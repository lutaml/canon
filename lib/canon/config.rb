# frozen_string_literal: true

require_relative "config/env_provider"
require_relative "config/override_resolver"
require_relative "color_detector"

module Canon
  # Global configuration for Canon
  # Provides unified configuration across CLI, Ruby API, and RSpec interfaces
  class Config
    class << self
      def instance
        @instance ||= new
      end

      def configure
        yield instance if block_given?
        instance
      end

      def reset!
        @instance = new
      end

      # Delegate to instance
      def method_missing(method, ...)
        if @instance.respond_to?(method)
          @instance.send(method, ...)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @instance.respond_to?(method) || super
      end
    end

    attr_reader :xml, :html, :json, :yaml, :string

    def initialize
      @xml = FormatConfig.new(:xml)
      @html = FormatConfig.new(:html)
      @json = FormatConfig.new(:json)
      @yaml = FormatConfig.new(:yaml)
      @string = FormatConfig.new(:string)
    end

    def reset!
      @xml.reset!
      @html.reset!
      @json.reset!
      @yaml.reset!
      @string.reset!
    end

    # Backward compatibility methods for top-level diff configuration
    # These delegate to XML diff config for backward compatibility
    def diff_mode
      @xml.diff.mode
    end

    def diff_mode=(value)
      @xml.diff.mode = value
    end

    def use_color
      @xml.diff.use_color
    end

    def use_color=(value)
      @xml.diff.use_color = value
    end

    # Backward compatibility methods for match profile configuration
    def xml_match_profile
      @xml.match.profile
    end

    def xml_match_profile=(value)
      @xml.match.profile = value
    end

    def html_match_profile
      @html.match.profile
    end

    def html_match_profile=(value)
      @html.match.profile = value
    end

    # Format-specific configuration
    # Each format (XML, HTML, JSON, YAML) has its own instance
    class FormatConfig
      attr_reader :format, :match, :diff
      attr_accessor :preprocessing

      def initialize(format)
        @format = format
        @match = MatchConfig.new(format)
        @diff = DiffConfig.new(format)
        @preprocessing = nil
      end

      def reset!
        @match.reset!
        @diff.reset!
        @preprocessing = nil
      end
    end

    # Match configuration for comparison behavior
    class MatchConfig
      attr_reader :options

      def initialize(format = nil)
        @format = format
        @resolver = build_resolver(format)
        @options = {}
      end

      def options=(value)
        @options = value || {}
      end

      def reset!
        @resolver = build_resolver(@format)
        @options = {}
      end

      # Profile accessor with ENV override support
      def profile
        @resolver.resolve(:profile)
      end

      def profile=(value)
        @resolver.set_programmatic(:profile, value)
      end

      # Build match options from profile and options
      def to_h
        result = {}
        result[:match_profile] = profile if profile
        result[:match] = @options if @options && !@options.empty?
        result
      end

      private

      def build_resolver(format)
        defaults = {
          profile: nil,
        }

        env = format ? EnvProvider.load_match_for_format(format) : {}

        OverrideResolver.new(
          defaults: defaults,
          programmatic: {},
          env: env,
        )
      end
    end

    # Diff configuration for output formatting
    class DiffConfig
      def initialize(format = nil)
        @format = format
        @resolver = build_resolver(format)
      end

      def reset!
        @resolver = build_resolver(@format)
      end

      # Accessors with ENV override support
      def mode
        @resolver.resolve(:mode)
      end

      def mode=(value)
        @resolver.set_programmatic(:mode, value)
      end

      def use_color
        @resolver.resolve(:use_color)
      end

      def use_color=(value)
        @resolver.set_programmatic(:use_color, value)
      end

      def context_lines
        @resolver.resolve(:context_lines)
      end

      def context_lines=(value)
        @resolver.set_programmatic(:context_lines, value)
      end

      def grouping_lines
        @resolver.resolve(:grouping_lines)
      end

      def grouping_lines=(value)
        @resolver.set_programmatic(:grouping_lines, value)
      end

      def show_diffs
        @resolver.resolve(:show_diffs)
      end

      def show_diffs=(value)
        @resolver.set_programmatic(:show_diffs, value)
      end

      def verbose_diff
        @resolver.resolve(:verbose_diff)
      end

      def verbose_diff=(value)
        @resolver.set_programmatic(:verbose_diff, value)
      end

      def show_raw_inputs
        @resolver.resolve(:show_raw_inputs)
      end

      def show_raw_inputs=(value)
        @resolver.set_programmatic(:show_raw_inputs, value)
      end

      def show_preprocessed_inputs
        @resolver.resolve(:show_preprocessed_inputs)
      end

      def show_preprocessed_inputs=(value)
        @resolver.set_programmatic(:show_preprocessed_inputs, value)
      end

      def show_line_numbered_inputs
        @resolver.resolve(:show_line_numbered_inputs)
      end

      def show_line_numbered_inputs=(value)
        @resolver.set_programmatic(:show_line_numbered_inputs, value)
      end

      def display_format
        @resolver.resolve(:display_format)
      end

      def display_format=(value)
        @resolver.set_programmatic(:display_format, value)
      end

      def algorithm
        @resolver.resolve(:algorithm)
      end

      def algorithm=(value)
        @resolver.set_programmatic(:algorithm, value)
      end

      # File size limit in bytes (default 5MB)
      def max_file_size
        @resolver.resolve(:max_file_size)
      end

      def max_file_size=(value)
        @resolver.set_programmatic(:max_file_size, value)
      end

      # Maximum node count in tree (default 10,000)
      def max_node_count
        @resolver.resolve(:max_node_count)
      end

      def max_node_count=(value)
        @resolver.set_programmatic(:max_node_count, value)
      end

      # Maximum diff output lines (default 10,000)
      def max_diff_lines
        @resolver.resolve(:max_diff_lines)
      end

      def max_diff_lines=(value)
        @resolver.set_programmatic(:max_diff_lines, value)
      end

      # Build diff options
      def to_h
        {
          diff: mode,
          use_color: use_color,
          context_lines: context_lines,
          grouping_lines: grouping_lines,
          show_diffs: show_diffs,
          verbose_diff: verbose_diff,
          diff_algorithm: algorithm,
          show_raw_inputs: show_raw_inputs,
          show_preprocessed_inputs: show_preprocessed_inputs,
          show_line_numbered_inputs: show_line_numbered_inputs,
          display_format: display_format,
          max_file_size: max_file_size,
          max_node_count: max_node_count,
          max_diff_lines: max_diff_lines,
        }
      end

      private

      def build_resolver(format)
        defaults = {
          mode: :by_line,
          use_color: ColorDetector.supports_color?,
          context_lines: 3,
          grouping_lines: 10,
          show_diffs: :all,
          verbose_diff: false,
          algorithm: :dom,
          show_raw_inputs: false,
          show_preprocessed_inputs: false,
          show_line_numbered_inputs: false,
          display_format: :raw,     # :raw = no formatting, :canonical = HTML-aware formatting
          max_file_size: 5_242_880, # 5MB in bytes
          max_node_count: 10_000,   # Maximum nodes in tree
          max_diff_lines: 10_000,   # Maximum diff output lines
        }

        env = format ? EnvProvider.load_diff_for_format(format) : {}

        OverrideResolver.new(
          defaults: defaults,
          programmatic: {},
          env: env,
        )
      end
    end
  end
end
