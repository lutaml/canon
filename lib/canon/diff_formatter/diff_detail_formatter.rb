# frozen_string_literal: true

require "rainbow"
require_relative "../xml/namespace_helper"
# DiffDetailFormatter helper modules
require_relative "diff_detail_formatter/text_utils"
require_relative "diff_detail_formatter/color_helper"
require_relative "diff_detail_formatter/location_extractor"
require_relative "diff_detail_formatter/node_utils"
require_relative "diff_detail_formatter/dimension_formatter"

module Canon
  class DiffFormatter
    # Formats dimension-specific detail for individual differences
    # Provides actionable, colorized output showing exactly what changed
    module DiffDetailFormatter
      ANSI_ESCAPE = /\e\[[0-9;]*m/
      COMPACT_DETAIL_MAX = 30

      class << self
        # Format all differences as a semantic diff report
        #
        # @param differences [Array<DiffNode>] Array of differences
        # @param use_color [Boolean] Whether to use colors
        # @param show_diffs [Symbol] Filter: :all (default), :normative, :informative
        # @param compact_semantic_report [Boolean] When true, serialize element nodes
        #   as compact XML (e.g. <strong>Annex</strong>) instead of the verbose
        #   node_info description (e.g. "name: strong namespace_uri: …")
        # @return [String] Formatted semantic diff report
        def format_report(differences, use_color: true, show_diffs: :all,
                          compact_semantic_report: false,
                          expand_difference: false)
          return "" if differences.empty?

          # Group differences by normative status
          normative = differences.select do |diff|
            diff.respond_to?(:normative?) ? diff.normative? : true
          end
          informative = differences.select do |diff|
            diff.respond_to?(:normative?) && !diff.normative?
          end

          # Apply show_diffs filter — same semantics as the line-diff filter
          show_normative   = show_diffs != :informative
          show_informative = show_diffs != :normative

          output = []
          output << ""
          output << colorize("=" * 70, :cyan, use_color, bold: true)
          output << colorize(
            "  SEMANTIC DIFF REPORT (#{differences.length} #{differences.length == 1 ? 'difference' : 'differences'})", :cyan, use_color, bold: true
          )
          output << colorize("=" * 70, :cyan, use_color, bold: true)

          # Show normative differences first
          if normative.any? && show_normative
            output << ""
            output << colorize(
              "┌─ NORMATIVE DIFFERENCES (#{normative.length}) ─┐", :green, use_color, bold: true
            )

            normative.each_with_index do |diff, i|
              output << ""
              output << format_single_diff(diff, i + 1, normative.length,
                                           use_color, section: "NORMATIVE",
                                                      compact: compact_semantic_report,
                                                      expand_difference: expand_difference)
            end
          end

          # Show informative differences second
          if informative.any? && show_informative
            output << ""
            output << ""
            output << colorize(
              "┌─ INFORMATIVE DIFFERENCES (#{informative.length}) ─┐", :yellow, use_color, bold: true
            )

            informative.each_with_index do |diff, i|
              output << ""
              output << format_single_diff(diff, i + 1, informative.length,
                                           use_color, section: "INFORMATIVE",
                                                      compact: compact_semantic_report,
                                                      expand_difference: expand_difference)
            end
          end

          output << ""
          output << colorize("=" * 70, :cyan, use_color, bold: true)
          output << ""

          output.join("\n")
        end

        private

        # Format a single difference with dimension-specific details
        def format_single_diff(diff, number, total, use_color, section: nil,
compact: false, expand_difference: false)
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
          location = DiffDetailFormatterHelpers::LocationExtractor.extract_location(diff)
          output << "#{colorize('Location:', :cyan, use_color,
                                bold: true)}  #{colorize(location, :blue,
                                                         use_color)}"

          # show reason if available
          if diff.respond_to?(:reason) && diff.reason
            format_reason_line(output, diff.reason, use_color)
          end
          output << ""

          # Dimension-specific details
          detail1, detail2, changes = DiffDetailFormatterHelpers::DimensionFormatter.format_dimension_details(
            diff, use_color, compact: compact, expand_difference: expand_difference
          )

          format_expected_actual(output, detail1, detail2, use_color)

          if changes && !changes.empty?
            output << ""
            output << colorize("✨ Changes:", :yellow, use_color, bold: true)
            output << "   #{changes}"
          end

          output.join("\n")
        rescue StandardError => e
          # Safe fallback if formatting fails - provide detailed context
          location = begin
            DiffDetailFormatterHelpers::LocationExtractor.extract_location(diff)
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

        # Format the Reason line. When the reason contains visualized
        # spaces (░), split into two vertically-aligned lines so the
        # before/after text can be compared visually.
        def format_reason_line(output, reason_text, use_color)
          if reason_text.include?("\u2591") &&
              reason_text.match?(/\A(Text|whitespace): .*\bvs\b/)
            parts = reason_text.split(" vs ", 2)
            if parts.length == 2
              output << "#{colorize('Reason:', :cyan, use_color,
                                    bold: true)}  #{colorize(parts[0],
                                                             :yellow, use_color)}"
              output << "#{' ' * 10}#{colorize("vs.: #{parts[1]}",
                                               :yellow, use_color)}"
              return
            end
          end
          output << "#{colorize('Reason:', :cyan, use_color,
                                bold: true)}  #{colorize(reason_text,
                                                         :yellow, use_color)}"
        end

        # Format the Expected/Actual block. Short values (both under 30
        # chars) are rendered as compact single lines with aligned colons;
        # longer values use the multi-line layout without a blank line gap.
        def format_expected_actual(output, detail1, detail2, use_color)
          plain1 = detail1.gsub(ANSI_ESCAPE, "")
          plain2 = detail2.gsub(ANSI_ESCAPE, "")

          if plain1.length < COMPACT_DETAIL_MAX &&
              plain2.length < COMPACT_DETAIL_MAX
            lbl1 = colorize("\u2296 Expected (File 1)", :red, use_color,
                            bold: true)
            lbl2 = colorize("\u2295 Actual (File 2)  ", :green, use_color,
                            bold: true)
            output << "#{lbl1}: #{detail1}"
            output << "#{lbl2}: #{detail2}"
          else
            output << colorize("\u2296 Expected (File 1):", :red, use_color,
                               bold: true)
            output << "   #{detail1}"
            output << colorize("\u2295 Actual (File 2):", :green, use_color,
                               bold: true)
            output << "   #{detail2}"
          end
        end

        # Helper: Colorize text
        def colorize(text, color, use_color, bold: false)
          DiffDetailFormatterHelpers::ColorHelper.colorize(text, color,
                                                           use_color, bold: bold)
        end
      end
    end
  end
end
