# frozen_string_literal: true

require "canon" unless defined?(::Canon)
require "canon/comparison"
require "diffy"

begin
  require "rspec/expectations"
rescue LoadError
end

module Canon
  module RSpecMatchers
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
        @actual_sorted = Canon::Xml::C14n.canonicalize(@target,
                                                       with_comments: false)
        @expected_sorted = Canon::Xml::C14n.canonicalize(@expected,
                                                         with_comments: false)
        @actual_sorted == @expected_sorted
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

      def failure_message
        generic_failure_message
      end

      def generic_failure_message
        diff = Diffy::Diff.new(
          @expected_sorted,
          @actual_sorted,
          include_diff_info: false,
          include_plus_and_minus_in_html: true,
          diff_options: "-u",
        )

        "expected #{@format.to_s.upcase} to be equivalent\n\n" \
          "Diff:\n" +
          diff.to_s(:color)
      end

      def failure_message_when_negated
        [
          "expected:",
          @target.to_s,
          "not be equivalent to:",
          @expected.to_s,
        ].join("\n")
      end

      def diffable
        true
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
