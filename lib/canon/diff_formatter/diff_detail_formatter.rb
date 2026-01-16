# frozen_string_literal: true

require "paint"
require_relative "../xml/namespace_helper"

module Canon
  class DiffFormatter
    # Formats dimension-specific detail for individual differences
    # Provides actionable, colorized output showing exactly what changed
    module DiffDetailFormatter
      class << self
        # Format all differences as a semantic diff report
        #
        # @param differences [Array<DiffNode>] Array of differences
        # @param use_color [Boolean] Whether to use colors
        # @return [String] Formatted semantic diff report
        def format_report(differences, use_color: true)
          return "" if differences.empty?

          # Group differences by normative status
          normative = differences.select do |diff|
            diff.respond_to?(:normative?) ? diff.normative? : true
          end
          informative = differences.select do |diff|
            diff.respond_to?(:normative?) && !diff.normative?
          end

          output = []
          output << ""
          output << colorize("=" * 70, :cyan, use_color, bold: true)
          output << colorize(
            "  SEMANTIC DIFF REPORT (#{differences.length} #{differences.length == 1 ? 'difference' : 'differences'})", :cyan, use_color, bold: true
          )
          output << colorize("=" * 70, :cyan, use_color, bold: true)

          # Show normative differences first
          if normative.any?
            output << ""
            output << colorize(
              "┌─ NORMATIVE DIFFERENCES (#{normative.length}) ─┐", :green, use_color, bold: true
            )

            normative.each_with_index do |diff, i|
              output << ""
              output << format_single_diff(diff, i + 1, normative.length,
                                           use_color, section: "NORMATIVE")
            end
          end

          # Show informative differences second
          if informative.any?
            output << ""
            output << ""
            output << colorize(
              "┌─ INFORMATIVE DIFFERENCES (#{informative.length}) ─┐", :yellow, use_color, bold: true
            )

            informative.each_with_index do |diff, i|
              output << ""
              output << format_single_diff(diff, i + 1, informative.length,
                                           use_color, section: "INFORMATIVE")
            end
          end

          output << ""
          output << colorize("=" * 70, :cyan, use_color, bold: true)
          output << ""

          output.join("\n")
        end

        private

        # Format a single difference with dimension-specific details
        def format_single_diff(diff, number, total, use_color, section: nil)
          output = []

          # Header - handle both DiffNode and Hash
          status = section || (if diff.respond_to?(:normative?)
                                 diff.normative? ? "NORMATIVE" : "INFORMATIVE"
                               else
                                 "NORMATIVE" # Hash diffs are always normative
                               end)
          status_color = status == "NORMATIVE" ? :green : :yellow
          output << colorize("🔍 DIFFERENCE ##{number}/#{total} [#{status}]",
                             status_color, use_color, bold: true)
          output << colorize("─" * 70, :cyan, use_color)

          # Dimension - handle both DiffNode and Hash
          dimension = if diff.respond_to?(:dimension)
                        diff.dimension
                      elsif diff.is_a?(Hash)
                        diff[:diff_code] || diff[:dimension] || "unknown"
                      else
                        "unknown"
                      end
          output << "#{colorize('Dimension:', :cyan, use_color,
                                bold: true)} #{colorize(dimension.to_s,
                                                        :magenta, use_color)}"

          # Location (XPath for XML/HTML, Path for JSON/YAML)
          location = extract_location(diff)
          output << "#{colorize('Location:', :cyan, use_color,
                                bold: true)}  #{colorize(location, :blue,
                                                         use_color)}"
          output << ""

          # Dimension-specific details
          detail1, detail2, changes = format_dimension_details(diff,
                                                               use_color)

          output << colorize("⊖ Expected (File 1):", :red, use_color,
                             bold: true)
          output << "   #{detail1}"
          output << ""
          output << colorize("⊕ Actual (File 2):", :green, use_color,
                             bold: true)
          output << "   #{detail2}"

          if changes && !changes.empty?
            output << ""
            output << colorize("✨ Changes:", :yellow, use_color, bold: true)
            output << "   #{changes}"
          end

          output.join("\n")
        rescue StandardError => e
          # Safe fallback if formatting fails - provide detailed context
          location = begin
            extract_location(diff)
          rescue StandardError
            "(unable to extract location)"
          end

          dimension = begin
            diff.respond_to?(:dimension) ? diff.dimension : "unknown"
          rescue StandardError
            "unknown"
          end

          error_msg = [
            "🔍 DIFFERENCE ##{number}/#{total} [Error formatting diff]",
            "",
            "Location: #{location}",
            "Dimension: #{dimension}",
            "",
            "Error: #{e.message}",
            "",
            "This is likely a bug in the diff formatter. Please report this issue",
            "with the above information.",
          ].join("\n")

          colorize(error_msg, :red, use_color, bold: true)
        end

        # Extract XPath or JSON path for the difference location
        # Uses enriched path from DiffNode if available (with ordinal indices)
        def extract_location(diff)
          # For Hash diffs (JSON/YAML)
          if diff.is_a?(Hash)
            return diff[:path] || "(root)"
          end

          # For DiffNode (XML/HTML) - use enriched path if available
          if diff.respond_to?(:path) && diff.path
            return diff.path
          end

          # Fallback: extract from node (legacy path)
          node = diff.respond_to?(:node1) ? (diff.node1 || diff.node2) : nil

          # For XML/HTML element nodes
          if node.respond_to?(:name)
            return extract_xpath(node)
          end

          # Final fallback
          if diff.respond_to?(:dimension)
            diff.dimension.to_s
          else
            "(unknown)"
          end
        end

        # Extract XPath from an XML/HTML node
        def extract_xpath(node)
          return "/" if node.nil?

          # Document nodes don't have meaningful XPaths
          if node.is_a?(Nokogiri::XML::Document) ||
              node.is_a?(Nokogiri::HTML::Document) ||
              node.is_a?(Nokogiri::HTML4::Document) ||
              node.is_a?(Nokogiri::HTML5::Document)
            return "/"
          end

          parts = []
          current = node
          max_depth = 100
          depth = 0

          begin
            while current.respond_to?(:name) && current.name && depth < max_depth
              # Stop at document-level nodes
              break if ["document", "#document"].include?(current.name)
              break if current.is_a?(Nokogiri::XML::Document) ||
                current.is_a?(Nokogiri::HTML::Document)

              parts.unshift(current.name)

              # Move to parent safely
              break unless current.respond_to?(:parent)

              parent = begin
                current.parent
              rescue StandardError
                nil
              end

              break unless parent
              break if parent == current

              current = parent
              depth += 1
            end
          rescue StandardError
            # If any error, return what we have
            return "/#{parts.join('/')}"
          end

          "/#{parts.join('/')}"
        end

        # Format details based on dimension type
        def format_dimension_details(diff, use_color)
          # Handle Hash diffs (JSON/YAML)
          if diff.is_a?(Hash)
            return format_hash_diff_details(diff, use_color)
          end

          # Handle DiffNode (XML/HTML)
          dimension = diff.respond_to?(:dimension) ? diff.dimension : nil

          case dimension
          when :element_structure
            format_element_structure_details(diff, use_color)
          when :attribute_presence
            format_attribute_presence_details(diff, use_color)
          when :attribute_values
            format_attribute_values_details(diff, use_color)
          when :attribute_order
            format_attribute_order_details(diff, use_color)
          when :namespace_uri
            format_namespace_uri_details(diff, use_color)
          when :namespace_declarations
            format_namespace_declarations_details(diff, use_color)
          when :text_content
            format_text_content_details(diff, use_color)
          when :structural_whitespace
            format_structural_whitespace_details(diff, use_color)
          when :comments
            format_comments_details(diff, use_color)
          else
            format_fallback_details(diff, use_color)
          end
        end

        # Format namespace_uri dimension details
        def format_namespace_uri_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Use NamespaceHelper for consistent formatting
          ns1_display = Canon::Xml::NamespaceHelper.format_namespace(
            node1.respond_to?(:namespace_uri) ? node1.namespace_uri : nil,
          )
          ns2_display = Canon::Xml::NamespaceHelper.format_namespace(
            node2.respond_to?(:namespace_uri) ? node2.namespace_uri : nil,
          )

          element_name = if node1.respond_to?(:name)
                           node1.name
                         else
                           node2.respond_to?(:name) ? node2.name : "element"
                         end

          detail1 = "<#{element_name}> #{colorize(ns1_display, :cyan,
                                                  use_color)}"
          detail2 = "<#{element_name}> #{colorize(ns2_display, :cyan,
                                                  use_color)}"

          changes = "Namespace differs: #{colorize(ns1_display, :red,
                                                   use_color)} → #{colorize(
                                                     ns2_display, :green, use_color
                                                   )}"

          [detail1, detail2, changes]
        end

        # Format namespace_declarations dimension details
        def format_namespace_declarations_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Extract namespace declarations from both nodes
          ns_decls1 = extract_namespace_declarations_from_node(node1)
          ns_decls2 = extract_namespace_declarations_from_node(node2)

          element_name = if node1.respond_to?(:name)
                           node1.name
                         else
                           node2.respond_to?(:name) ? node2.name : "element"
                         end

          # Format namespace declarations for display
          detail1 = if ns_decls1.empty?
                      "<#{element_name}> #{colorize(
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
                      "<#{element_name}> #{colorize(
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
          missing = ns_decls1.keys - ns_decls2.keys  # In node1 but not node2
          extra = ns_decls2.keys - ns_decls1.keys    # In node2 but not node1
          changed = ns_decls1.select do |prefix, uri|
            ns_decls2[prefix] && ns_decls2[prefix] != uri
          end.keys

          # Format changes
          changes_parts = []
          if missing.any?
            missing_str = missing.map do |prefix|
              attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
              colorize("-#{attr_name}=\"#{ns_decls1[prefix]}\"", :red,
                       use_color)
            end.join(", ")
            changes_parts << "Removed: #{missing_str}"
          end
          if extra.any?
            extra_str = extra.map do |prefix|
              attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
              colorize("+#{attr_name}=\"#{ns_decls2[prefix]}\"", :green,
                       use_color)
            end.join(", ")
            changes_parts << "Added: #{extra_str}"
          end
          if changed.any?
            changed_str = changed.map do |prefix|
              attr_name = prefix.empty? ? "xmlns" : "xmlns:#{prefix}"
              "#{colorize(attr_name, :cyan,
                          use_color)}: \"#{ns_decls1[prefix]}\" → \"#{ns_decls2[prefix]}\""
            end.join(", ")
            changes_parts << "Changed: #{changed_str}"
          end

          changes = changes_parts.join(" | ")

          [detail1, detail2, changes]
        end

        # Extract namespace declarations from a node (helper for formatter)
        # @param node [Object] Node to extract namespace declarations from
        # @return [Hash] Hash of prefix => URI mappings
        def extract_namespace_declarations_from_node(node)
          return {} if node.nil?

          declarations = {}

          # Handle Canon::Xml::Node (uses namespace_nodes)
          if node.respond_to?(:namespace_nodes)
            node.namespace_nodes.each do |ns|
              # Skip the implicit xml namespace (always present)
              next if ns.prefix == "xml" && ns.uri == "http://www.w3.org/XML/1998/namespace"

              prefix = ns.prefix || ""
              declarations[prefix] = ns.uri
            end
            return declarations
          end

          # Handle Nokogiri/Moxml nodes (use attributes)
          # Get raw attributes
          raw_attrs = if node.respond_to?(:attribute_nodes)
                        node.attribute_nodes
                      elsif node.respond_to?(:attributes)
                        node.attributes
                      else
                        return {}
                      end

          # Handle Canon::Xml::Node attribute format (array of AttributeNode)
          if raw_attrs.is_a?(Array)
            raw_attrs.each do |attr|
              name = attr.name
              value = attr.value

              if name == "xmlns" || name.start_with?("xmlns:")
                # Extract prefix: "xmlns" -> "", "xmlns:xmi" -> "xmi"
                prefix = name == "xmlns" ? "" : name.split(":", 2)[1]
                declarations[prefix] = value
              end
            end
          else
            # Handle Nokogiri and Moxml attribute formats (Hash-like)
            raw_attrs.each do |key, val|
              if key.is_a?(String)
                # Nokogiri format: key=name (String), val=attr object
                name = key
                value = val.respond_to?(:value) ? val.value : val.to_s
              else
                # Moxml format: key=attr object, val=nil
                name = key.respond_to?(:name) ? key.name : key.to_s
                value = key.respond_to?(:value) ? key.value : key.to_s
              end

              if name == "xmlns" || name.start_with?("xmlns:")
                # Extract prefix: "xmlns" -> "", "xmlns:xmi" -> "xmi"
                prefix = name == "xmlns" ? "" : name.split(":", 2)[1]
                declarations[prefix] = value
              end
            end
          end

          declarations
        end

        # Format element_structure dimension details (INSERT/DELETE operations)
        # Uses enriched serialized content from DiffNode when available
        def format_element_structure_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Use enriched serialized content if available
          serialized_before = diff.respond_to?(:serialized_before) ? diff.serialized_before : nil
          serialized_after = diff.respond_to?(:serialized_after) ? diff.serialized_after : nil

          # Determine operation type
          if node1.nil? && !node2.nil?
            # INSERT operation - show content preview
            node2.respond_to?(:name) ? node2.name : "element"
            # Use serialized_after if available, otherwise extract from node
            content_preview = serialized_after || extract_content_preview(
              node2, 50
            )
            detail1 = colorize("(not present)", :red, use_color)
            detail2 = content_preview
            changes = "Element inserted"
          elsif !node1.nil? && node2.nil?
            # DELETE operation - show content preview
            node1.respond_to?(:name) ? node1.name : "element"
            # Use serialized_before if available, otherwise extract from node
            content_preview = serialized_before || extract_content_preview(
              node1, 50
            )
            detail1 = content_preview
            detail2 = colorize("(not present)", :green, use_color)
            changes = "Element deleted"
          elsif !node1.nil? && !node2.nil?
            # STRUCTURAL CHANGE (both nodes present) - show both previews
            name1 = node1.respond_to?(:name) ? node1.name : "element"
            name2 = node2.respond_to?(:name) ? node2.name : "element"
            # Use enriched serialized content if available
            detail1 = serialized_before || extract_content_preview(node1, 50)
            detail2 = serialized_after || extract_content_preview(node2, 50)

            changes = if name1 == name2
                        "Element structure changed"
                      else
                        "Element type changed: #{name1} → #{name2}"
                      end
          else
            # Both nil (shouldn't happen)
            detail1 = "(nil)"
            detail2 = "(nil)"
            changes = "Unknown structural change"
          end

          [detail1, detail2, changes]
        end

        # Format attribute_presence dimension details
        def format_attribute_presence_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          attrs1 = get_attribute_names(node1)
          attrs2 = get_attribute_names(node2)

          attrs1 & attrs2
          missing = attrs1 - attrs2  # In node1 but not node2
          extra = attrs2 - attrs1    # In node2 but not node1

          # Format expected
          detail1 = "<#{node1.name}> with #{attrs1.length} #{attrs1.length == 1 ? 'attribute' : 'attributes'}: #{attrs1.join(', ')}"

          # Format actual
          detail2 = "<#{node2.name}> with #{attrs2.length} #{attrs2.length == 1 ? 'attribute' : 'attributes'}: #{attrs2.join(', ')}"

          # Format changes
          changes_parts = []
          if extra.any?
            extra_str = extra.map do |a|
              colorize("+#{a}", :green, use_color)
            end.join(", ")
            changes_parts << "Added: #{extra_str}"
          end
          if missing.any?
            missing_str = missing.map do |a|
              colorize("-#{a}", :red, use_color)
            end.join(", ")
            changes_parts << "Removed: #{missing_str}"
          end

          changes = changes_parts.join(" | ")

          [detail1, detail2, changes]
        end

        # Format attribute_values dimension details
        # Uses enriched attributes from DiffNode when available
        def format_attribute_values_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Use enriched attributes if available
          attrs1_before = diff.respond_to?(:attributes_before) ? diff.attributes_before : nil
          attrs2_after = diff.respond_to?(:attributes_after) ? diff.attributes_after : nil

          # Find ALL attributes with different values
          # Use enriched attributes if available, otherwise extract from nodes
          if attrs1_before && attrs2_after
            # Use enriched attributes
            all_keys = (attrs1_before.keys + attrs2_after.keys).uniq
            differing_attrs = all_keys.reject do |key|
              attrs1_before[key] == attrs2_after[key]
            end
          else
            # Fallback to extracting from nodes
            differing_attrs = find_all_differing_attributes(node1, node2)
          end

          if differing_attrs.any?
            # Show element name with all differing attributes
            attrs1_str = differing_attrs.map do |attr|
              val1 = if attrs1_before
                       attrs1_before[attr]
                     else
                       get_attribute_value(
                         node1, attr
                       )
                     end
              "#{colorize(attr, :cyan, use_color)}=\"#{escape_quotes(val1)}\""
            end.join(" ")

            attrs2_str = differing_attrs.map do |attr|
              val2 = if attrs2_after
                       attrs2_after[attr]
                     else
                       get_attribute_value(
                         node2, attr
                       )
                     end
              "#{colorize(attr, :cyan, use_color)}=\"#{escape_quotes(val2)}\""
            end.join(" ")

            detail1 = "<#{node1.name}> #{attrs1_str}"
            detail2 = "<#{node2.name}> #{attrs2_str}"

            # List all attribute changes
            changes_parts = differing_attrs.map do |attr|
              val1 = if attrs1_before
                       attrs1_before[attr]
                     else
                       get_attribute_value(
                         node1, attr
                       )
                     end
              val2 = if attrs2_after
                       attrs2_after[attr]
                     else
                       get_attribute_value(
                         node2, attr
                       )
                     end

              if val1.empty? && !val2.empty?
                "#{colorize(attr, :cyan,
                            use_color)}: (added) → \"#{escape_quotes(val2)}\""
              elsif !val1.empty? && val2.empty?
                "#{colorize(attr, :cyan,
                            use_color)}: \"#{escape_quotes(val1)}\" → (removed)"
              else
                "#{colorize(attr, :cyan,
                            use_color)}: \"#{escape_quotes(val1)}\" → \"#{escape_quotes(val2)}\""
              end
            end

            changes = changes_parts.join("; ")

            [detail1, detail2, changes]
          else
            ["<#{node1.name}> (values differ)",
             "<#{node2.name}> (values differ)", nil]
          end
        end

        # Format attribute_order dimension details
        def format_attribute_order_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Get attribute names in order
          attrs1 = get_attribute_names_in_order(node1)
          attrs2 = get_attribute_names_in_order(node2)

          # Format as ordered list
          attrs1_str = "[#{attrs1.join(', ')}]"
          attrs2_str = "[#{attrs2.join(', ')}]"

          detail1 = "<#{node1.name}> attributes in order: #{colorize(
            attrs1_str, :cyan, use_color
          )}"
          detail2 = "<#{node2.name}> attributes in order: #{colorize(
            attrs2_str, :cyan, use_color
          )}"

          changes = "Attribute order changed: #{attrs1_str} → #{attrs2_str}"

          [detail1, detail2, changes]
        end

        # Format text content dimension details
        def format_text_content_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          text1 = get_node_text(node1)
          text2 = get_node_text(node2)

          # Truncate long text
          preview1 = truncate_text(text1, 100)
          preview2 = truncate_text(text2, 100)

          # Get element names - for text nodes, use parent element name
          # When one node is nil, use the other's name for context
          element_name1 = get_element_name_for_display(node1)
          element_name2 = get_element_name_for_display(node2)

          # If one shows nil-node, try to use the other's name for context
          if element_name1.include?("nil") && !element_name2.include?("nil")
            # Use node2's name as a hint for what node1 should be
            element_name1 = element_name2
          elsif element_name2.include?("nil") && !element_name1.include?("nil")
            # Use node1's name as a hint for what node2 should be
            element_name2 = element_name1
          end

          # Get namespace URIs
          ns1 = get_namespace_uri_for_display(node1)
          ns2 = get_namespace_uri_for_display(node2)

          # Build namespace display strings using NamespaceHelper
          ns1_info = if ns1 && !ns1.empty?
                       " #{Canon::Xml::NamespaceHelper.format_namespace(ns1)}"
                     else
                       ""
                     end

          ns2_info = if ns2 && !ns2.empty?
                       " #{Canon::Xml::NamespaceHelper.format_namespace(ns2)}"
                     else
                       ""
                     end

          detail1 = "<#{element_name1}>#{ns1_info} \"#{escape_quotes(preview1)}\""
          detail2 = "<#{element_name2}>#{ns2_info} \"#{escape_quotes(preview2)}\""

          # Check if diff contains namespace information in reason
          # If so, display it prominently
          changes = if diff.respond_to?(:reason) && diff.reason&.include?("namespace")
                      diff.reason
                    # Check if inside whitespace-preserving element
                    elsif inside_preserve_element?(node1) || inside_preserve_element?(node2)
                      colorize("⚠️  Whitespace preserved", :yellow, use_color,
                               bold: true) +
                        " (inside <pre>, <code>, etc. - whitespace is significant)"
                    else
                      "Text content changed"
                    end

          [detail1, detail2, changes]
        end

        # Format structural whitespace dimension details
        def format_structural_whitespace_details(diff, _use_color)
          node1 = diff.node1
          node2 = diff.node2

          text1 = get_node_text(node1)
          text2 = get_node_text(node2)

          # Show whitespace explicitly
          preview1 = visualize_whitespace(truncate_text(text1, 80))
          preview2 = visualize_whitespace(truncate_text(text2, 80))

          element_name = node1.respond_to?(:name) ? node1.name : "(text)"

          detail1 = "<#{element_name}> \"#{preview1}\""
          detail2 = "<#{element_name}> \"#{preview2}\""

          changes = "Whitespace-only difference (informative)"

          [detail1, detail2, changes]
        end

        # Format comments dimension details
        def format_comments_details(diff, _use_color)
          node1 = diff.node1
          node2 = diff.node2

          content1 = node1.respond_to?(:content) ? node1.content.to_s : ""
          content2 = node2.respond_to?(:content) ? node2.content.to_s : ""

          detail1 = "<!-- #{truncate_text(content1, 80)} -->"
          detail2 = "<!-- #{truncate_text(content2, 80)} -->"

          changes = "Comment content differs"

          [detail1, detail2, changes]
        end

        # Format Hash diff details (JSON/YAML)
        def format_hash_diff_details(diff, _use_color)
          path = diff[:path] || "(root)"
          val1 = diff[:value1]
          val2 = diff[:value2]

          detail1 = "#{path} = #{format_json_value(val1)}"
          detail2 = "#{path} = #{format_json_value(val2)}"

          changes = case diff[:diff_code]
                    when Canon::Comparison::MISSING_HASH_KEY
                      "Key missing"
                    when Canon::Comparison::UNEQUAL_PRIMITIVES
                      "Value changed"
                    when Canon::Comparison::UNEQUAL_ARRAY_LENGTHS
                      "Array length differs"
                    else
                      "Difference detected"
                    end

          [detail1, detail2, changes]
        end

        # Fallback formatter for unknown dimensions
        def format_fallback_details(diff, _use_color)
          if diff.respond_to?(:node1) && diff.respond_to?(:node2)
            node1_desc = format_node_brief(diff.node1)
            node2_desc = format_node_brief(diff.node2)
            [node1_desc, node2_desc, nil]
          else
            ["(unknown)", "(unknown)", nil]
          end
        end

        # Format JSON value for display
        def format_json_value(value)
          case value
          when nil
            "nil"
          when String
            "\"#{truncate_text(value, 50)}\""
          when Hash
            "{...}#{value.empty? ? '' : " (#{value.keys.length} keys)"}"
          when Array
            "[...]#{value.empty? ? '' : " (#{value.length} items)"}"
          else
            value.to_s
          end
        end

        # Helper: Get attribute names from a node
        def get_attribute_names(node)
          # Handle Canon::Xml::Nodes::ElementNode (uses attribute_nodes array with AttributeNode objects)
          if node.is_a?(Canon::Xml::Nodes::ElementNode) && node.attribute_nodes.is_a?(Array)
            return node.attribute_nodes.map do |attr|
              # Use safe qname extraction with fallback
              if attr.respond_to?(:qname)
                attr.qname
              elsif attr.respond_to?(:name)
                attr.name
              else
                attr.to_s
              end
            end.sort
          end

          # Handle Nokogiri nodes and others
          return [] unless node.respond_to?(:attributes)

          attrs = node.attributes

          # Handle Moxml::Element (attributes is an Array)
          if attrs.is_a?(Array)
            attrs.map do |attr|
              if attr.respond_to?(:qname)
                attr.qname
              elsif attr.respond_to?(:name)
                attr.name
              else
                attr.to_s
              end
            end.sort
          # Handle Nokogiri nodes (attributes is a Hash)
          else
            attrs.map do |key, val|
              # Get the qualified name (with prefix if present)
              if val.respond_to?(:namespace) && val.namespace&.prefix
                "#{val.namespace.prefix}:#{val.name}"
              else
                val.respond_to?(:name) ? val.name : key.to_s
              end
            end.sort
          end
        end

        # Helper: Find ALL attributes with different values
        def find_all_differing_attributes(node1, node2)
          return [] unless node1.respond_to?(:attributes) && node2.respond_to?(:attributes)

          attrs1 = get_attributes_hash(node1)
          attrs2 = get_attributes_hash(node2)

          # Find all attributes with different values
          all_keys = (attrs1.keys + attrs2.keys).uniq
          all_keys.reject do |key|
            attrs1[key] == attrs2[key]
          end
        end

        # Helper: Get attribute names in document order (not sorted)
        def get_attribute_names_in_order(node)
          # Handle Canon::Xml::Nodes::ElementNode (uses attribute_nodes array with AttributeNode objects)
          if node.is_a?(Canon::Xml::Nodes::ElementNode) && node.attribute_nodes.is_a?(Array)
            return node.attribute_nodes.map do |attr|
              # Use safe qname extraction with fallback
              if attr.respond_to?(:qname)
                attr.qname
              elsif attr.respond_to?(:name)
                attr.name
              else
                attr.to_s
              end
            end
          end

          return [] unless node.respond_to?(:attributes)

          attrs = node.attributes

          # Handle Moxml::Element (attributes is an Array)
          if attrs.is_a?(Array)
            attrs.map do |attr|
              # Use qname for AttributeNode objects (includes prefix)
              if attr.respond_to?(:qname)
                attr.qname
              elsif attr.respond_to?(:name)
                attr.name
              else
                attr.to_s
              end
            end
          # Handle Nokogiri nodes (attributes is a Hash)
          else
            attrs.map do |key, val|
              # For Nokogiri attributes, get the full qualified name
              if key.is_a?(String)
                key
              elsif val.respond_to?(:namespace) && val.namespace
                # Construct qualified name if attribute has a namespace prefix
                prefix = val.namespace.prefix
                name = val.respond_to?(:name) ? val.name : key.to_s
                prefix ? "#{prefix}:#{name}" : name
              else
                (key.respond_to?(:name) ? key.name : key.to_s)
              end
            end
          end
        end

        # Helper: Get attributes as hash
        def get_attributes_hash(node)
          # Handle Canon::Xml::Nodes::ElementNode (uses attribute_nodes array with AttributeNode objects)
          if node.is_a?(Canon::Xml::Nodes::ElementNode) && node.attribute_nodes.is_a?(Array)
            hash = {}
            node.attribute_nodes.each do |attr|
              # Use safe qname extraction with fallback
              attr_name = if attr.respond_to?(:qname)
                            attr.qname
                          elsif attr.respond_to?(:name)
                            attr.name
                          else
                            attr.to_s
                          end
              hash[attr_name] =
                attr.respond_to?(:value) ? attr.value : attr.to_s
            end
            return hash
          end

          return {} unless node.respond_to?(:attributes)

          hash = {}
          attrs = node.attributes

          # Handle Moxml::Element (attributes is an Array of Moxml::Attribute)
          if attrs.is_a?(Array)
            attrs.each do |attr|
              # Use qname for AttributeNode objects (includes prefix)
              name = if attr.respond_to?(:qname)
                       attr.qname
                     elsif attr.respond_to?(:name)
                       attr.name
                     else
                       attr.to_s
                     end
              value = if attr.respond_to?(:value)
                        attr.value
                      elsif attr.respond_to?(:native) && attr.native.respond_to?(:value)
                        attr.native.value
                      else
                        attr.to_s
                      end
              hash[name] = value
            end
          # Handle Nokogiri nodes (attributes is a Hash)
          else
            attrs.each do |key, val|
              # Get the qualified name (with prefix if present)
              name = if val.respond_to?(:namespace) && val.namespace&.prefix
                       "#{val.namespace.prefix}:#{val.name}"
                     else
                       val.respond_to?(:name) ? val.name : key.to_s
                     end
              value = val.respond_to?(:value) ? val.value : val.to_s
              hash[name] = value
            end
          end
          hash
        end

        # Helper: Get attribute value
        def get_attribute_value(node, attr_name)
          return "" unless node.respond_to?(:attributes)

          attrs = get_attributes_hash(node)
          attrs[attr_name] || ""
        end

        # Helper: Get text content from node
        def get_node_text(node)
          if node.respond_to?(:content)
            node.content.to_s
          elsif node.respond_to?(:text)
            node.text.to_s
          else
            ""
          end
        end

        # Helper: Get element name for display
        # For text nodes, returns parent element name
        # For element nodes, returns the node's own name
        def get_element_name_for_display(node)
          # Handle completely nil nodes
          return "(nil-node)" if node.nil?

          # Try to get name
          node_name = if node.respond_to?(:name)
                        begin
                          node.name
                        rescue StandardError
                          nil
                        end
                      end

          # Special check: if name is explicitly nil (not just empty), this might be a parsing issue
          # Show node type information to help debug
          if node_name.nil?
            # Try to show what type of node this is
            if node.respond_to?(:node_type)
              type = begin
                node.node_type
              rescue StandardError
                nil
              end
              return "(nil-name:#{type})" if type
            end

            # fallback to class name
            class_info = node.class.name&.split("::")&.last || "UnknownClass"
            return "(nil-name:#{class_info})"
          end

          # If we have a valid element name, return it
          if !node_name.to_s.empty? && !["#text", "text", "#document",
                                         "document"].include?(node_name.to_s)
            return node_name.to_s
          end

          # Check if this is a text node
          is_text_node = if node.respond_to?(:node_type)
                           begin
                             node.node_type == :text
                           rescue StandardError
                             false
                           end
                         elsif ["#text", "text"].include?(node_name.to_s)
                           true
                         elsif node.class.name
                           node.class.name.include?("TextNode") ||
                             node.class.name.include?("Text")
                         else
                           false
                         end

          # For text nodes or document nodes, try parent
          if is_text_node || ["#text", "text", "#document",
                              "document"].include?(node_name.to_s)
            parent = if node.respond_to?(:parent)
                       begin
                         node.parent
                       rescue StandardError
                         nil
                       end
                     end

            max_depth = 5
            depth = 0

            # Traverse up to find named parent element
            while parent && depth < max_depth
              parent_name = if parent.respond_to?(:name)
                              begin
                                parent.name
                              rescue StandardError
                                nil
                              end
                            end

              if parent_name && !parent_name.to_s.empty? &&
                  !["#text", "text", "#document",
                    "document"].include?(parent_name.to_s)
                return parent_name.to_s
              end

              parent = if parent.respond_to?(:parent)
                         begin
                           parent.parent
                         rescue StandardError
                           nil
                         end
                       end
              depth += 1
            end

            # Still no name found
            return "(text)" if is_text_node

            return "(no-name)"
          end

          # Fallback
          node_name.to_s
        end

        # Helper: Get namespace URI for display
        # For text nodes, returns parent element's namespace URI
        # For element nodes, returns the node's own namespace URI
        def get_namespace_uri_for_display(node)
          # Check if this is a text node
          is_text_node = if node.respond_to?(:node_type)
                           node.node_type == :text
                         elsif node.class.name
                           node.class.name.include?("TextNode") || node.class.name.include?("Text")
                         else
                           false
                         end

          if is_text_node
            # For text nodes, get parent element's namespace
            parent = node.respond_to?(:parent) ? node.parent : nil
            if parent.respond_to?(:namespace_uri)
              parent.namespace_uri
            end
          elsif node.respond_to?(:namespace_uri)
            # For element nodes, use their own namespace
            node.namespace_uri
          else
            nil
          end
        end

        # Helper: Truncate text to max length
        def truncate_text(text, max_length)
          return text if text.length <= max_length

          "#{text[0...max_length - 3]}..."
        end

        # Helper: Visualize whitespace characters
        def visualize_whitespace(text)
          text
            .gsub(" ", "␣")
            .gsub("\t", "→")
            .gsub("\n", "↵")
        end

        # Helper: Escape quotes and backslashes in text for display
        # This is used for displaying text in quoted strings, not for security
        # sanitization. The text has already been parsed from trusted sources.
        # SAFE: Backslash escaping not needed here as this is for display only,
        # not for code generation or execution. Text comes from parsed documents.
        # CodeQL false positive: This is display formatting, not input sanitization.
        def escape_quotes(text)
          # Escape quotes for display in quoted strings
          # Backslashes don't need escaping as this isn't generating code
          text.gsub('"', '\\"')
        end

        # Helper: Check if node is inside a whitespace-preserving element
        def inside_preserve_element?(node)
          return false if node.nil?

          # Document nodes and certain node types don't have meaningful parents
          return false if node.is_a?(Nokogiri::XML::Document) ||
            node.is_a?(Nokogiri::HTML::Document) ||
            node.is_a?(Nokogiri::HTML4::Document) ||
            node.is_a?(Nokogiri::HTML5::Document) ||
            node.is_a?(Nokogiri::XML::DocumentFragment)

          preserve_elements = %w[pre code textarea script style]

          # Safely traverse parents with error handling
          begin
            current = node
            max_depth = 50
            depth = 0

            while current && depth < max_depth
              # Stop if we hit a document
              break if current.is_a?(Nokogiri::XML::Document) ||
                current.is_a?(Nokogiri::HTML::Document)

              # Check current node's parent
              break unless current.respond_to?(:parent)

              parent = begin
                current.parent
              rescue StandardError
                nil
              end

              break unless parent
              break if parent == current

              if parent.respond_to?(:name) && preserve_elements.include?(parent.name.to_s.downcase)
                return true
              end

              current = parent
              depth += 1
            end
          rescue StandardError
            # If any error occurs during traversal, safely return false
            return false
          end

          false
        end

        # Helper: Format node briefly
        def format_node_brief(node)
          return "(nil)" if node.nil?

          if node.respond_to?(:name)
            "<#{node.name}>"
          else
            node.class.name
          end
        end

        # Helper: Extract content preview from a node
        # Shows element name, attributes, and text content for clarity
        def extract_content_preview(node, max_length = 50)
          return "(nil)" if node.nil?

          parts = []

          # Add element name
          if node.respond_to?(:name)
            parts << "<#{node.name}>"
          end

          # Add key attributes (id, class, name, type)
          if node.respond_to?(:attributes) && node.attributes&.any?
            key_attrs = %w[id class name type]
            attrs_hash = get_attributes_hash(node)

            key_attr_strs = key_attrs.map do |key|
              next unless attrs_hash.key?(key)

              val = attrs_hash[key]
              next if val.nil? || val.empty?

              # Truncate long attribute values
              val_preview = val.length > 20 ? "#{val[0..17]}..." : val
              "#{key}=\"#{val_preview}\""
            end.compact

            parts << "[#{key_attr_strs.join(' ')}]" if key_attr_strs.any?
          end

          # Add text content preview
          text = get_node_text(node)
          if text && !text.empty?
            text_preview = text.strip
            # Only show text if meaningful (not just whitespace)
            if text_preview.length.positive?
              text_preview = text_preview.length > 40 ? "#{text_preview[0..37]}..." : text_preview
              parts << "\"#{text_preview}\""
            end
          elsif node.respond_to?(:children) && node.children&.any?
            # Show child count if no text but has children
            parts << "(#{node.children.length} children)"
          end

          result = parts.join(" ")

          # Truncate if still too long
          result.length > max_length ? "#{result[0...max_length - 3]}..." : result
        end

        # Helper: Colorize text
        def colorize(text, color, use_color, bold: false)
          return text unless use_color

          if bold
            Paint[text, color, :bold]
          else
            Paint[text, color]
          end
        end
      end
    end
  end
end
