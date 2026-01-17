# frozen_string_literal: true

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Dimension-specific formatting
      #
      # Formats details for specific comparison dimensions.
      module DimensionFormatter
        # Format dimension details based on diff type
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [String] Formatted dimension details
        def self.format_dimension_details(diff, use_color)
          dimension = extract_dimension(diff)

          case dimension
          when :namespace_uri
            format_namespace_uri_details(diff, use_color)
          when :namespace_declarations
            format_namespace_declarations_details(diff, use_color)
          when :element_structure
            format_element_structure_details(diff, use_color)
          when :attribute_presence
            format_attribute_presence_details(diff, use_color)
          when :attribute_values
            format_attribute_values_details(diff, use_color)
          when :attribute_order
            format_attribute_order_details(diff, use_color)
          when :text_content
            format_text_content_details(diff, use_color)
          when :structural_whitespace
            format_structural_whitespace_details(diff, use_color)
          when :comments
            format_comments_details(diff, use_color)
          when :hash_diff
            format_hash_diff_details(diff, use_color)
          else
            format_fallback_details(diff, use_color)
          end
        end

        # Format namespace URI differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_namespace_uri_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          # Use NamespaceHelper for consistent formatting
          ns1_display = Canon::Xml::NamespaceHelper.format_namespace(
            NodeUtils.get_namespace_uri_for_display(node1),
          )
          ns2_display = Canon::Xml::NamespaceHelper.format_namespace(
            NodeUtils.get_namespace_uri_for_display(node2),
          )

          element_name = NodeUtils.get_element_name_for_display(node1) || "element"

          detail1 = "<#{element_name}> #{ColorHelper.colorize(ns1_display, :cyan, use_color)}"
          detail2 = "<#{element_name}> #{ColorHelper.colorize(ns2_display, :cyan, use_color)}"

          changes = "Namespace differs: #{ColorHelper.colorize(ns1_display, :red, use_color)} → " \
                    "#{ColorHelper.colorize(ns2_display, :green, use_color)}"

          [detail1, detail2, changes]
        end

        # Format namespace declaration differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_namespace_declarations_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"
          require_relative "text_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          # Extract namespace declarations from both nodes
          ns_decls1 = extract_namespace_declarations_from_node(node1)
          ns_decls2 = extract_namespace_declarations_from_node(node2)

          element_name = NodeUtils.get_element_name_for_display(node1) || "element"

          # Format namespace declarations for display
          detail1 = if ns_decls1.empty?
                      "<#{element_name}> #{ColorHelper.colorize(
                        '(no namespace declarations)', :red, use_color
                      )}"
                    else
                      ns_str = ns_decls1.map do |prefix, uri|
                        attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
                        "#{attr_name}=\"#{uri}\""
                      end.join(" ")
                      "<#{element_name}> #{ns_str}"
                    end

          detail2 = if ns_decls2.empty?
                      "<#{element_name}> #{ColorHelper.colorize(
                        '(no namespace declarations)', :green, use_color
                      )}"
                    else
                      ns_str = ns_decls2.map do |prefix, uri|
                        attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
                        "#{attr_name}=\"#{uri}\""
                      end.join(" ")
                      "<#{element_name}> #{ns_str}"
                    end

          # Analyze changes
          missing = ns_decls1.keys - ns_decls2.keys
          extra = ns_decls2.keys - ns_decls1.keys
          changed = ns_decls1.select { |k, v| ns_decls2[k] && ns_decls2[k] != v }.keys

          # Format changes
          changes_parts = []
          if missing.any?
            missing_str = missing.map do |prefix|
              attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
              ColorHelper.colorize("-#{attr_name}=\"#{ns_decls1[prefix]}\"", :red, use_color)
            end.join(", ")
            changes_parts << "Removed: #{missing_str}"
          end
          if extra.any?
            extra_str = extra.map do |prefix|
              attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
              ColorHelper.colorize("+#{attr_name}=\"#{ns_decls2[prefix]}\"", :green, use_color)
            end.join(", ")
            changes_parts << "Added: #{extra_str}"
          end
          if changed.any?
            changed_str = changed.map do |prefix|
              attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
              "#{ColorHelper.colorize(attr_name, :cyan, use_color)}: " \
              "\"#{ns_decls1[prefix]}\" → \"#{ns_decls2[prefix]}\""
            end.join(", ")
            changes_parts << "Changed: #{changed_str}"
          end

          changes = changes_parts.join(" | ")

          [detail1, detail2, changes]
        end

        # Format element structure differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_element_structure_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          name1 = NodeUtils.get_element_name_for_display(node1)
          name2 = NodeUtils.get_element_name_for_display(node2)

          detail1 = "<#{ColorHelper.colorize(name1, :red, use_color)}>"
          detail2 = "<#{ColorHelper.colorize(name2, :green, use_color)}>"

          changes = "Element differs: #{ColorHelper.colorize(name1, :red, use_color)} → " \
                    "#{ColorHelper.colorize(name2, :green, use_color)}"

          [detail1, detail2, changes]
        end

        # Format attribute presence differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_attribute_presence_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          attrs1 = NodeUtils.get_attribute_names(node1).sort
          attrs2 = NodeUtils.get_attribute_names(node2).sort

          missing = attrs1 - attrs2
          extra = attrs2 - attrs1

          # Format the attribute lists
          detail1 = if attrs1.empty?
                      ColorHelper.colorize("(no attributes)", :red, use_color)
                    else
                      attrs1.map { |a| ColorHelper.colorize(a, :red, use_color) }.join(", ")
                    end

          detail2 = if attrs2.empty?
                      ColorHelper.colorize("(no attributes)", :green, use_color)
                    else
                      attrs2.map { |a| ColorHelper.colorize(a, :green, use_color) }.join(", ")
                    end

          # Build changes description
          changes_parts = []
          if missing.any?
            missing_str = missing.map { |a| ColorHelper.colorize("-#{a}", :red, use_color) }.join(", ")
            changes_parts << "Missing: #{missing_str}"
          end
          if extra.any?
            extra_str = extra.map { |a| ColorHelper.colorize("+#{a}", :green, use_color) }.join(", ")
            changes_parts << "Extra: #{extra_str}"
          end

          changes = changes_parts.join(" | ")

          [detail1, detail2, changes]
        end

        # Format attribute value differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_attribute_values_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          differing = NodeUtils.find_all_differing_attributes(node1, node2)

          # Format all differing attributes
          attrs1_parts = []
          attrs2_parts = []
          changes_parts = []

          differing.each do |attr_name|
            val1 = NodeUtils.get_attribute_value(node1, attr_name)
            val2 = NodeUtils.get_attribute_value(node2, attr_name)

            attrs1_parts << "#{attr_name}=#{format_json_value(val1)}"
            attrs2_parts << "#{attr_name}=#{format_json_value(val2)}"
            changes_parts << "#{attr_name}: #{ColorHelper.colorize(format_json_value(val1), :red, use_color)} → " \
                             "#{ColorHelper.colorize(format_json_value(val2), :green, use_color)}"
          end

          detail1 = attrs1_parts.join(", ")
          detail2 = attrs2_parts.join(", ")
          changes = changes_parts.join(" | ")

          [detail1, detail2, changes]
        end

        # Format attribute order differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_attribute_order_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          order1 = NodeUtils.get_attribute_names_in_order(node1)
          order2 = NodeUtils.get_attribute_names_in_order(node2)

          detail1 = order1.map { |a| ColorHelper.colorize(a, :red, use_color) }.join(", ")
          detail2 = order2.map { |a| ColorHelper.colorize(a, :green, use_color) }.join(", ")

          changes = "Order differs: #{ColorHelper.colorize(order1.join(', '), :red, use_color)} → " \
                    "#{ColorHelper.colorize(order2.join(', '), :green, use_color)}"

          [detail1, detail2, changes]
        end

        # Format text content differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_text_content_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"
          require_relative "text_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          text1 = NodeUtils.get_node_text(node1)
          text2 = NodeUtils.get_node_text(node2)

          if NodeUtils.inside_preserve_element?(node1) || NodeUtils.inside_preserve_element?(node2)
            detail1 = ColorHelper.colorize(TextUtils.visualize_whitespace(text1), :red, use_color)
            detail2 = ColorHelper.colorize(TextUtils.visualize_whitespace(text2), :green, use_color)
          else
            detail1 = ColorHelper.colorize(format_json_value(text1), :red, use_color)
            detail2 = ColorHelper.colorize(format_json_value(text2), :green, use_color)
          end

          changes = "Content differs: #{detail1} → #{detail2}"

          [detail1, detail2, changes]
        end

        # Format structural whitespace differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_structural_whitespace_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"
          require_relative "text_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          text1 = NodeUtils.get_node_text(node1)
          text2 = NodeUtils.get_node_text(node2)

          detail1 = ColorHelper.colorize(TextUtils.visualize_whitespace(text1), :red, use_color)
          detail2 = ColorHelper.colorize(TextUtils.visualize_whitespace(text2), :green, use_color)

          changes = "Whitespace differs: #{detail1} → #{detail2}"

          [detail1, detail2, changes]
        end

        # Format comment differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_comments_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          text1 = NodeUtils.get_node_text(node1)
          text2 = NodeUtils.get_node_text(node2)

          detail1 = ColorHelper.colorize(format_json_value(text1), :red, use_color)
          detail2 = ColorHelper.colorize(format_json_value(text2), :green, use_color)

          changes = "Comment differs: #{detail1} → #{detail2}"

          [detail1, detail2, changes]
        end

        # Format hash differences
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_hash_diff_details(diff, use_color)
          require_relative "color_helper"

          detail1 = if diff.is_a?(Hash) && diff[:value1]
                      ColorHelper.colorize(format_json_value(diff[:value1]), :red, use_color)
                    else
                      ColorHelper.colorize("(no value)", :red, use_color)
                    end

          detail2 = if diff.is_a?(Hash) && diff[:value2]
                      ColorHelper.colorize(format_json_value(diff[:value2]), :green, use_color)
                    else
                      ColorHelper.colorize("(no value)", :green, use_color)
                    end

          path_str = if diff.is_a?(Hash) && diff[:path]
                       " at #{diff[:path]}"
                     else
                       ""
                     end

          changes = "Value differs#{path_str}: #{detail1} → #{detail2}"

          [detail1, detail2, changes]
        end

        # Format fallback details for unknown dimensions
        #
        # @param diff [DiffNode, Hash] Difference node
        # @param use_color [Boolean] Whether to use colors
        # @return [Array] Tuple of [detail1, detail2, changes]
        def self.format_fallback_details(diff, use_color)
          require_relative "color_helper"
          require_relative "node_utils"

          node1 = extract_node1(diff)
          node2 = extract_node2(diff)

          detail1 = ColorHelper.colorize(NodeUtils.format_node_brief(node1), :red, use_color)
          detail2 = ColorHelper.colorize(NodeUtils.format_node_brief(node2), :green, use_color)

          dimension = extract_dimension(diff)
          changes = "#{dimension.to_s.capitalize} differs: #{detail1} → #{detail2}"

          [detail1, detail2, changes]
        end

        # Format JSON value for display
        #
        # @param value [Object] Value to format
        # @return [String] Formatted value
        def self.format_json_value(value)
          require "json"

          case value
          when String
            # Escape for display
            escaped = value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n",
                                                                       "\\n")
            "\"#{escaped}\""
          when Numeric, TrueClass, FalseClass, NilClass
            value.to_s
          else
            # Use JSON.pretty_generate for complex types
            JSON.pretty_generate(value)
          end
        rescue StandardError
          value.inspect
        end

        # Extract dimension from diff
        #
        # @param diff [DiffNode, Hash] Difference node
        # @return [Symbol] Dimension
        def self.extract_dimension(diff)
          if diff.respond_to?(:dimension)
            diff.dimension
          elsif diff.is_a?(Hash)
            diff[:dimension] || diff[:diff_code] || :unknown
          else
            :unknown
          end
        end

        # Extract node1 from diff
        #
        # @param diff [DiffNode, Hash] Difference node
        # @return [Object] Node1
        def self.extract_node1(diff)
          if diff.respond_to?(:node1)
            diff.node1
          elsif diff.is_a?(Hash)
            diff[:node1]
          end
        end

        # Extract node2 from diff
        #
        # @param diff [DiffNode, Hash] Difference node
        # @return [Object] Node2
        def self.extract_node2(diff)
          if diff.respond_to?(:node2)
            diff.node2
          elsif diff.is_a?(Hash)
            diff[:node2]
          end
        end

        # Extract namespace declarations from a node
        #
        # @param node [Object] Node to extract from
        # @return [Hash] Namespace declarations
        def self.extract_namespace_declarations_from_node(node)
          return {} unless node

          declarations = {}

          # Handle Canon::Xml::Node (uses namespace_nodes)
          if node.respond_to?(:namespace_nodes)
            node.namespace_nodes.each do |ns|
              next if ns.prefix == "xml" && ns.uri == "http://www.w3.org/XML/1998/namespace"

              prefix = ns.prefix || ""
              declarations[prefix] = ns.uri
            end
            return declarations
          end

          # Handle Nokogiri/Moxml nodes (use attributes)
          raw_attrs = node.respond_to?(:attribute_nodes) ? node.attribute_nodes : node.attributes

          if raw_attrs.is_a?(Array)
            raw_attrs.each do |attr|
              name = attr.respond_to?(:name) ? attr.name : attr.to_s
              value = attr.respond_to?(:value) ? attr.value : attr.to_s

              if namespace_declaration?(name)
                prefix = name == "xmlns" ? "" : name.split(":", 2)[1]
                declarations[prefix] = value
              end
            end
          elsif raw_attrs.respond_to?(:each)
            raw_attrs.each do |key, val|
              name = if key.is_a?(String)
                       key
                     else
                       (key.respond_to?(:name) ? key.name : key.to_s)
                     end
              value = if val.respond_to?(:value)
                        val.value
                      elsif val.respond_to?(:content)
                        val.content
                      else
                        val.to_s
                      end

              if namespace_declaration?(name)
                prefix = name == "xmlns" ? "" : name.split(":", 2)[1]
                declarations[prefix] = value
              end
            end
          end

          declarations
        end

        # Check if an attribute name is a namespace declaration
        #
        # @param name [String] Attribute name
        # @return [Boolean] true if namespace declaration
        def self.namespace_declaration?(name)
          name == "xmlns" || name.to_s.start_with?("xmlns:")
        end
      end
    end
  end
end
