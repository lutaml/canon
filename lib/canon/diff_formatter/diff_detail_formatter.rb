# frozen_string_literal: true

require "paint"
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
          location = DiffDetailFormatterHelpers::LocationExtractor.extract_location(diff)
          output << "#{colorize('Location:', :cyan, use_color,
                                bold: true)}  #{colorize(location, :blue,
                                                         use_color)}"
          output << ""

          # Dimension-specific details
          detail1, detail2, changes = DiffDetailFormatterHelpers::DimensionFormatter.format_dimension_details(
            diff, use_color
          )

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

        # Helper: Colorize text
        def colorize(text, color, use_color, bold: false)
          DiffDetailFormatterHelpers::ColorHelper.colorize(text, color,
                                                           use_color, bold: bold)
        end
      end
    end
  end
end
