# frozen_string_literal: true

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
      def method_missing(method, *args, &block)
        if @instance.respond_to?(method)
          @instance.send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        (@instance && @instance.respond_to?(method)) || super
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
        @match = MatchConfig.new
        @diff = DiffConfig.new
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
      attr_accessor :profile
      attr_reader :options

      def initialize
        @profile = nil
        @options = {}
      end

      def options=(value)
        @options = value || {}
      end

      def reset!
        @profile = nil
        @options = {}
      end

      # Build match options from profile and options
      def to_h
        result = {}
        result[:match_profile] = @profile if @profile
        result[:match] = @options if @options && !@options.empty?
        result
      end
    end

    # Diff configuration for output formatting
    class DiffConfig
      attr_accessor :mode, :use_color, :context_lines, :grouping_lines

      def initialize
        @mode = :by_line
        @use_color = true
        @context_lines = 3
        @grouping_lines = 10
      end

      def reset!
        @mode = :by_line
        @use_color = true
        @context_lines = 3
        @grouping_lines = 10
      end

      # Build diff options
      def to_h
        {
          diff: @mode,
          use_color: @use_color,
          context_lines: @context_lines,
          grouping_lines: @grouping_lines,
        }
      end
    end
  end
end
