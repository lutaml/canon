# frozen_string_literal: true

require "diff/lcs"
require "diff/lcs/hunk"

module Canon
  class DiffFormatter
    module ByLine
      # Base formatter for line-by-line diffs
      # Provides common LCS diff logic and hunk building
      class BaseFormatter
        attr_reader :use_color, :context_lines, :diff_grouping_lines,
                    :visualization_map

        # Create a format-specific by-line formatter
        #
        # @param format [Symbol] Format type (:xml, :json, :yaml, :simple)
        # @param options [Hash] Formatting options
        # @return [BaseFormatter] Format-specific formatter instance
        def self.for_format(format, **options)
          case format
          when :xml
            require_relative "xml_formatter"
            XmlFormatter.new(**options)
          when :json
            require_relative "json_formatter"
            JsonFormatter.new(**options)
          when :yaml
            require_relative "yaml_formatter"
            YamlFormatter.new(**options)
          else
            require_relative "simple_formatter"
            SimpleFormatter.new(**options)
          end
        end

        def initialize(use_color: true, context_lines: 3,
                       diff_grouping_lines: nil, visualization_map: nil)
          @use_color = use_color
          @context_lines = context_lines
          @diff_grouping_lines = diff_grouping_lines
          @visualization_map = visualization_map
        end

        # Format line-by-line diff
        # Subclasses must implement this method
        #
        # @param doc1 [String] First document
        # @param doc2 [String] Second document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          raise NotImplementedError,
                "Subclasses must implement the format method"
        end

        protected

        # Build hunks from diff with context lines
        #
        # @param diffs [Array] LCS diff array
        # @param lines1 [Array<String>] Lines from first document
        # @param lines2 [Array<String>] Lines from second document
        # @param context_lines [Integer] Number of context lines
        # @return [Array<Array>] Array of hunks
        def build_hunks(diffs, _lines1, _lines2, context_lines: 3)
          hunks = []
          current_hunk = []
          last_change_index = -context_lines - 1

          diffs.each_with_index do |change, index|
            # Check if we should start a new hunk
            if !current_hunk.empty? && index - last_change_index > context_lines * 2
              hunks << current_hunk
              current_hunk = []
            end

            # Add context before first change or after gap
            if current_hunk.empty? && change.action != "="
              start_context = [index - context_lines, 0].max
              (start_context...index).each do |i|
                current_hunk << diffs[i] if i < diffs.length
              end
            end

            current_hunk << change

            # Track last change for hunk grouping
            last_change_index = index if change.action != "="
          end

          # Add final hunk if any
          hunks << current_hunk unless current_hunk.empty?

          hunks
        end

        # Colorize text if color is enabled
        # RSpec-aware: resets any existing ANSI codes before applying new colors
        #
        # @param text [String] Text to colorize
        # @param colors [Array<Symbol>] Paint color arguments
        # @return [String] Colorized or plain text
        def colorize(text, *colors)
          return text unless @use_color

          require "paint"
          # Reset ANSI codes first to prevent RSpec's initial red from interfering
          "\e[0m#{Paint[text, *colors]}"
        end
      end
    end
  end
end
