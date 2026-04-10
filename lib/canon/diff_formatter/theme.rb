# frozen_string_literal: true

module Canon
  class DiffFormatter
    # Theme definitions for diff display.
    #
    # Theme is a nested hash structure:
    # - diff: removed/added/changed/unchanged/formatting/informative
    # - xml: tag/attribute_name/attribute_value/text/comment/cdata
    # - html: same as xml
    # - structure: line_number/pipe/context
    # - visualization: space/tab/newline/nbsp
    # - display_mode: :separate/:inline/:mixed
    #
    # Each styled element has: color, bg, bold, underline, strikethrough, italic
    module Theme
      # Valid ANSI color values (standard 16 + common extended colors)
      # Standard: 8 colors + 8 bright variants
      # Extended: light_ variants (for backgrounds), amber (retro terminal)
      VALID_COLORS = %i[
        default black red green yellow blue magenta cyan white
        bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white
        light_red light_green light_blue light_cyan light_magenta light_yellow light_black light_white
        amber
      ].freeze

      # Valid display modes
      VALID_DISPLAY_MODES = %i[separate inline mixed].freeze

      # Base properties for any styled element
      STYLING_PROPERTIES = %i[color bg bold underline strikethrough
                              italic].freeze

      # =====================================================================
      # LIGHT THEME - Light terminal backgrounds, professional use
      # =====================================================================
      LIGHT = {
        name: "Light",
        description: "Light terminal backgrounds - professional, high contrast",

        diff: {
          removed: {
            marker: { color: :red, bg: :light_red, bold: false },
            content: { color: :red, bg: nil, bold: false, underline: false,
                       strikethrough: true },
          },
          added: {
            marker: { color: :green, bg: :light_green, bold: false },
            content: { color: :green, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          changed: {
            marker: { color: :bright_red, bg: nil, bold: true },
            content_old: { color: :bright_red,   bg: nil, bold: true,
                           underline: false, strikethrough: true },
            content_new: { color: :bright_green, bg: nil, bold: true,
                           underline: true, strikethrough: false },
          },
          unchanged: {
            content: { color: :default, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          formatting: {
            marker: { color: :bright_blue, bg: nil, bold: false },
            content: { color: :bright_blue, bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
          informative: {
            marker: { color: :bright_magenta, bg: nil, bold: false },
            content: { color: :bright_magenta, bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
        },

        xml: {
          tag: { color: :bright_blue, bg: nil, bold: true, italic: false },
          attribute_name: { color: :magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :magenta, bg: nil, bold: false, italic: true },
          cdata: { color: :yellow, bg: nil, bold: false, italic: false },
        },

        html: {
          tag: { color: :bright_blue, bg: nil, bold: true, italic: false },
          attribute_name: { color: :magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :magenta, bg: nil, bold: false, italic: true },
          cdata: { color: :yellow, bg: nil, bold: false, italic: false },
        },

        structure: {
          line_number: { color: :black },
          pipe: { color: :black },
          context: { color: :black },
        },

        visualization: {
          space: "░",
          tab: "→",
          newline: "¶",
          nbsp: "␣",
        },

        display_mode: :separate,
      }.freeze

      # =====================================================================
      # DARK THEME - Dark terminal backgrounds, developer favorite
      # =====================================================================
      DARK = {
        name: "Dark",
        description: "Dark terminal backgrounds - saturated colors, no backgrounds",

        diff: {
          removed: {
            marker: { color: :red, bg: nil, bold: false },
            content: { color: :red, bg: nil, bold: false, underline: false,
                       strikethrough: true },
          },
          added: {
            marker: { color: :green, bg: nil, bold: false },
            content: { color: :green,       bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
          changed: {
            marker: { color: :yellow,       bg: nil, bold: true },
            content_old: { color: :bright_red,   bg: nil, bold: false,
                           underline: false, strikethrough: true },
            content_new: { color: :bright_green, bg: nil, bold: false,
                           underline: true, strikethrough: false },
          },
          unchanged: {
            content: { color: :default, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          formatting: {
            marker: { color: :bright_blue, bg: nil, bold: false },
            content: { color: :bright_blue, bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
          informative: {
            marker: { color: :cyan, bg: nil, bold: false },
            content: { color: :cyan, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
        },

        xml: {
          tag: { color: :bright_blue, bg: nil, bold: true, italic: false },
          attribute_name: { color: :magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :cyan, bg: nil, bold: false, italic: true },
          cdata: { color: :yellow, bg: nil, bold: false, italic: false },
        },

        html: {
          tag: { color: :bright_blue, bg: nil, bold: true, italic: false },
          attribute_name: { color: :magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :cyan, bg: nil, bold: false, italic: true },
          cdata: { color: :yellow, bg: nil, bold: false, italic: false },
        },

        structure: {
          line_number: { color: :white },
          pipe: { color: :white },
          context: { color: :white },
        },

        visualization: {
          space: "░",
          tab: "→",
          newline: "¶",
          nbsp: "␣",
        },

        display_mode: :separate,
      }.freeze

      # =====================================================================
      # RETRO THEME - Amber CRT, low blue light, accessibility
      # =====================================================================
      RETRO = {
        name: "Retro",
        description: "Amber CRT phosphor - monochromatic amber, low blue light, high accessibility",

        diff: {
          removed: {
            # Bright amber on amber background = inverse video, highest emphasis
            marker: { color: :bright_yellow, bg: :yellow, bold: true },
            content: { color: :bright_yellow, bg: :yellow, bold: true,
                       underline: false, strikethrough: false },
          },
          added: {
            # Bright white = less emphasis than removed, but distinct from normal text
            marker: { color: :bright_white, bg: nil, bold: true },
            content: { color: :bright_white, bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
          changed: {
            marker: { color: :bright_yellow, bg: :yellow, bold: true },
            content_old: { color: :bright_yellow, bg: :yellow, bold: true,
                           underline: false, strikethrough: true },
            content_new: { color: :bright_white, bg: nil, bold: false,
                           underline: true, strikethrough: false },
          },
          unchanged: {
            content: { color: :yellow, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          formatting: {
            # Dimmer amber + strikethrough = clearly different from normal text
            marker: { color: :yellow, bg: nil, bold: false,
                      strikethrough: true },
            content: { color: :yellow, bg: nil, bold: false, underline: false,
                       strikethrough: true },
          },
          informative: {
            # Bright amber + underline = distinct from formatting and normal
            marker: { color: :bright_yellow, bg: nil, bold: true,
                      underline: true },
            content: { color: :bright_yellow, bg: nil, bold: true,
                       underline: true, strikethrough: false },
          },
        },

        xml: {
          # Amber monochrome for all XML elements
          tag: { color: :bright_yellow, bg: nil, bold: true, italic: false },
          attribute_name: { color: :bright_yellow, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :bright_yellow, bg: nil, bold: false,
                             italic: false },
          text: { color: :yellow, bg: nil, bold: false, italic: false },
          comment: { color: :yellow, bg: nil, bold: false, italic: true },
          cdata: { color: :bright_yellow, bg: nil, bold: false, italic: false },
        },

        html: {
          tag: { color: :bright_yellow, bg: nil, bold: true, italic: false },
          attribute_name: { color: :bright_yellow, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :bright_yellow, bg: nil, bold: false,
                             italic: false },
          text: { color: :yellow, bg: nil, bold: false, italic: false },
          comment: { color: :yellow, bg: nil, bold: false, italic: true },
          cdata: { color: :bright_yellow, bg: nil, bold: false, italic: false },
        },

        structure: {
          line_number: { color: :yellow },
          pipe: { color: :yellow },
          context: { color: :yellow },
        },

        visualization: {
          space: "░",
          tab: "→",
          newline: "¶",
          nbsp: "␣",
        },

        display_mode: :separate,
      }.freeze

      # =====================================================================
      # CLAUDE THEME - Claude Code diff style, high contrast HUD
      # =====================================================================
      CLAUDE = {
        name: "Claude",
        description: "Claude Code diff style - red/green backgrounds, maximum visual pop",

        diff: {
          removed: {
            # Red background + white text = immediate visual pop
            marker: { color: :white, bg: :red, bold: true },
            content: { color: :white, bg: :red, bold: false, underline: false,
                       strikethrough: false },
          },
          added: {
            # Green background + white text (black invisible on dark terminals)
            marker: { color: :white, bg: :green, bold: true },
            content: { color: :white, bg: :green, bold: false,
                       underline: false, strikethrough: false },
          },
          changed: {
            marker: { color: :white, bg: :magenta, bold: true },
            content_old: { color: :bright_red,   bg: nil, bold: false,
                           underline: false, strikethrough: true },
            content_new: { color: :bright_green, bg: nil, bold: false,
                           underline: true, strikethrough: false },
          },
          unchanged: {
            content: { color: :default, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          formatting: {
            marker: { color: :yellow, bg: nil, bold: false },
            content: { color: :yellow, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          informative: {
            marker: { color: :bright_cyan, bg: nil, bold: false },
            content: { color: :bright_cyan, bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
        },

        xml: {
          tag: { color: :bright_blue, bg: nil, bold: true, italic: false },
          attribute_name: { color: :magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :cyan, bg: nil, bold: false, italic: true },
          cdata: { color: :yellow, bg: nil, bold: false, italic: false },
        },

        html: {
          tag: { color: :bright_blue, bg: nil, bold: true, italic: false },
          attribute_name: { color: :magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :cyan, bg: nil, bold: false, italic: true },
          cdata: { color: :yellow, bg: nil, bold: false, italic: false },
        },

        structure: {
          line_number: { color: :yellow },
          pipe: { color: :yellow },
          context: { color: :white },
        },

        visualization: {
          space: "░",
          tab: "→",
          newline: "¶",
          nbsp: "␣",
        },

        display_mode: :separate,
      }.freeze

      # =====================================================================
      # CYBERPUNK THEME - Neon on black, high contrast, futuristic
      # =====================================================================
      CYBERPUNK = {
        name: "Cyberpunk",
        description: "Neon on black - high contrast, futuristic, electric",

        diff: {
          removed: {
            # Hot pink/magenta neon for deletions
            marker: { color: :bright_magenta, bg: nil, bold: true },
            content: { color: :bright_magenta, bg: nil, bold: true,
                       underline: false, strikethrough: true },
          },
          added: {
            # Electric cyan neon for additions
            marker: { color: :bright_cyan, bg: nil, bold: true },
            content: { color: :bright_cyan, bg: nil, bold: true,
                       underline: false, strikethrough: false },
          },
          changed: {
            # Yellow warning neon for change markers
            marker: { color: :bright_yellow, bg: nil, bold: true },
            content_old: { color: :bright_magenta, bg: nil, bold: false,
                           underline: false, strikethrough: true },
            content_new: { color: :bright_cyan,    bg: nil, bold: false,
                           underline: true, strikethrough: false },
          },
          unchanged: {
            content: { color: :default, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          formatting: {
            # Dim green for low-priority formatting
            marker: { color: :green, bg: nil, bold: false },
            content: { color: :green, bg: nil, bold: false, underline: false,
                       strikethrough: false },
          },
          informative: {
            # Bright yellow neon for informative
            marker: { color: :bright_yellow, bg: nil, bold: true },
            content: { color: :bright_yellow, bg: nil, bold: false,
                       underline: false, strikethrough: false },
          },
        },

        xml: {
          # Tags in bright cyan, attributes in hot magenta
          tag: { color: :bright_cyan, bg: nil, bold: true, italic: false },
          attribute_name: { color: :bright_magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :bright_green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :green, bg: nil, bold: false, italic: true },
          cdata: { color: :bright_yellow, bg: nil, bold: false, italic: false },
        },

        html: {
          tag: { color: :bright_cyan, bg: nil, bold: true, italic: false },
          attribute_name: { color: :bright_magenta, bg: nil, bold: false,
                            italic: false },
          attribute_value: { color: :bright_green, bg: nil, bold: false,
                             italic: false },
          text: { color: :default, bg: nil, bold: false, italic: false },
          comment: { color: :green, bg: nil, bold: false, italic: true },
          cdata: { color: :bright_yellow, bg: nil, bold: false, italic: false },
        },

        structure: {
          line_number: { color: :bright_cyan },
          pipe: { color: :bright_cyan },
          context: { color: :bright_white },
        },

        visualization: {
          space: "░",
          tab: "→",
          newline: "¶",
          nbsp: "␣",
        },

        display_mode: :separate,
      }.freeze

      # Registry of all themes
      THEMES = {
        light: LIGHT,
        dark: DARK,
        retro: RETRO,
        claude: CLAUDE,
        cyberpunk: CYBERPUNK,
      }.freeze

      # =====================================================================
      # Theme Inheritance Helper
      # =====================================================================

      # Create a new theme by inheriting from a base theme and merging overrides
      # @param base_name [Symbol] Name of base theme (:light, :dark, :retro, :claude)
      # @return [ThemeInheritance] Inheritance builder for chaining
      def self.inherit_from(base_name)
        ThemeInheritance.new(base_name)
      end

      # Theme inheritance builder
      class ThemeInheritance
        def initialize(base_name)
          unless THEMES.key?(base_name)
            raise ArgumentError,
                  "Unknown theme: #{base_name}. Valid: #{THEMES.keys}"
          end

          @base_name = base_name
          @overrides = {}
        end

        # Add overrides to the inherited theme
        # @param overrides [Hash] Nested hash of overrides
        # @return [self] for chaining
        def merge(overrides)
          deep_merge!(@overrides, overrides)
          self
        end

        # Build the final theme hash
        # @return [Hash] Merged theme
        def build
          base = deep_dup(THEMES[@base_name])
          deep_merge!(base, @overrides)
          base
        end

        # Shorthand for merge + build
        def merge!(overrides)
          merge(overrides)
          build
        end

        private

        # Delegate to module-level deep_dup
        def deep_dup(obj)
          Theme.deep_dup(obj)
        end

        def deep_merge!(target, source)
          source.each do |key, value|
            if value.is_a?(Hash) && target[key].is_a?(Hash)
              deep_merge!(target[key], value)
            else
              target[key] = deep_dup(value)
            end
          end
        end
      end

      # =====================================================================
      # Theme Validation
      # =====================================================================

      # Validation result
      ValidationResult = Struct.new(:valid, :missing_keys, :extra_keys,
                                    :invalid_values, keyword_init: true)

      # Validate a theme hash has all required keys and valid values
      # @param theme [Hash] Theme hash to validate
      # @return [ValidationResult]
      def self.validate(theme)
        missing_keys = []
        extra_keys = []
        invalid_values = []

        # Check top-level keys
        required_toplevel = %i[name description diff xml html structure
                               visualization display_mode]
        required_toplevel.each do |key|
          missing_keys << "top-level.#{key}" unless theme.key?(key)
        end

        # Validate diff section
        if theme[:diff]
          validate_diff_section(theme[:diff], missing_keys, extra_keys,
                                invalid_values)
        end

        # Validate xml section
        if theme[:xml]
          validate_xml_section(theme[:xml], missing_keys, extra_keys,
                               invalid_values)
        end

        # Validate html section
        if theme[:html]
          validate_xml_section(theme[:html], missing_keys, extra_keys,
                               invalid_values)
        end

        # Validate structure
        if theme[:structure]
          validate_structure_section(theme[:structure], missing_keys,
                                     extra_keys, invalid_values)
        end

        # Validate visualization
        if theme[:visualization]
          validate_visualization_section(theme[:visualization], missing_keys,
                                         extra_keys, invalid_values)
        end

        # Validate display_mode
        if theme[:display_mode]
          unless VALID_DISPLAY_MODES.include?(theme[:display_mode])
            invalid_values << "display_mode must be one of #{VALID_DISPLAY_MODES}, got #{theme[:display_mode]}"
          end
        else
          missing_keys << "display_mode"
        end

        ValidationResult.new(
          valid: missing_keys.empty? && extra_keys.empty? && invalid_values.empty?,
          missing_keys: missing_keys,
          extra_keys: extra_keys,
          invalid_values: invalid_values,
        )
      end

      # Validate all predefined themes
      # @return [Hash{Symbol => ValidationResult}]
      def self.validate_all
        THEMES.transform_values { |theme| validate(theme) }
      end

      # Get a theme by name
      # @param name [Symbol] Theme name
      # @return [Hash] Theme hash
      # @raise [ArgumentError] if theme not found
      # Deep copy a value, handling nested hashes and arrays
      def self.deep_dup(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        when String, Symbol, Numeric, TrueClass, FalseClass, NilClass
          obj
        else
          begin
            obj.dup
          rescue StandardError
            obj
          end
        end
      end

      def self.[](name)
        theme = THEMES[name] || raise(ArgumentError,
                                      "Unknown theme: #{name}. Valid: #{THEMES.keys}")
        # Return a deep copy to prevent mutation of theme constants
        deep_dup(theme)
      end

      # List available theme names
      # @return [Array<Symbol>]
      def self.names
        THEMES.keys
      end

      # Check if theme name exists
      # @param name [Symbol]
      # @return [Boolean]
      def self.include?(name)
        THEMES.key?(name)
      end

      # =====================================================================
      # Private: Section Validators
      # =====================================================================

      class << self
        private

        def validate_diff_section(diff, missing_keys, extra_keys,
invalid_values)
          required_types = %i[removed added changed unchanged formatting
                              informative]

          required_types.each do |type|
            unless diff.key?(type)
              missing_keys << "diff.#{type}"
              next
            end

            section = diff[type]
            validate_styling_section(section, "diff.#{type}", missing_keys,
                                     extra_keys, invalid_values)
          end

          # Check for extra keys
          extra = diff.keys - required_types
          extra_keys.concat(extra.map { |k| "diff.#{k}" }) unless extra.empty?
        end

        def validate_xml_section(xml, missing_keys, extra_keys, invalid_values)
          required_types = %i[tag attribute_name attribute_value text comment
                              cdata]

          required_types.each do |type|
            unless xml.key?(type)
              missing_keys << "xml.#{type}"
              next
            end

            section = xml[type]
            validate_styling_section(section, "xml.#{type}", missing_keys,
                                     extra_keys, invalid_values)
          end
        end

        def validate_styling_section(section, path, missing_keys, _extra_keys,
invalid_values)
          # Marker sections only need color, bg, bold
          marker_props = %i[color bg bold]

          if section.key?(:marker)
            validate_style_properties(section[:marker], "#{path}.marker",
                                      missing_keys, invalid_values, marker_props)
          end

          # Content sections need all styling properties except italic (not universally supported)
          content_props = %i[color bg bold underline strikethrough]

          if section.key?(:content)
            validate_style_properties(section[:content], "#{path}.content",
                                      missing_keys, invalid_values, content_props)
          end

          # changed section has content_old, content_new
          if section.key?(:content_old)
            validate_style_properties(section[:content_old],
                                      "#{path}.content_old", missing_keys, invalid_values, content_props)
          end

          if section.key?(:content_new)
            validate_style_properties(section[:content_new],
                                      "#{path}.content_new", missing_keys, invalid_values, content_props)
          end
        end

        # Required properties for structure elements (just color)
        STRUCTURE_PROPERTIES = %i[color].freeze

        def validate_structure_section(structure, missing_keys, _extra_keys,
invalid_values)
          required = %i[line_number pipe context]

          required.each do |key|
            unless structure.key?(key)
              missing_keys << "structure.#{key}"
              next
            end

            section = structure[key]
            validate_style_properties(section, "structure.#{key}",
                                      missing_keys, invalid_values, STRUCTURE_PROPERTIES)
          end
        end

        def validate_style_properties(style, path, missing_keys,
invalid_values, required_props = STYLING_PROPERTIES)
          unless style.is_a?(Hash)
            invalid_values << "#{path} must be a Hash, got #{style.class}"
            return
          end

          required_props.each do |prop|
            unless style.key?(prop)
              missing_keys << "#{path}.#{prop}"
            end
          end

          # Validate color (if present)
          if style.key?(:color) && !VALID_COLORS.include?(style[:color])
            invalid_values << "#{path}.color must be one of #{VALID_COLORS}, got #{style[:color]}"
          end

          # Validate bg
          if style.key?(:bg) && !style[:bg].nil? && !VALID_COLORS.include?(style[:bg])
            invalid_values << "#{path}.bg must be one of #{VALID_COLORS} or nil, got #{style[:bg]}"
          end

          # Validate booleans
          %i[bold underline strikethrough italic].each do |prop|
            next unless required_props.include?(prop)

            if style.key?(prop) && ![true, false].include?(style[prop])
              invalid_values << "#{path}.#{prop} must be true or false, got #{style[prop]}"
            end
          end
        end

        def validate_visualization_section(vis, missing_keys, _extra_keys,
_invalid_values)
          required = %i[space tab newline nbsp]

          required.each do |key|
            unless vis.key?(key)
              missing_keys << "visualization.#{key}"
            end
          end
        end
      end

      # =====================================================================
      # Theme Resolver - Resolves theme from Config + ENV
      # =====================================================================

      # Resolves the actual theme hash from configuration.
      # Priority:
      # 1. ENV['CANON_DIFF_THEME'] (highest)
      # 2. config.xml.diff.theme
      # 3. :dark default
      #
      # Also supports:
      # - Theme inheritance via config.xml.diff.theme_inheritance
      # - Custom theme via config.xml.diff.custom_theme
      class Resolver
        # Initialize with a config object (optional)
        # @param config [Canon::Config, nil]
        def initialize(config = nil)
          @config = config
        end

        # Resolve the theme hash to use for rendering
        # @return [Hash] Complete theme hash
        def resolve
          # Check ENV first
          env_theme = resolve_from_env
          return env_theme if env_theme

          # Check config theme_inheritance (custom theme with base + overrides)
          if @config.respond_to?(:xml) && @config.xml.diff.respond_to?(:theme_inheritance)
            inheritance = @config.xml.diff.theme_inheritance
            return resolve_inheritance_theme(inheritance) if inheritance
          end

          # Check config custom_theme (full custom theme hash)
          if @config.respond_to?(:xml) && @config.xml.diff.respond_to?(:custom_theme)
            custom = @config.xml.diff.custom_theme
            return custom if custom.is_a?(Hash) && !custom.empty?
          end

          # Check config theme name
          if @config.respond_to?(:xml) && @config.xml.diff.respond_to?(:theme)
            theme_name = @config.xml.diff.theme
            return Theme[theme_name] if Theme.include?(theme_name)
          end

          # Default to :dark
          Theme[:dark]
        end

        # Get theme by name from ENV or config
        # @return [Symbol] Theme name
        def theme_name
          # ENV takes precedence
          env_name = ENV["CANON_DIFF_THEME"]&.to_sym
          return env_name if env_name && Theme.include?(env_name)

          # Check config
          if @config.respond_to?(:xml) && @config.xml.diff.respond_to?(:theme)
            theme_name = @config.xml.diff.theme
            return theme_name if Theme.include?(theme_name)
          end

          # Default
          :dark
        end

        private

        def resolve_from_env
          env_theme_name = ENV["CANON_DIFF_THEME"]&.to_sym
          return nil unless env_theme_name
          return nil unless Theme.include?(env_theme_name)

          Theme[env_theme_name]
        end

        def resolve_inheritance_theme(inheritance)
          base_name = inheritance[:base]
          overrides = inheritance[:overrides] || {}

          return Theme[base_name] if overrides.empty?

          Theme.inherit_from(base_name).merge(overrides).build
        end
      end

      # Singleton instance for convenience
      def self.resolver(config = nil)
        Resolver.new(config)
      end
    end
  end
end
