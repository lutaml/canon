# frozen_string_literal: true

module Canon
  module Comparison
    # HtmlCompareProfile extends CompareProfile with HTML-specific comparison policies
    #
    # HTML has different semantics than XML:
    # 1. Comments are presentational (default to :ignore unless explicitly :strict)
    # 2. Whitespace preservation required in specific elements
    # 3. Case sensitivity differs between HTML4 and HTML5
    # 4. Self-closing tags handled differently
    #
    # This class provides HTML-specific policy decisions while maintaining
    # the separation of concerns established by CompareProfile.
    class HtmlCompareProfile < CompareProfile
      attr_reader :html_version

      # @param match_options [ResolvedMatchOptions, Hash] The match options to use
      # @param html_version [Symbol] The HTML version (:html4 or :html5)
      def initialize(match_options, html_version: :html5)
        super(match_options)
        @html_version = html_version
      end

      # Override for HTML-specific comment handling
      #
      # In HTML, comments are presentational content (not part of the DOM semantics)
      # unless explicitly set to :strict.
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if differences affect equivalence
      def affects_equivalence?(dimension)
        if dimension == :comments
          if match_options.is_a?(Hash)
            return false unless match_options.key?(:comments)

            return match_options[:comments] == :strict
          elsif match_options.is_a?(ResolvedMatchOptions)
            return behavior_for(dimension) == :strict
          end
          return false
        end

        super
      end

      # Override normative classification for HTML-specific comment handling.
      #
      # Delegates to the parent class for all dimensions, which in turn delegates
      # to Dimension objects.  For :comments, applies the same HTML-specific rule
      # as affects_equivalence? — comments default to non-normative in HTML.
      def normative_dimension?(dimension)
        if dimension == :comments
          return affects_equivalence?(:comments)
        end

        super
      end

      # Check if whitespace should be preserved for a given element
      #
      # HTML has specific elements where whitespace is significant:
      # <pre>, <code>, <textarea>, <script>, <style>
      #
      # @param element_name [String] The element name to check
      # @return [Boolean] true if whitespace should be preserved
      def preserve_whitespace?(element_name)
        html_preserve_elements.include?(element_name.to_s.downcase)
      end

      # Check if element names should be compared case-sensitively
      #
      # HTML4 is case-insensitive, HTML5 is case-sensitive
      #
      # @return [Boolean] true if case-sensitive comparison
      def case_sensitive?
        @html_version == :html5
      end

      private

      # Elements where whitespace is semantically significant in HTML
      #
      # SINGLE SOURCE OF TRUTH: Delegates to WhitespaceSensitivity.format_default_preserve_elements
      # This ensures consistency across the codebase.
      #
      # @return [Array<String>] List of element names (as strings)
      def html_preserve_elements
        WhitespaceSensitivity.format_default_preserve_elements(format: @html_version).map(&:to_s)
      end

      # Check if a dimension is explicitly set to :strict
      # @param dimension [Symbol] The match dimension
      # @return [Boolean] true if explicitly :strict
      def explicitly_strict?(dimension)
        behavior_for(dimension) == :strict
      end

      # Check if an option was explicitly provided in match_options
      # @param dimension [Symbol] The match dimension
      # @return [Boolean] true if option was explicitly set
      def has_explicit_option?(dimension)
        if match_options.is_a?(Hash)
          match_options.key?(dimension)
        elsif match_options.is_a?(ResolvedMatchOptions)
          !match_options.options[dimension].nil?
        else
          false
        end
      end
    end
  end
end
