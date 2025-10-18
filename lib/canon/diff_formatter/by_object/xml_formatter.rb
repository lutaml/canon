# frozen_string_literal: true

require_relative "base_formatter"

module Canon
  class DiffFormatter
    module ByObject
      # XML/HTML tree formatter for by-object diffs
      # Handles DOM node differences with proper path extraction
      class XmlFormatter < BaseFormatter
        # Render a diff node for XML/HTML DOM differences
        #
        # @param key [String] Node name or path segment
        # @param diff [Hash] Difference information
        # @param prefix [String] Tree prefix for indentation
        # @param connector [String] Box-drawing connector character
        # @return [String] Formatted diff node
        def render_diff_node(key, diff, prefix, connector)
          output = []

          # Show full path if available (path in cyan, no color on tree structure)
          path_display = if diff[:path] && !diff[:path].empty?
                           colorize(diff[:path].to_s, :cyan, :bold)
                         else
                           colorize(key.to_s, :cyan)
                         end

          output << "#{prefix}#{connector}#{path_display}:"

          # Determine continuation for nested values
          continuation = connector.start_with?("├") ? "│   " : "    "
          value_prefix = prefix + continuation

          diff_code = diff[:diff_code] || diff[:diff1]

          case diff_code
          when Comparison::UNEQUAL_ELEMENTS
            render_unequal_elements(diff, value_prefix, output)
          when Comparison::UNEQUAL_TEXT_CONTENTS
            render_unequal_text(diff, value_prefix, output)
          when Comparison::UNEQUAL_ATTRIBUTES
            render_unequal_attributes(diff, value_prefix, output)
          when Comparison::MISSING_ATTRIBUTE
            render_missing_attribute(diff, value_prefix, output)
          when Comparison::UNEQUAL_COMMENTS
            render_unequal_comments(diff, value_prefix, output)
          when Comparison::MISSING_NODE
            render_missing_node(diff, value_prefix, output)
          else
            # Fallback for unknown diff types
            render_fallback(diff, value_prefix, output)
          end

          output.join("\n")
        end

        # Add a difference to the tree structure
        # Handles DOM nodes by extracting their path
        #
        # @param tree [Hash] Tree structure to add to
        # @param path [String, Array] Path to the difference
        # @param diff [Hash] Difference information
        def add_to_tree(tree, path, diff)
          # For DOM differences, extract path from node
          if !diff.key?(:path) && (diff[:node1] || diff[:node2])
            path = extract_dom_path(diff)
          end

          super(tree, path, diff)
        end

        private

        # Render unequal elements
        def render_unequal_elements(diff, prefix, output)
          node1 = diff[:node1]
          node2 = diff[:node2]
          output << "#{prefix}├── - #{colorize("<#{node1.name}>", :red)}"
          output << "#{prefix}└── + #{colorize("<#{node2.name}>", :green)}"
        end

        # Render unequal text contents
        def render_unequal_text(diff, prefix, output)
          node1 = diff[:node1]
          node2 = diff[:node2]

          text1 = extract_text(node1)
          text2 = extract_text(node2)

          # Show parent element if available
          if node1.respond_to?(:parent) && node1.parent.respond_to?(:name)
            output << "#{prefix}    #{colorize(
              "Element: <#{node1.parent.name}>", :blue
            )}"
          end

          output << "#{prefix}├── - #{colorize(format_text_inline(text1),
                                               :red)}"
          output << "#{prefix}└── + #{colorize(format_text_inline(text2),
                                               :green)}"
        end

        # Render unequal attributes
        def render_unequal_attributes(diff, prefix, output)
          node1 = diff[:node1]
          output << "#{prefix}└── #{colorize(
            "Element: <#{node1.name}> [attributes differ]", :yellow
          )}"
        end

        # Render missing attribute
        def render_missing_attribute(diff, prefix, output)
          node1 = diff[:node1]
          output << "#{prefix}└── #{colorize(
            "Element: <#{node1.name}> [attribute mismatch]", :yellow
          )}"
        end

        # Render unequal comments
        def render_unequal_comments(diff, prefix, output)
          node1 = diff[:node1]
          node2 = diff[:node2]

          content1 = extract_text(node1)
          content2 = extract_text(node2)

          output << "#{prefix}├── - #{colorize(
            "<!-- #{format_text_inline(content1)} -->", :red
          )}"
          output << "#{prefix}└── + #{colorize(
            "<!-- #{format_text_inline(content2)} -->", :green
          )}"
        end

        # Render missing node
        def render_missing_node(diff, prefix, output)
          output << if diff[:node1] && !diff[:node2]
                      "#{prefix}└── - #{colorize('[node deleted]', :red)}"
                    elsif diff[:node2] && !diff[:node1]
                      "#{prefix}└── + #{colorize('[node inserted]', :green)}"
                    else
                      "#{prefix}└── #{colorize('[node mismatch]', :yellow)}"
                    end
        end

        # Render fallback for unknown diff types
        def render_fallback(diff, prefix, output)
          if diff[:node1] && diff[:node2]
            output << "#{prefix}├── - #{colorize('[file1 node]', :red)}"
            output << "#{prefix}└── + #{colorize('[file2 node]', :green)}"
          elsif diff[:node1]
            output << "#{prefix}└── - #{colorize('[file1 only]', :red)}"
          elsif diff[:node2]
            output << "#{prefix}└── + #{colorize('[file2 only]', :green)}"
          else
            output << "#{prefix}└── #{colorize('[unknown change]', :yellow)}"
          end
        end

        # Extract DOM path from a difference
        #
        # @param diff [Hash] Difference with node1 or node2
        # @return [String] Path string
        def extract_dom_path(diff)
          node = diff[:node1] || diff[:node2]
          return "" unless node

          parts = []
          current = node

          while current.respond_to?(:name)
            parts.unshift(current.name) if current.name
            current = current.parent if current.respond_to?(:parent)
          end

          parts.join(".")
        end

        # Extract text from a node
        #
        # @param node [Object] Node with content or text
        # @return [String] Text content
        def extract_text(node)
          if node.respond_to?(:content)
            node.content.to_s
          elsif node.respond_to?(:text)
            node.text.to_s
          else
            ""
          end
        end

        # Format text for inline display (truncate if too long)
        #
        # @param text [String] Text to format
        # @return [String] Formatted text
        def format_text_inline(text)
          # Truncate long text
          if text.length > 60
            "\"#{text[0..57]}...\""
          else
            "\"#{text}\""
          end
        end
      end
    end
  end
end
