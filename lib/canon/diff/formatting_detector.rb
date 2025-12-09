# frozen_string_literal: true

module Canon
  module Diff
    # Detects if differences between lines are formatting-only
    # (whitespace, line breaks) with no semantic content changes
    class FormattingDetector
      # Detect if two lines differ only in formatting
      #
      # @param line1 [String, nil] First line to compare
      # @param line2 [String, nil] Second line to compare
      # @return [Boolean] true if lines differ only in formatting
      def self.formatting_only?(line1, line2)
        # If both are nil or empty, not a formatting diff
        return false if blank?(line1) && blank?(line2)

        # If only one is blank, it's not just formatting
        return false if blank?(line1) || blank?(line2)

        # Compare normalized versions
        normalize_for_comparison(line1) == normalize_for_comparison(line2)
      end

      # Aggressive normalization for formatting comparison
      # Collapses all whitespace to single space and strips
      # Also normalizes whitespace around tag delimiters
      #
      # @param line [String, nil] Line to normalize
      # @return [String] Normalized line
      def self.normalize_for_comparison(line)
        return "" if line.nil?

        # Collapse all whitespace (spaces, tabs, newlines) to single space
        normalized = line.gsub(/\s+/, " ").strip

        # Normalize whitespace around tag delimiters
        # Remove spaces before > and after <
        normalized = normalized.gsub(/\s+>/, ">") # "div >" -> "div>"
        normalized.gsub(/<\s+/, "<") # "< div" -> "<div"
      end

      # Check if a line is blank (nil or whitespace-only)
      #
      # @param line [String, nil] Line to check
      # @return [Boolean] true if blank
      def self.blank?(line)
        line.nil? || line.strip.empty?
      end

      private_class_method :normalize_for_comparison, :blank?
    end
  end
end
