# frozen_string_literal: true

require "canon" unless defined?(::Canon)
require "canon/comparison"
require "canon/diff_formatter"

begin
  require "rspec/expectations"
rescue LoadError
end

module Canon
  module RSpecMatchers
    # Configuration for RSpec matchers
    class << self
      attr_accessor :diff_mode, :use_color, :context_lines,
                    :diff_grouping_lines, :normalize_tag_whitespace,
                    :xml_match_profile, :html_match_profile,
                    :xml_match_options, :html_match_options,
                    :xml_preprocessing, :html_preprocessing

      def configure
        yield self
      end

      def reset_config
        @diff_mode = :by_line
        @use_color = true
        @context_lines = 3
        @diff_grouping_lines = 10
        @normalize_tag_whitespace = false
        @xml_match_profile = nil
        @html_match_profile = nil
        @xml_match_options = nil
        @html_match_options = nil
        @xml_preprocessing = nil
        @html_preprocessing = nil
      end
    end

    # Initialize default configuration
    reset_config

    # Base matcher class for serialization equivalence
    class SerializationMatcher
      def initialize(expected, format = :xml, match_profile: nil,
match_options: nil, preprocessing: nil)
        @expected = expected
        unless SUPPORTED_FORMATS.include?(format.to_sym)
          raise Canon::Error, "Unsupported format: #{format}"
        end

        @format = format.to_sym
        @result = nil
        @match_profile = match_profile
        @match_options = match_options
        @preprocessing = preprocessing
      end

      def matches?(target)
        @target = target
        send("match_#{@format}")
      rescue NoMethodError
        raise Canon::Error, "Unsupported format: #{@format}"
      end

      def match_xml
        # Build comparison options
        opts = {
          ignore_comments: true,
          ignore_attr_order: true,
        }

        # Pass per-test parameters (highest priority)
        opts[:match_profile] = @match_profile if @match_profile
        opts[:match_options] = @match_options if @match_options
        opts[:preprocessing] = @preprocessing if @preprocessing

        # Pass global configuration (lower priority)
        opts[:global_profile] = Canon::RSpecMatchers.xml_match_profile
        opts[:global_options] = Canon::RSpecMatchers.xml_match_options

        # Use XmlComparator for comparison (it will resolve precedence)
        result = if @match_profile || @match_options ||
            Canon::RSpecMatchers.xml_match_profile ||
            Canon::RSpecMatchers.xml_match_options
                   # Use MECE match options with full precedence handling
                   Canon::Comparison::XmlComparator.equivalent?(@target,
                                                                @expected, opts)
                 elsif Canon::RSpecMatchers.normalize_tag_whitespace
                   # Legacy behavior for backward compatibility
                   opts[:normalize_tag_whitespace] = true
                   opts[:collapse_whitespace] = false
                   Canon::Comparison::XmlComparator.equivalent?(@target,
                                                                @expected, opts)
                 else
                   # Default: strict C14N comparison
                   nil
                 end

        # Set sorted versions for diff display (after comparison)
        @actual_sorted = Canon::Xml::C14n.canonicalize(@target,
                                                       with_comments: false)
        @expected_sorted = Canon::Xml::C14n.canonicalize(@expected,
                                                         with_comments: false)

        # Return comparison result or fallback to C14N comparison
        result.nil? ? (@actual_sorted == @expected_sorted) : result
      end

      # Canonicalize and check string equivalence for YAML/JSON
      def match_yaml
        canonicalize_and_compare(:yaml)
      end

      def match_json
        canonicalize_and_compare(:json)
      end

      def match_html
        html_semantic_compare(:html)
      end

      def match_html4
        html_semantic_compare(:html4)
      end

      def match_html5
        html_semantic_compare(:html5)
      end

      private

      def canonicalize_and_compare(format)
        @actual_sorted = Canon.format(@target, format)
        @expected_sorted = Canon.format(@expected, format)
        @actual_sorted == @expected_sorted
      end

      def html_semantic_compare(format)
        # Build comparison options
        opts = {
          collapse_whitespace: true,
          ignore_attr_order: true,
          ignore_comments: true,
        }

        # Pass per-test parameters (highest priority)
        opts[:match_profile] = @match_profile if @match_profile
        opts[:match_options] = @match_options if @match_options
        opts[:preprocessing] = @preprocessing if @preprocessing

        # Pass global configuration (lower priority)
        opts[:global_profile] = Canon::RSpecMatchers.html_match_profile
        opts[:global_options] = Canon::RSpecMatchers.html_match_options

        # Parse and normalize HTML for error messages
        actual_doc = parse_html_for_display(@target, format)
        expected_doc = parse_html_for_display(@expected, format)

        @actual_sorted = actual_doc
        @expected_sorted = expected_doc

        # Use Canon::Comparison for actual comparison
        Canon::Comparison.equivalent?(@target, @expected, opts)
      end

      def parse_html_for_display(html, format)
        require "nokogiri"

        # Parse with Nokogiri
        doc = if format == :html5
                Nokogiri::HTML5(html)
              else
                Nokogiri::HTML(html)
              end

        # Return normalized HTML string for display
        doc.to_html
      rescue StandardError
        # Fallback to original string if parsing fails
        html
      end

      public

      def failure_message
        msg = "expected #{@format.to_s.upcase} to be equivalent\n\n"

        # Generate visual diff
        diff_output = generate_visual_diff
        msg + diff_output if diff_output
      end

      def failure_message_when_negated
        "expected #{@format.to_s.upcase} not to be equivalent"
      end

      def expected
        @expected_sorted || @expected
      end

      def actual
        @actual_sorted || @target
      end

      def diffable
        # Disable RSpec's built-in diff - we use our own
        false
      end

      private

      def compare_for_diff_mode
        # Use format-specific comparison classes for by_object mode
        case @format
        when :json
          Canon::Comparison::JsonComparator.equivalent?(@expected_sorted, @actual_sorted,
                                                        verbose: true)
        when :yaml
          Canon::Comparison::YamlComparator.equivalent?(@expected_sorted, @actual_sorted,
                                                        verbose: true)
        when :xml
          Canon::Comparison::XmlComparator.equivalent?(@expected_sorted, @actual_sorted,
                                                       verbose: true)
        when :html, :html4, :html5
          Canon::Comparison::HtmlComparator.equivalent?(@expected_sorted, @actual_sorted,
                                                        verbose: true)
        else
          []
        end
      end

      def generate_visual_diff
        return nil unless @actual_sorted && @expected_sorted

        # Get configuration settings
        diff_mode = Canon::RSpecMatchers.diff_mode || :by_line
        use_color = Canon::RSpecMatchers.use_color.nil? || Canon::RSpecMatchers.use_color
        context_lines = Canon::RSpecMatchers.context_lines || 3
        diff_grouping_lines = Canon::RSpecMatchers.diff_grouping_lines

        # Show diff of the actual canonicalized versions being compared
        # This ensures we see exactly what the comparison algorithm sees
        formatter = Canon::DiffFormatter.new(use_color: use_color,
                                             mode: diff_mode,
                                             context_lines: context_lines,
                                             diff_grouping_lines: diff_grouping_lines)

        # For by_object mode, compute actual differences using Comparison
        # For by_line mode, pass empty array and let formatter do line-by-line diff
        differences = if diff_mode == :by_object
                        compare_for_diff_mode
                      else
                        []
                      end

        case @format
        when :xml
          # For XML, show diff of the RAW C14N versions (what's actually compared)
          # Split into lines for readability
          doc1 = @expected_sorted.gsub(/></, ">\n<")
          doc2 = @actual_sorted.gsub(/></, ">\n<")
          formatter.format(differences, :xml, doc1: doc1, doc2: doc2)
        when :html, :html4, :html5
          formatter.format(differences, @format, doc1: @expected_sorted,
                                                 doc2: @actual_sorted)
        when :json
          formatter.format(differences, :json, doc1: @expected_sorted,
                                               doc2: @actual_sorted)
        when :yaml
          formatter.format(differences, :yaml, doc1: @expected_sorted,
                                               doc2: @actual_sorted)
        end
      rescue Canon::ValidationError
        # Let validation errors propagate to RSpec output
        raise
      rescue StandardError => e
        "\nUnexpected error generating diff: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    # Matcher methods
    def be_serialization_equivalent_to(expected, format: :xml,
match_profile: nil, match_options: nil, preprocessing: nil)
      SerializationMatcher.new(expected, format,
                               match_profile: match_profile,
                               match_options: match_options,
                               preprocessing: preprocessing)
    end

    def be_analogous_with(expected, match_profile: nil, match_options: nil,
preprocessing: nil)
      SerializationMatcher.new(expected, :xml,
                               match_profile: match_profile,
                               match_options: match_options,
                               preprocessing: preprocessing)
    end

    def be_xml_equivalent_to(expected, match_profile: nil, match_options: nil,
preprocessing: nil)
      SerializationMatcher.new(expected, :xml,
                               match_profile: match_profile,
                               match_options: match_options,
                               preprocessing: preprocessing)
    end

    def be_yaml_equivalent_to(expected)
      SerializationMatcher.new(expected, :yaml)
    end

    def be_json_equivalent_to(expected)
      SerializationMatcher.new(expected, :json)
    end

    def be_html_equivalent_to(expected, match_profile: nil, match_options: nil,
preprocessing: nil)
      SerializationMatcher.new(expected, :html,
                               match_profile: match_profile,
                               match_options: match_options,
                               preprocessing: preprocessing)
    end

    def be_html4_equivalent_to(expected, match_profile: nil,
match_options: nil, preprocessing: nil)
      SerializationMatcher.new(expected, :html4,
                               match_profile: match_profile,
                               match_options: match_options,
                               preprocessing: preprocessing)
    end

    def be_html5_equivalent_to(expected, match_profile: nil,
match_options: nil, preprocessing: nil)
      SerializationMatcher.new(expected, :html5,
                               match_profile: match_profile,
                               match_options: match_options,
                               preprocessing: preprocessing)
    end

    if defined?(::RSpec) && ::RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.include(Canon::RSpecMatchers)
      end
    end
  end
end
