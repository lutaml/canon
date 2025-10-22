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

          output = []
          output << ""
          output << colorize("=" * 70, :cyan, use_color, bold: true)
          output << colorize(
            "  SEMANTIC DIFF REPORT (#{differences.length} #{differences.length == 1 ? 'difference' : 'differences'})", :cyan, use_color, bold: true
          )
          output << colorize("=" * 70, :cyan, use_color, bold: true)

          differences.each_with_index do |diff, i|
            output << ""
            output << format_single_diff(diff, i + 1, differences.length,
                                         use_color)
          end

          output << ""
          output << colorize("=" * 70, :cyan, use_color, bold: true)
          output << ""

          output.join("\n")
        end

        private

        # Format a single difference with dimension-specific details
        def format_single_diff(diff, number, total, use_color)
          output = []

          # Header - handle both DiffNode and Hash
          status = if diff.respond_to?(:normative?)
                     diff.normative? ? "NORMATIVE" : "INFORMATIVE"
                   else
                     "NORMATIVE" # Hash diffs are always normative
                   end
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
          when :attribute_presence
            format_attribute_presence_details(diff, use_color)
          when :attribute_values
            format_attribute_values_details(diff, use_color)
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

          # Find which attribute has different value
          differing_attr = find_differing_attribute(node1, node2)

          if differing_attr
            val1 = get_attribute_value(node1, differing_attr)
            val2 = get_attribute_value(node2, differing_attr)

            detail1 = "<#{node1.name}> #{colorize(differing_attr, :cyan,
                                                  use_color)}=\"#{escape_quotes(val1)}\""
            detail2 = "<#{node2.name}> #{colorize(differing_attr, :cyan,
                                                  use_color)}=\"#{escape_quotes(val2)}\""

            # Analyze the difference
            changes = if val1.strip == val2.strip && val1 != val2
                        "Whitespace difference only"
                      elsif val1.gsub(/\s+/, " ") == val2.gsub(/\s+/, " ")
                        "Whitespace normalization difference"
                      else
                        "Value changed"
                      end

            [detail1, detail2, changes]
          else
            ["<#{node1.name}> (values differ)",
             "<#{node2.name}> (values differ)", nil]
          end
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

          detail1 = "<#{element_name}> \"#{escape_quotes(preview1)}\""
          detail2 = "<#{element_name}> \"#{escape_quotes(preview2)}\""

          # Check if inside whitespace-preserving element
          changes = if inside_preserve_element?(node1) || inside_preserve_element?(node2)
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

          node.attributes.map do |key, _val|
            if key.is_a?(String)
              key
            else
              (key.respond_to?(:name) ? key.name : key.to_s)
            end
          end.sort
        end

        # Helper: Find which attribute has different value
        def find_differing_attribute(node1, node2)
          return nil unless node1.respond_to?(:attributes) && node2.respond_to?(:attributes)

          attrs1 = get_attributes_hash(node1)
          attrs2 = get_attributes_hash(node2)

          # Find first attribute with different value
          common_keys = attrs1.keys & attrs2.keys
          common_keys.find { |key| attrs1[key] != attrs2[key] }
        end

        # Helper: Get attributes as hash
        def get_attributes_hash(node)
          return {} unless node.respond_to?(:attributes)

          hash = {}
          node.attributes.each do |key, val|
            name = if key.is_a?(String)
                     key
                   else
                     (key.respond_to?(:name) ? key.name : key.to_s)
                   end
            value = val.respond_to?(:value) ? val.value : val.to_s
            hash[name] = value
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
