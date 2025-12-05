# frozen_string_literal: true

require "paint"

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
          # Safe fallback if formatting fails
          colorize(
            "🔍 DIFFERENCE ##{number}/#{total} [Error formatting: #{e.message}]", :red, use_color, bold: true
          )
        end

        # Extract XPath or JSON path for the difference location
        def extract_location(diff)
          # For Hash diffs (JSON/YAML)
          if diff.is_a?(Hash)
            return diff[:path] || "(root)"
          end

          # For DiffNode (XML/HTML)
          node = diff.respond_to?(:node1) ? (diff.node1 || diff.node2) : nil

          # For XML/HTML element nodes
          if node.respond_to?(:name)
            return extract_xpath(node)
          end

          # Fallback
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

          # Extract namespace URIs
          ns1 = node1.respond_to?(:namespace_uri) ? node1.namespace_uri : nil
          ns2 = node2.respond_to?(:namespace_uri) ? node2.namespace_uri : nil

          ns1_display = ns1.nil? || ns1.empty? ? "(no namespace)" : ns1
          ns2_display = ns2.nil? || ns2.empty? ? "(no namespace)" : ns2

          element_name = if node1.respond_to?(:name)
                           node1.name
                         else
                           node2.respond_to?(:name) ? node2.name : "element"
                         end

          detail1 = "<#{element_name}> with namespace: #{colorize(ns1_display,
                                                                  :cyan, use_color)}"
          detail2 = "<#{element_name}> with namespace: #{colorize(ns2_display,
                                                                  :cyan, use_color)}"

          changes = "Namespace differs: #{colorize(ns1_display, :red,
                                                   use_color)} → #{colorize(
                                                     ns2_display, :green, use_color
                                                   )}"

          [detail1, detail2, changes]
        end

        # Format element_structure dimension details (INSERT/DELETE operations)
        def format_element_structure_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Determine operation type
          if node1.nil? && !node2.nil?
            # INSERT operation - show content preview
            node2.respond_to?(:name) ? node2.name : "element"
            content_preview = extract_content_preview(node2, 50)
            detail1 = colorize("(not present)", :red, use_color)
            detail2 = content_preview
            changes = "Element inserted"
          elsif !node1.nil? && node2.nil?
            # DELETE operation - show content preview
            node1.respond_to?(:name) ? node1.name : "element"
            content_preview = extract_content_preview(node1, 50)
            detail1 = content_preview
            detail2 = colorize("(not present)", :green, use_color)
            changes = "Element deleted"
          elsif !node1.nil? && !node2.nil?
            # STRUCTURAL CHANGE (both nodes present) - show both previews
            name1 = node1.respond_to?(:name) ? node1.name : "element"
            name2 = node2.respond_to?(:name) ? node2.name : "element"
            detail1 = extract_content_preview(node1, 50)
            detail2 = extract_content_preview(node2, 50)

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
        def format_attribute_values_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          # Find ALL attributes with different values
          differing_attrs = find_all_differing_attributes(node1, node2)

          if differing_attrs.any?
            # Show element name with all differing attributes
            attrs1_str = differing_attrs.map do |attr|
              val1 = get_attribute_value(node1, attr)
              "#{colorize(attr, :cyan, use_color)}=\"#{escape_quotes(val1)}\""
            end.join(" ")

            attrs2_str = differing_attrs.map do |attr|
              val2 = get_attribute_value(node2, attr)
              "#{colorize(attr, :cyan, use_color)}=\"#{escape_quotes(val2)}\""
            end.join(" ")

            detail1 = "<#{node1.name}> #{attrs1_str}"
            detail2 = "<#{node2.name}> #{attrs2_str}"

            # List all attribute changes
            changes_parts = differing_attrs.map do |attr|
              val1 = get_attribute_value(node1, attr)
              val2 = get_attribute_value(node2, attr)

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

        # Format text_content dimension details
        def format_text_content_details(diff, use_color)
          node1 = diff.node1
          node2 = diff.node2

          text1 = get_node_text(node1)
          text2 = get_node_text(node2)

          # Truncate long text
          preview1 = truncate_text(text1, 100)
          preview2 = truncate_text(text2, 100)

          element_name = node1.respond_to?(:name) ? node1.name : "(text)"

          "<#{element_name}> \"#{escape_quotes(preview1)}\""
          "<#{element_name}> \"#{escape_quotes(preview2)}\""

          # Extract namespace information and include it in the details
          element_name1 = node1.respond_to?(:name) ? node1.name : "(text)"
          element_name2 = node2.respond_to?(:name) ? node2.name : "(text)"

          # Get namespace URIs
          ns1 = node1.respond_to?(:namespace_uri) ? node1.namespace_uri : nil
          ns2 = node2.respond_to?(:namespace_uri) ? node2.namespace_uri : nil

          # Build namespace display strings
          ns1_info = if ns1 && !ns1.empty?
                       " [namespace: #{colorize(ns1, :cyan, use_color)}]"
                     else
                       ""
                     end

          ns2_info = if ns2 && !ns2.empty?
                       " [namespace: #{colorize(ns2, :cyan, use_color)}]"
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

        # Format structural_whitespace dimension details
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
          return [] unless node.respond_to?(:attributes)

          attrs = node.attributes

          # Handle Moxml::Element (attributes is an Array)
          if attrs.is_a?(Array)
            attrs.map do |attr|
              attr.respond_to?(:name) ? attr.name : attr.to_s
            end.sort
          # Handle Nokogiri nodes (attributes is a Hash)
          else
            attrs.map do |key, _val|
              if key.is_a?(String)
                key
              else
                (key.respond_to?(:name) ? key.name : key.to_s)
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
          return [] unless node.respond_to?(:attributes)

          attrs = node.attributes

          # Handle Moxml::Element (attributes is an Array)
          if attrs.is_a?(Array)
            attrs.map do |attr|
              attr.respond_to?(:name) ? attr.name : attr.to_s
            end
          # Handle Nokogiri nodes (attributes is a Hash)
          else
            attrs.map do |key, _val|
              if key.is_a?(String)
                key
              else
                (key.respond_to?(:name) ? key.name : key.to_s)
              end
            end
          end
        end

        # Helper: Get attributes as hash
        def get_attributes_hash(node)
          return {} unless node.respond_to?(:attributes)

          hash = {}
          attrs = node.attributes

          # Handle Moxml::Element (attributes is an Array of Moxml::Attribute)
          if attrs.is_a?(Array)
            attrs.each do |attr|
              name = attr.respond_to?(:name) ? attr.name : attr.to_s
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
              name = if key.is_a?(String)
                       key
                     else
                       (key.respond_to?(:name) ? key.name : key.to_s)
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
