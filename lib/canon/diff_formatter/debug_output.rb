# frozen_string_literal: true

require_relative "diff_detail_formatter"

module Canon
  class DiffFormatter
    # Verbose diff output helper for CANON_VERBOSE mode
    # Can be activated by:
    # 1. Environment variable: CANON_VERBOSE=1
    # 2. Diff option: verbose_diff: true
    # Provides beautiful, readable output
    module DebugOutput
      class << self
        def enabled?(verbose_diff_option = false)
          verbose_diff_option ||
            ENV["CANON_VERBOSE"] == "1" ||
            ENV["CANON_VERBOSE"] == "true"
        end

        # Return ONLY CANON VERBOSE tables (not Semantic Diff Report)
        # Semantic Diff Report is now part of main diff output
        def verbose_tables_only(comparison_result, formatter_options = {})
          verbose_diff = formatter_options[:verbose_diff] || false
          return "" unless enabled?(verbose_diff)

          require "table_tennis"

          output = []
          output << ""
          output << "=" * 80
          output << "CANON VERBOSE MODE - DETAILED OPTIONS"
          output << "=" * 80
          output << ""

          # Show match options as a table
          output << format_match_options_table(comparison_result)
          output << ""

          # Show formatter options as a table
          output << format_formatter_options_table(formatter_options)
          output << ""

          # Show comparison summary
          output << format_comparison_summary(comparison_result)
          output << ""

          output << "=" * 80
          output << ""

          output.join("\n")
        end

        # Backward compatibility alias
        def debug_info(comparison_result, formatter_options = {})
          verbose_tables_only(comparison_result, formatter_options)
        end

        def format_match_options_table(comparison_result)
          return "MATCH OPTIONS: (not available)" unless comparison_result.is_a?(Canon::Comparison::ComparisonResult)
          return "MATCH OPTIONS: (not available)" unless comparison_result.match_options

          # Filter out internal tree_diff metadata keys that should not be displayed
          internal_keys = %i[tree_diff_operations tree_diff_statistics tree_diff_matching]

          rows = comparison_result.match_options.reject do |dimension, _behavior|
            internal_keys.include?(dimension)
          end.map do |dimension, behavior|
            {
              dimension: dimension.to_s,
              behavior: behavior.to_s,
              description: dimension_description(dimension, behavior),
            }
          end

          TableTennis.new(
            rows,
            title: "Match Options (#{comparison_result.format.to_s.upcase})",
            columns: %i[dimension behavior description],
            headers: { dimension: "Dimension", behavior: "Behavior",
                       description: "Meaning" },
            zebra: true,
          ).to_s
        end

        def dimension_description(dimension, behavior)
          # Special handling for preprocessing dimension
          if dimension.to_s == "preprocessing"
            return case behavior
                   when :none
                     "No preprocessing (compare as-is)"
                   when :c14n
                     "Canonicalize (XML C14N normalization)"
                   when :normalize
                     "Normalize (collapse whitespace, trim lines)"
                   when :format
                     "Pretty-format (consistent indentation)"
                   when :rendered
                     "As browser-rendered (compacted whitespace, to_html)"
                   else
                     behavior.to_s
                   end
          end

          # Standard dimension descriptions
          case behavior
          when :ignore
            "Differences IGNORED (informative)"
          when :normalize
            "Normalized then compared (normative if different after normalization)"
          when :strict
            "Must match exactly (normative)"
          when :strip
            "Strip leading/trailing whitespace only"
          when :compact
            "Collapse whitespace runs to single space"
          else
            behavior.to_s
          end
        end

        def format_formatter_options_table(formatter_options)
          rows = formatter_options.map do |key, value|
            {
              option: key.to_s,
              value: format_value(value),
              impact: option_impact(key, value),
            }
          end

          TableTennis.new(
            rows,
            title: "Formatter Options",
            columns: %i[option value impact],
            headers: { option: "Option", value: "Value", impact: "Impact" },
            zebra: true,
          ).to_s
        end

        def format_value(value)
          case value
          when Symbol
            value.to_s
          when Integer, String
            value.to_s
          when true, false
            value.to_s
          when nil
            "(nil)"
          else
            value.class.name
          end
        end

        def option_impact(key, value)
          case key
          when :show_diffs
            case value
            when :all
              "Show all diffs (normative + informative)"
            when :normative
              "Show only normative (semantic) diffs"
            when :informative
              "Show only informative (textual) diffs"
            else
              value.to_s
            end
          when :mode
            value == :by_line ? "Line-by-line diff" : "Object tree diff"
          when :context_lines
            "#{value} lines of context around diffs"
          when :diff_grouping_lines
            value ? "Group diffs within #{value} lines" : "No grouping"
          else
            "-"
          end
        end

        def format_comparison_summary(comparison_result)
          return "COMPARISON RESULT: (not a ComparisonResult object)" unless comparison_result.is_a?(Canon::Comparison::ComparisonResult)

          normative_count = comparison_result.normative_differences.length
          informative_count = comparison_result.informative_differences.length

          rows = [
            {
              metric: "Equivalent?",
              value: comparison_result.equivalent? ? "✓ YES" : "✗ NO",
              detail: comparison_result.equivalent? ? "Documents are semantically equivalent" : "Documents have semantic differences",
            },
            {
              metric: "Normative Diffs",
              value: normative_count.positive? ? "#{normative_count} diffs" : "0",
              detail: "Semantic differences that matter",
            },
            {
              metric: "Informative Diffs",
              value: informative_count.positive? ? "#{informative_count} diffs" : "0",
              detail: "Textual/formatting differences (ignored)",
            },
            {
              metric: "Total Diffs",
              value: comparison_result.differences.length.to_s,
              detail: "All differences found",
            },
          ]

          TableTennis.new(
            rows,
            title: "Comparison Result Summary",
            columns: %i[metric value detail],
            headers: { metric: "Metric", value: "Value",
                       detail: "Description" },
            zebra: true,
          ).to_s
        end

        def format_differences_tree(differences)
          output = []
          output << "DIFFERENCES TREE:"
          output << ""

          # Create table rows for each difference
          rows = differences.map.with_index do |diff, i|
            if diff.is_a?(Canon::Diff::DiffNode)
              detail1, detail2 = format_node_diff_detail(diff)

              {
                "#": i + 1,
                dimension: diff.dimension.to_s,
                marker: diff.normative? ? "+/-" : "~",
                diff1: detail1,
                diff2: detail2,
              }
            elsif diff.is_a?(Hash)
              {
                "#": i + 1,
                dimension: diff[:dimension] || "(unknown)",
                marker: "+/-",
                diff1: "(hash)",
                diff2: "(hash)",
              }
            else
              {
                "#": i + 1,
                dimension: "-",
                marker: "-",
                diff1: "-",
                diff2: "-",
              }
            end
          end

          output << TableTennis.new(
            rows,
            title: "Differences Detail (#{differences.length} total)",
            columns: %i[# dimension marker diff1 diff2],
            headers: {
              "#": "#",
              dimension: "Dimension",
              marker: "Marker",
              diff1: "Expected (File 1)",
              diff2: "Actual (File 2)",
            },
            zebra: true,
            mark: ->(row) { row[:marker] == "+/-" },
          ).to_s

          output.join("\n")
        end

        def format_node_brief(node)
          return "(nil)" if node.nil?

          if node.respond_to?(:name)
            "<#{node.name}>"
          elsif node.respond_to?(:content)
            content = node.content.to_s
            if content&.length && content.length > 30
              "\"#{content[0..27]}...\""
            else
              "\"#{content || ''}\""
            end
          elsif node.respond_to?(:text)
            text = node.text.to_s
            if text&.length && text.length > 30
              "\"#{text[0..27]}...\""
            else
              "\"#{text || ''}\""
            end
          else
            node.class.name
          end
        end

        # Format detailed information about what differed in the nodes
        def format_node_diff_detail(diff)
          node1 = diff.node1
          node2 = diff.node2

          # For attribute differences, show which attributes differ
          if diff.dimension == :attribute_whitespace &&
              node1.respond_to?(:attributes) && node2.respond_to?(:attributes)
            attrs1 = format_attributes(node1)
            attrs2 = format_attributes(node2)
            return ["<#{node1.name}> #{attrs1}", "<#{node2.name}> #{attrs2}"]
          end

          # For element differences, show element names
          if node1.respond_to?(:name) && node2.respond_to?(:name)
            if node1.name == node2.name
              # Same element name, different content
            end
            return ["<#{node1.name}>", "<#{node2.name}>"]

            return ["<#{node1.name}>", "<#{node2.name}>"]
          end

          # For text differences, show content preview
          if %i[text_content structural_whitespace].include?(diff.dimension)
            content1 = get_node_content(node1)
            content2 = get_node_content(node2)
            return [format_content_preview(content1),
                    format_content_preview(content2)]
          end

          # Fallback to brief format
          [format_node_brief(node1), format_node_brief(node2)]
        end

        def format_attributes(node)
          return "" unless node.respond_to?(:attributes)

          attrs = node.attributes
          return "" if attrs.empty?

          # Format as name="value"
          attr_strs = attrs.map do |key, val|
            name = if key.is_a?(String)
                     key
                   else
                     (key.respond_to?(:name) ? key.name : key.to_s)
                   end
            value = val.respond_to?(:value) ? val.value : val.to_s
            "#{name}=\"#{value}\""
          end.sort

          # Limit to first 3 attributes
          if attr_strs.length > 3
            "#{attr_strs[0..2].join(' ')} ..."
          else
            attr_strs.join(" ")
          end
        end

        def get_node_content(node)
          if node.respond_to?(:content)
            node.content.to_s
          elsif node.respond_to?(:text)
            node.text.to_s
          else
            ""
          end
        end

        def format_content_preview(content)
          return '""' if content.nil? || content.empty?

          # Show first 40 chars
          if content.length > 40
            "\"#{content[0..37]}...\""
          else
            "\"#{content}\""
          end
        end

        def debug_diff_structure(diff_report)
          return "" unless enabled?

          require "table_tennis"

          output = []
          output << ""
          output << "DIFF STRUCTURE (DiffReport):"
          output << ""

          if diff_report.nil? || diff_report.contexts.empty?
            output << "  (no diff contexts)"
            return output.join("\n")
          end

          output << "  Total contexts: #{diff_report.contexts.length}"
          output << ""

          # Show contexts and blocks in table format
          diff_report.contexts.each_with_index do |context, ctx_idx|
            output << "  Context #{ctx_idx + 1}: Lines #{context.start_line}-#{context.end_line}"
            output << ""

            if context.diff_blocks.any?
              block_rows = context.diff_blocks.map.with_index do |block, blk_idx|
                {
                  "#": blk_idx + 1,
                  range: "#{block.start_idx}-#{block.end_idx}",
                  size: block.size,
                  types: block.types.join(", "),
                  normative: block.normative? ? "✓ NORMATIVE" : "✗ informative",
                  dimension: block.diff_node&.dimension&.to_s || "-",
                  lines: block.diff_lines&.length || 0,
                }
              end

              output << TableTennis.new(
                block_rows,
                title: "  Diff Blocks in Context #{ctx_idx + 1}",
                columns: %i[# range size types normative dimension lines],
                headers: {
                  "#": "#",
                  range: "Line Range",
                  size: "Size",
                  types: "Types",
                  normative: "Normative?",
                  dimension: "Dimension",
                  lines: "Lines",
                },
                mark: ->(row) { row[:normative] == "✓ NORMATIVE" },
              ).to_s
              output << ""
            end
          end

          output.join("\n")
        end
      end
    end
  end
end
