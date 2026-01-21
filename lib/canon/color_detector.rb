# frozen_string_literal: true

module Canon
  # Detects whether the current terminal supports color output.
  #
  # This class provides cross-platform detection of terminal color capabilities
  # by checking environment variables and, on Unix-like systems, optionally
  # querying the terminfo database.
  #
  # == Detection Logic
  #
  # The detection follows this priority order:
  #
  # 1. **NO_COLOR**: If set (regardless of value), colors are disabled
  #    (per https://no-color.org/)
  # 2. **Explicit user choice**: If explicitly set, honor that choice
  # 3. **Terminal capability detection**:
  #    - COLORTERM=24bit or truecolor → True color support
  #    - TERM ending with 256 or 256color → 256-color support
  #    - TERM=dumb, TERM containing "emacs" → No color support
  #    - CI environment → Check specific CI variables
  #    - TTY detection → Only enable colors if output is to a TTY
  #
  # == Usage
  #
  #   # Auto-detect
  #   ColorDetector.supports_color?  # => true or false
  #
  #   # Explicit choice (bypass detection)
  #   ColorDetector.supports_color?(explicit: true)   # => true
  #   ColorDetector.supports_color?(explicit: false)  # => false
  #
  #   # With output stream check
  #   ColorDetector.supports_color?(output: $stdout)
  #
  class ColorDetector
    # Environment variables that indicate color support
    COLOR_TERM_VALUES = %w[24bit truecolor true].freeze
    COLOR_TERM_SUFFIXES = %w[256 256color direct].freeze
    NO_COLOR_TERMS = %w[dumb emacs].freeze
    CI_ENV_VARS = %w[CI GITHUB_ACTIONS TRAVIS GITLAB_CI JENKINS_HOME].freeze

    class << self
      # Detect whether the current environment supports color output.
      #
      # @param explicit [Boolean, nil] Explicit user choice to bypass detection
      # @param output [IO, nil] Output stream to check (default: $stdout)
      # @return [Boolean] true if colors are supported, false otherwise
      def supports_color?(explicit: nil, output: $stdout)
        # 1. NO_COLOR always wins (per https://no-color.org/)
        return false if ENV.key?("NO_COLOR")

        # 2. Explicit user choice bypasses detection
        return explicit unless explicit.nil?

        # 3. Check if output is a TTY (don't use colors for piped/file output)
        return false unless tty?(output)

        # 4. Check terminal capability indicators
        detect_from_env
      end

      private

      # Check if output stream is a TTY
      #
      # @param io [IO] Output stream
      # @return [Boolean] true if the stream is a TTY
      def tty?(io)
        return false unless io.respond_to?(:tty?)
        return false unless io.respond_to?(:isatty)

        # Ruby 2.5+ uses tty?, older uses isatty
        io.tty? || io.isatty
      rescue ArgumentError, IOError
        # Stream might be closed or invalid
        false
      end

      # Detect color support from environment variables
      #
      # @return [Boolean] true if colors appear to be supported
      def detect_from_env
        # Check for known color-capable terminals
        colorterm = ENV["COLORTERM"]
        return true if COLOR_TERM_VALUES.include?(colorterm)

        # Check TERM variable
        term = ENV["TERM"]
        if term
          # Known no-color terminals
          return false if NO_COLOR_TERMS.any? { |t| term.include?(t) }
          # Known color-capable terminals
          return true if COLOR_TERM_SUFFIXES.any? { |s| term.end_with?(s) }
          # Most modern terminals support basic ANSI colors
          return true unless term.empty? || term == "unknown"
        end

        # Check CI environments
        # Some CI systems support colors, others don't
        return detect_ci_colors if ci_environment?

        # Default: assume colors are supported on modern terminals
        # This is a safe default for most use cases
        true
      end

      # Detect if we're in a CI environment
      #
      # @return [Boolean] true if in a CI environment
      def ci_environment?
        CI_ENV_VARS.any? { |var| ENV.key?(var) }
      end

      # Detect color support in CI environments
      #
      # Different CI systems have different color support:
      # - GitHub Actions: supports colors (explicit CI env vars)
      # - Travis CI: supports colors
      # - GitLab CI: supports colors
      # - Jenkins: supports colors
      # - Generic CI: check for specific TeamCity/Terminal variables
      #
      # @return [Boolean] true if CI environment likely supports colors
      def detect_ci_colors
        # GitHub Actions explicitly supports colors
        return true if ENV["GITHUB_ACTIONS"]

        # TeamCity supports colors with specific env var
        return true if ENV["TEAMCITY_VERSION"]

        # Most modern CI systems support ANSI colors
        # Only disable for explicitly known non-color CI
        return false if ENV["TERM"] == "dumb"

        # Default to supporting colors in CI
        true
      end
    end
  end
end
