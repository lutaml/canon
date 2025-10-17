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
      attr_accessor :diff_mode, :use_color, :context_lines, :diff_grouping_lines, :normalize_tag_whitespace

      def configure
        yield self
      end

      def reset_config
        @diff_mode = :by_line
        @use_color = true
        @context_lines = 3
        @diff_grouping_lines = 10
        @normalize_tag_whitespace = false
      end
    end

    # Initialize default configuration
    reset_config

    # Base matcher class for serialization equivalence
    class SerializationMatcher
      def initialize(expected, format = :xml)
        @expected = expected
        unless SUPPORTED_FORMATS.include?(format.to_sym)
          raise Canon::Error, "Unsupported format: #{format}"
        end

        @format = format.to_sym
        @result = nil
      end

      def matches?(target)
        @target = target
        send("match_#{@format}")
      rescue NoMethodError
        raise Canon::Error, "Unsupported format: #{@format}"
      end

      def match_xml
        # Use C14N for comparison (not pretty printing)
        # Even when normalize_tag_whitespace is enabled, we still need to
        # canonicalize for the diff display
        @actual_sorted = Canon::Xml::C14n.canonicalize(@target,
                                                       with_comments: false)
        @expected_sorted = Canon::Xml::C14n.canonicalize(@expected,
                                                         with_comments: false)

        # Check if normalize_tag_whitespace is enabled
        if Canon::RSpecMatchers.normalize_tag_whitespace
          # Use comparison with normalize_tag_whitespace option
          opts = {
            normalize_tag_whitespace: true,
            collapse_whitespace: false,  # Don't use collapse when normalizing
            ignore_comments: true,
            ignore_attr_order: true
          }
          Canon::Comparison::Xml.equivalent?(@target, @expected, opts)
        else
          @actual_sorted == @expected_sorted
        end
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
        # Use Canon::Comparison for HTML comparison
        opts = {
          collapse_whitespace: true,
          ignore_attr_order: true,
          ignore_comments: true,
        }

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
        # Use format-specific comparison modules for by_object mode
        case @format
        when :json
          Canon::Comparison::Json.equivalent?(@expected_sorted, @actual_sorted,
                                              verbose: true)
        when :yaml
          Canon::Comparison::Yaml.equivalent?(@expected_sorted, @actual_sorted,
                                              verbose: true)
        when :xml
          Canon::Comparison::Xml.equivalent?(@expected_sorted, @actual_sorted,
                                             verbose: true)
        when :html, :html4, :html5
          Canon::Comparison::Html.equivalent?(@expected_sorted, @actual_sorted,
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
      rescue StandardError => e
        "\nError generating visual diff: #{e.message}"
      end
    end

    # Matcher methods
    def be_serialization_equivalent_to(expected, format: :xml)
      SerializationMatcher.new(expected, format)
    end

    def be_analogous_with(expected)
      SerializationMatcher.new(expected, :xml)
    end

    def be_xml_equivalent_to(expected)
      SerializationMatcher.new(expected, :xml)
    end

    def be_yaml_equivalent_to(expected)
      SerializationMatcher.new(expected, :yaml)
    end

    def be_json_equivalent_to(expected)
      SerializationMatcher.new(expected, :json)
    end

    def be_html_equivalent_to(expected)
      SerializationMatcher.new(expected, :html)
    end

    def be_html4_equivalent_to(expected)
      SerializationMatcher.new(expected, :html4)
    end

    def be_html5_equivalent_to(expected)
      SerializationMatcher.new(expected, :html5)
    end

    if defined?(::RSpec) && ::RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.include(Canon::RSpecMatchers)
      end
    end
  end
end
