# frozen_string_literal: true

require "set"

module Canon
  module Comparison
    # Single factory for DiffNode creation in the DOM comparison path.
    #
    # Centralises reason building, metadata enrichment (path, serialization,
    # attributes), and whitespace visualization — previously duplicated
    # across MarkupComparator and XmlComparator.
    class DiffNodeBuilder
      # Build an enriched DiffNode.
      def self.build(node1:, node2:, diff1:, diff2:, dimension:, **_opts)
        raise ArgumentError, "dimension required for DiffNode" if dimension.nil?

        reason = build_reason(node1, node2, diff1, diff2, dimension)
        metadata = enrich_metadata(node1, node2)

        Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: dimension,
          reason: reason,
          **metadata,
        )
      end

      # --- Reason building ---------------------------------------------------

      def self.build_reason(node1, node2, diff1, diff2, dimension)
        # Nil-node text content with namespace info
        if dimension == :text_content && (node1.nil? || node2.nil?)
          node = node1 || node2
          if node.is_a?(Canon::Xml::Node) || Canon::XmlParsing.xml_node?(node)
            ns = Canon::XmlParsing.namespace_uri(node)
            ns_info = ns.nil? || ns.empty? ? "" : " (namespace: #{ns})"
            label = Canon::Comparison.code_pair_label(diff1, diff2)
            return "element '#{node.name}'#{ns_info}: #{label}"
          end
        end

        case dimension
        when :attribute_presence
          build_attribute_difference_reason(
            extract_attributes(node1), extract_attributes(node2)
          )
        when :attribute_values
          build_attribute_values_reason(node1, node2)
        when :text_content
          build_text_difference_reason(
            extract_text_content(node1), extract_text_content(node2)
          )
        when :attribute_order
          build_attribute_order_reason(node1, node2)
        when :comments
          build_comment_difference_reason(node1,
                                          node2) || fallback_reason(diff1,
                                                                    diff2, dimension, node1, node2)
        when :whitespace_adjacency
          build_whitespace_adjacency_reason(node1, node2)
        else
          fallback_reason(diff1, diff2, dimension, node1, node2)
        end
      end

      # --- Metadata enrichment -----------------------------------------------

      def self.enrich_metadata(node1, node2)
        {
          path: Canon::Diff::PathBuilder.build(node1 || node2,
                                               format: :document),
          serialized_before: serialize(node1),
          serialized_after: serialize(node2),
          attributes_before: extract_attributes(node1),
          attributes_after: extract_attributes(node2),
        }
      end

      # --- Node queries (delegate to NodeSerializer) -------------------------

      def self.serialize(node)
        return nil if node.nil?

        Canon::Diff::NodeSerializer.serialize(node)
      end

      def self.extract_attributes(node)
        return nil if node.nil?

        Canon::Diff::NodeSerializer.extract_attributes(node)
      end

      # --- Attribute reason builders -----------------------------------------

      def self.build_attribute_difference_reason(attrs1, attrs2)
        unless attrs1 && attrs2
          return "#{attrs1&.keys&.size || 0} vs #{attrs2&.keys&.size || 0} attributes"
        end

        keys1 = attrs1.keys.to_set
        keys2 = attrs2.keys.to_set

        only_in_first = keys1 - keys2
        only_in_second = keys2 - keys1
        different_values = (keys1 & keys2).reject { |k| attrs1[k] == attrs2[k] }

        parts = []
        parts << "only in first: #{only_in_first.to_a.sort.join(', ')}" if only_in_first.any?
        parts << "only in second: #{only_in_second.to_a.sort.join(', ')}" if only_in_second.any?
        parts << "different values: #{different_values.sort.join(', ')}" if different_values.any?

        parts.empty? ? "#{keys1.size} vs #{keys2.size} attributes (same names)" : parts.join("; ")
      end

      def self.build_attribute_values_reason(node1, node2)
        attrs1 = extract_attributes(node1) || {}
        attrs2 = extract_attributes(node2) || {}

        differing = (attrs1.keys | attrs2.keys).sort.reject do |k|
          attrs1[k.to_s] == attrs2[k.to_s]
        end

        changed = differing.map do |k|
          "Changed: #{k}=\"#{attrs1[k.to_s]}\" → \"#{attrs2[k.to_s]}\""
        end

        changed.empty? ? "attributes differ" : "Attributes differ (#{changed.join('; ')})"
      end

      def self.build_attribute_order_reason(node1, node2)
        keys1 = extract_attributes(node1)&.keys || []
        keys2 = extract_attributes(node2)&.keys || []
        "Attribute order changed: [#{keys1.join(', ')}] → [#{keys2.join(', ')}]"
      end

      # --- Text content extraction -------------------------------------------

      def self.extract_text_content(node)
        return nil if node.nil?

        case node
        when Canon::Xml::Nodes::TextNode
          node.value
        when Canon::Xml::Node
          node.text_content
        else
          if Canon::XmlBackend.nokogiri? && node.is_a?(Nokogiri::XML::Node)
            node.content.to_s
          elsif Canon::XmlParsing.xml_node?(node)
            Canon::XmlParsing.text_content(node)
          else
            node.to_s
          end
        end
      rescue StandardError
        nil
      end

      # --- Text diff reason --------------------------------------------------

      def self.build_text_difference_reason(text1, text2)
        return "missing vs '#{truncate(text2)}'" if text1.nil? && text2
        return "'#{truncate(text1)}' vs missing" if text1 && text2.nil?
        return "both missing" if text1.nil? && text2.nil?

        if whitespace_only?(text1) && whitespace_only?(text2)
          return "whitespace: #{describe_whitespace(text1)} vs #{describe_whitespace(text2)}"
        end

        "Text: \"#{visualize_whitespace(text1)}\" vs \"#{visualize_whitespace(text2)}\""
      end

      # --- Comment reason ----------------------------------------------------

      def self.build_comment_difference_reason(node1, node2)
        cm1 = node1 && NodeInspector.comment_node?(node1)
        cm2 = node2 && NodeInspector.comment_node?(node2)

        return nil unless cm1 || cm2

        if cm1 && !cm2
          "Comment present on EXPECTED only: <!--#{truncate(comment_text(node1))}-->"
        elsif cm2 && !cm1
          "Comment present on ACTUAL only: <!--#{truncate(comment_text(node2))}-->"
        else
          t1 = truncate(comment_text(node1))
          t2 = truncate(comment_text(node2))
          "Comment text differs: <!--#{t1}--> vs <!--#{t2}-->"
        end
      end

      def self.comment_text(node)
        NodeInspector.text_content(node).to_s
      end

      # --- Whitespace adjacency reason (#137) --------------------------------

      def self.build_whitespace_adjacency_reason(node1, node2)
        text1 = extract_text_content(node1)
        text2 = extract_text_content(node2)

        ws_on_first = NodeInspector.whitespace_only_text?(node1) &&
          !NodeInspector.whitespace_only_text?(node2)
        ws_on_second = NodeInspector.whitespace_only_text?(node2) &&
          !NodeInspector.whitespace_only_text?(node1)

        unless ws_on_first || ws_on_second
          return build_text_difference_reason(text1, text2)
        end

        if ws_on_first
          build_adjacency_side(text1, text2, node1, "EXPECTED", "ACTUAL")
        else
          build_adjacency_side(text2, text1, node2, "ACTUAL", "EXPECTED")
        end
      end

      # --- Whitespace visualization ------------------------------------------

      def self.visualize_whitespace(text)
        return "" if text.nil?

        viz_map = character_visualization_map
        text.chars.map { |char| viz_map[char] || char }.join
      end

      def self.describe_whitespace(text)
        return "0 chars" if text.nil? || text.empty?

        char_count = text.length
        parts = []
        parts << "#{text.count("\n")} newlines" if text.include?("\n")
        parts << "#{text.count(' ')} spaces" if text.include?(" ")
        parts << "#{text.count("\t")} tabs" if text.include?("\t")

        "#{char_count} chars (#{parts.join(', ')})"
      end

      def self.whitespace_only?(text)
        return false if text.nil?

        text.to_s.strip.empty?
      end

      def self.truncate(text, max_length = 40)
        return "" if text.nil?

        text = text.to_s
        return text if text.length <= max_length

        "#{text[0...max_length]}..."
      end

      # --- Private helpers ---------------------------------------------------

      # Default reason when no dimension-specific handler matched.
      def self.fallback_reason(diff1, diff2, dimension, node1, node2)
        if diff1 == Canon::Comparison::MISSING_NODE && diff2 == Canon::Comparison::MISSING_NODE
          "element structure mismatch (children differ)"
        elsif dimension == :element_structure &&
            diff1 == Canon::Comparison::UNEQUAL_ELEMENTS &&
            diff2 == Canon::Comparison::UNEQUAL_ELEMENTS &&
            (node1.is_a?(Canon::Xml::Node) || Canon::XmlParsing.xml_node?(node1)) &&
            (node2.is_a?(Canon::Xml::Node) || Canon::XmlParsing.xml_node?(node2)) &&
            node1.name && node2.name && node1.name != node2.name
          "different element name (<#{node1.name}> vs <#{node2.name}>)"
        else
          Canon::Comparison.code_pair_label(diff1, diff2)
        end
      end
      private_class_method :fallback_reason

      # Build one side of a whitespace-adjacency reason.
      def self.build_adjacency_side(ws_text, content_text, ws_node,
present_side, absent_side)
        ws_vis = visualize_whitespace(ws_text)

        if content_text.nil? || content_text.strip.empty?
          parent_label = whitespace_adjacency_parent_label(ws_node)
          "Whitespace inside #{parent_label}: " \
            "present on #{present_side} (\"#{ws_vis}\"), absent on #{absent_side}"
        else
          direction = whitespace_partner_direction(ws_node)
          content_vis = visualize_whitespace(truncate(content_text))
          "Whitespace #{direction} \"#{content_vis}\": " \
            "present on #{present_side} (\"#{ws_vis}\"), absent on #{absent_side}"
        end
      end
      private_class_method :build_adjacency_side

      def self.whitespace_adjacency_parent_label(ws_node)
        parent = NodeInspector.parent(ws_node)
        return "(unknown parent)" unless parent

        name = parent.name
        name && !name.empty? ? "<#{name}>" : "(unknown parent)"
      end
      private_class_method :whitespace_adjacency_parent_label

      # Direction of the partner content relative to the whitespace node.
      def self.whitespace_partner_direction(ws_node)
        parent = NodeInspector.parent(ws_node)
        return "adjacent to" unless parent

        siblings = parent.children
        idx = siblings.index(ws_node)
        return "adjacent to" unless idx

        if non_ws_sibling_exists?(siblings, idx, 1) then "before"
        elsif non_ws_sibling_exists?(siblings, idx, -1) then "after"
        else "adjacent to"
        end
      end
      private_class_method :whitespace_partner_direction

      def self.non_ws_sibling_exists?(siblings, idx, direction)
        i = idx + direction
        while i >= 0 && i < siblings.length
          s = siblings[i]
          is_ws_text = NodeInspector.text_node?(s) &&
            NodeInspector.text_content(s).strip.empty?
          return true unless is_ws_text

          i += direction
        end
        false
      end
      private_class_method :non_ws_sibling_exists?

      # Lazy-loaded character visualization map from YAML.
      def self.character_visualization_map
        @character_visualization_map ||= begin
          require "yaml"
          lib_root = File.expand_path("../..", __dir__)
          yaml_path = File.join(lib_root,
                                "canon/diff_formatter/character_map.yml")
          data = YAML.load_file(yaml_path)

          data["characters"].each_with_object({}) do |char_data, map|
            char = if char_data["unicode"]
                     [char_data["unicode"].to_i(16)].pack("U")
                   else
                     char_data["character"]
                   end
            map[char] = char_data["visualization"]
          end
        end
      end
      private_class_method :character_visualization_map
    end
  end
end
