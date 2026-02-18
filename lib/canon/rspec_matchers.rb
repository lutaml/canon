# frozen_string_literal: true

require "canon" unless defined?(::Canon)
require "canon/comparison"
require "canon/diff_formatter"
require "canon/config"

begin
  require "rspec/expectations"
rescue LoadError
end

module Canon
  module RSpecMatchers
    # Configuration for RSpec matchers - delegates to Canon::Config
    class << self
      def configure
        yield Canon::Config.configure
      end

      def reset_config
        Canon::Config.reset!
      end

      # Delegate configuration getters to Canon::Config
      def xml
        Canon::Config.instance.xml
      end

      def html
        Canon::Config.instance.html
      end

      def json
        Canon::Config.instance.json
      end

      def yaml
        Canon::Config.instance.yaml
      end
    end

    # Base matcher class for serialization equivalence
    # This is a THIN WRAPPER around Canon::Comparison API
    class SerializationMatcher
      def initialize(expected, format = nil, match_profile: nil,
                     match: nil, preprocessing: nil, diff_algorithm: nil,
                     show_diffs: nil)
        @expected = expected
        @format = format&.to_sym
        @match_profile = match_profile
        @match = match
        @preprocessing = preprocessing
        @diff_algorithm = diff_algorithm
        @show_diffs = show_diffs
      end

      # Chain method for controlling diff display
      # @param value [Symbol, String] :all, :normative, or :informative
      # @return [SerializationMatcher] self for chaining
      def show_diffs(value)
        @show_diffs = value.to_sym
        self
      end

      # Chain method for setting match options
      # @param match_opts [Hash] match options
      # @return [SerializationMatcher] self for chaining
      def with_match(**match_opts)
        @match ||= {}
        @match = @match.merge(match_opts)
        self
      end

      # Chain method for setting match profile
      # @param profile_name [Symbol] Profile name (:strict, :spec_friendly, etc.)
      # @return [SerializationMatcher] self for chaining
      def with_profile(profile_name)
        @match_profile = profile_name
        self
      end

      # Chain method for setting match options (alias for with_match)
      # @param options [Hash] Match dimension options
      # @return [SerializationMatcher] self for chaining
      def with_options(**options)
        with_match(**options)
      end

      def matches?(target)
        @target = target

        # Build comparison options from config and matcher params
        opts = build_comparison_options

        # Add format hint if explicitly provided
        opts[:format] = @format if @format

        # Delegate to Canon::Comparison.equivalent? - the SINGLE source of truth
        # Comparison handles format detection, HTML parsing, and all business logic
        @comparison_result = Canon::Comparison.equivalent?(
          @expected,
          @target,
          opts,
        )

        # When verbose: true, result is a ComparisonResult object
        # Use the equivalent? method to check for normative differences
        case @comparison_result
        when Canon::Comparison::ComparisonResult
          @comparison_result.equivalent?
        when Hash
          # Legacy format - Hash with :differences array and :preprocessed strings
          @comparison_result[:differences].empty?
        when Array
          # Legacy format - XML/JSON/YAML returns []
          @comparison_result.empty?
        else
          # Boolean result
          @comparison_result
        end
      end

      def failure_message
        "expected #{format_name} to be equivalent\n\n#{diff_output}"
      end

      def failure_message_when_negated
        "expected #{format_name} not to be equivalent"
      end

      def expected
        @expected
      end

      def actual
        @target
      end

      def diffable
        false
      end

      private

      def format_name
        # Use explicitly provided format if available
        if @format
          case @format
          when :html4, :html5 then "HTML"
          when :string then "STRING"
          else @format.to_s.upcase
          end
        else
          # Fall back to detection only if format not provided
          begin
            detected_format = Canon::Comparison::FormatDetector.detect(@expected)
            detected_format.to_s.upcase
          rescue StandardError
            "CONTENT"
          end
        end
      end

      def build_comparison_options
        opts = { verbose: true } # Always use verbose for diff generation

        # Add per-test parameters (highest priority)
        opts[:match_profile] = @match_profile if @match_profile
        opts[:match] = @match if @match
        opts[:preprocessing] = @preprocessing if @preprocessing
        opts[:diff_algorithm] = @diff_algorithm if @diff_algorithm
        opts[:show_diffs] = @show_diffs if @show_diffs

        # Add global configuration from Canon::Config (lower priority)
        if @format
          config_format = normalize_format_for_config(@format)

          # Only access config if format is supported
          if Canon::Config.instance.respond_to?(config_format)
            format_config = Canon::Config.instance.public_send(config_format)
            if format_config.match.profile
              opts[:global_profile] =
                format_config.match.profile
            end
            unless format_config.match.options.empty?
              opts[:global_options] =
                format_config.match.options
            end
            opts[:preprocessing] ||= format_config.preprocessing
            # Add diff algorithm from config if not explicitly set
            opts[:diff_algorithm] ||= format_config.diff.algorithm if format_config.diff.algorithm
          elsif !%i[xml html html4 html5 json yaml
                    string].include?(@format)
            # Unsupported format - raise error early
            raise Canon::Error, "Unsupported format: #{@format}"
          end
        end

        opts
      end

      def normalize_format_for_config(format)
        case format
        when :html4, :html5 then :html
        else format
        end
      end

      def diff_output
        # For string format, use simple diff since there's no comparison_result
        if @format == :string
          config_format = :xml # Use XML config as fallback for string
          diff_config = Canon::Config.instance.public_send(config_format).diff

          formatter = Canon::DiffFormatter.new(
            use_color: diff_config.use_color,
            mode: :by_line, # Always use by_line for strings
            context_lines: diff_config.context_lines,
            diff_grouping_lines: diff_config.grouping_lines,
            show_diffs: diff_config.show_diffs,
          )

          return formatter.format([], :string, doc1: @expected.to_s,
                                               doc2: @target.to_s)
        end

        # Get diff configuration
        config_format = normalize_format_for_config(@format || :xml)
        diff_config = Canon::Config.instance.public_send(config_format).diff

        # Delegate to Canon::DiffFormatter - the SINGLE source of diff generation
        formatter = Canon::DiffFormatter.new(
          use_color: diff_config.use_color,
          mode: diff_config.mode,
          context_lines: diff_config.context_lines,
          diff_grouping_lines: diff_config.grouping_lines,
          show_diffs: diff_config.show_diffs,
          verbose_diff: diff_config.verbose_diff,
        )

        # Format the diff using the comparison result
        formatter.format_comparison_result(@comparison_result, @expected,
                                           @target)
      rescue StandardError => e
        "\nError generating diff: #{e.message}"
      end
    end

    # Matcher methods
    def be_serialization_equivalent_to(expected, format: :xml,
                                      match_profile: nil, match: nil,
                                      preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, format,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_analogous_with(expected, match_profile: nil, match: nil,
                         preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :xml,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_xml_equivalent_to(expected, match_profile: nil, match: nil,
                            preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :xml,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_yaml_equivalent_to(expected, match_profile: nil, match: nil,
                              preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :yaml,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_json_equivalent_to(expected, match_profile: nil, match: nil,
                              preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :json,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_html_equivalent_to(expected, match_profile: nil, match: nil,
                             preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :html,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_html4_equivalent_to(expected, match_profile: nil, match: nil,
                              preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :html4,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_html5_equivalent_to(expected, match_profile: nil, match: nil,
                              preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :html5,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_equivalent_to(expected, match_profile: nil, match: nil,
                         preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, nil,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    def be_string_equivalent_to(expected, match_profile: nil, match: nil,
                                 preprocessing: nil, diff_algorithm: nil)
      SerializationMatcher.new(expected, :string,
                               match_profile: match_profile,
                               match: match,
                               preprocessing: preprocessing,
                               diff_algorithm: diff_algorithm)
    end

    if defined?(::RSpec) && ::RSpec.respond_to?(:configure)
      RSpec.configure do |config|
        config.include(Canon::RSpecMatchers)
      end
    end
  end
end
