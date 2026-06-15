# frozen_string_literal: true

module Canon
  module Comparison
    # Shared comparison pipeline helpers used by both algorithms.
    #
    # Both `dom_diff` and `semantic_diff` need to:
    # - detect document format from inputs (with optional hint)
    # - validate that the two formats are comparable
    # - merge global config-sourced profile / options into the opts hash
    # - capture original-string snapshots before parsing mutates inputs
    # - parse both inputs through the format-specific comparator
    #
    # These steps are pure pipeline mechanics — they have nothing to do with
    # the comparison algorithm itself.  Keeping them here ensures the two
    # algorithm entrypoints cannot drift out of sync (see lutaml/canon
    # "Two Comparison Algorithms — Distinct by Design" in CLAUDE.md —
    # the algorithm cores stay separate; only shared infrastructure is
    # consolidated).
    module Pipeline
      # Formats whose Canon::Config exposes a match profile / options.
      CONFIG_BACKED_FORMATS = %i[xml html json yaml string].freeze

      # Cross-format compatibility groups.  DOM comparison accepts these
      # pairings because both sides parse to the same Ruby structure.
      # Semantic comparison does not — it requires exact format match.
      COMPATIBLE_FORMAT_GROUPS = [
        %i[json ruby_object].freeze,
        %i[yaml ruby_object].freeze,
      ].freeze

      class << self
        # Detect formats for both inputs, honouring an explicit hint.
        #
        # @param obj1 [Object] First input
        # @param obj2 [Object] Second input
        # @param format_hint [Symbol, nil] Explicit format override
        # @return [Array<Symbol, Symbol>] Detected or hinted formats
        def detect_formats(obj1, obj2, format_hint)
          return [format_hint, format_hint] if format_hint

          [FormatDetector.detect(obj1), FormatDetector.detect(obj2)]
        end

        # True when the two formats can be compared by the DOM algorithm.
        #
        # DOM allows `ruby_object` to be compared against `json` or `yaml`
        # because both sides parse to the same Ruby structure.  Semantic
        # comparison does not allow this — it requires exact format match.
        #
        # @param format1 [Symbol]
        # @param format2 [Symbol]
        # @param strict [Boolean] When true, require exact match (semantic)
        # @return [Boolean]
        def formats_compatible?(format1, format2, strict: false)
          return true if format1 == format2
          return false if strict

          COMPATIBLE_FORMAT_GROUPS.any? do |group|
            group.include?(format1) && group.include?(format2)
          end
        end

        # Raise a helpful error if formats are incompatible.
        #
        # @param format1 [Symbol]
        # @param format2 [Symbol]
        # @param strict [Boolean] Passed to {formats_compatible?}
        # @raise [Canon::CompareFormatMismatchError]
        # @return [void]
        def validate_compatible!(format1, format2, strict: false)
          return if formats_compatible?(format1, format2, strict: strict)

          raise Canon::CompareFormatMismatchError.new(format1, format2)
        end

        # Merge global config-sourced profile and options into `opts`.
        #
        # Reads `Canon::Config.instance.<format>.match` for a global
        # `profile` and `profile_options`, and merges them into a copy of
        # the supplied opts hash.  Caller-supplied values always win:
        # config-derived `profile_options` extend rather than replace
        # caller-supplied `global_options`.
        #
        # Returns the original opts hash unchanged when the format is not
        # config-backed (e.g. `:ruby_object`).
        #
        # @param format [Symbol]
        # @param opts [Hash] Caller opts (will not be mutated)
        # @return [Hash] New opts hash with config globals merged in
        def resolve_config(format, opts)
          return opts unless CONFIG_BACKED_FORMATS.include?(format)

          format_config = Canon::Config.instance.public_send(format)
          match_config = format_config.match
          profile = match_config.profile
          profile_opts = match_config.profile_options

          resolved = opts.dup
          if resolved[:global_profile].nil? && profile
            resolved[:global_profile] = profile
          end

          if profile_opts.any?
            resolved[:global_options] = merge_profile_options(
              resolved[:global_options], profile_opts
            )
          end

          resolved
        end

        # Capture pre-parse string snapshots for diff display.
        #
        # Parsing (especially HTML) can mutate inputs, so originals must
        # be captured before any parsing happens.  Strings pass through
        # unchanged; parsed nodes are serialized via NodeSerializer.
        #
        # @param obj1 [Object]
        # @param obj2 [Object]
        # @return [Array<String, String>] Captured original strings
        def capture_originals(obj1, obj2)
          [extract_original_string(obj1), extract_original_string(obj2)]
        end

        # Parse both inputs through the format-specific comparator.
        #
        # Delegates to `XmlComparator`, `HtmlComparator`, `JsonComparator`,
        # or `YamlComparator` based on format.  Uses `Cache` so the same
        # string is not re-parsed across runs.
        #
        # @param obj1 [Object]
        # @param obj2 [Object]
        # @param format [Symbol]
        # @param match_opts_hash [Hash] Resolved match options
        # @return [Array<Object, Object>] Parsed documents
        def parse_pair(obj1, obj2, format, match_opts_hash)
          preprocessing = match_opts_hash[:preprocessing] || :none

          case format
          when :xml
            [
              parse_with_cache(obj1, format, preprocessing) do |doc|
                XmlComparator.parse(doc, preprocessing)
              end,
              parse_with_cache(obj2, format, preprocessing) do |doc|
                XmlComparator.parse(doc, preprocessing)
              end,
            ]
          when :html, :html4, :html5
            [
              parse_with_cache(obj1, format, preprocessing) do |doc|
                HtmlComparator.parse(doc, preprocessing)
              end,
              parse_with_cache(obj2, format, preprocessing) do |doc|
                HtmlComparator.parse(doc, preprocessing)
              end,
            ]
          when :json
            [
              parse_with_cache(obj1, format, :none) do |doc|
                JsonComparator.parse(doc)
              end,
              parse_with_cache(obj2, format, :none) do |doc|
                JsonComparator.parse(doc)
              end,
            ]
          when :yaml
            [
              parse_with_cache(obj1, format, :none) do |doc|
                YamlComparator.parse(doc)
              end,
              parse_with_cache(obj2, format, :none) do |doc|
                YamlComparator.parse(doc)
              end,
            ]
          else
            [obj1, obj2]
          end
        end

        # Pre-parse HTML strings through `HtmlParser.parse(_, :html5)`.
        #
        # The DOM comparator needs HTML4 and HTML5 inputs to share HTML's
        # whitespace-sensitivity semantics, which means routing both
        # through Nokogiri::HTML5.fragment up front (issue #118).
        # The semantic comparator does not need this — it uses Canon's
        # own HTML data model downstream — so this helper is opt-in.
        #
        # Returns the inputs unchanged if they are not strings.
        #
        # @param obj1 [Object]
        # @param obj2 [Object]
        # @return [Array<Object, Object>] Potentially pre-parsed HTML inputs
        def preparse_html_pair(obj1, obj2)
          [
            html_string?(obj1) ? HtmlParser.parse(obj1, :html5) : obj1,
            html_string?(obj2) ? HtmlParser.parse(obj2, :html5) : obj2,
          ]
        end

        # True when the input is a String AND should be treated as HTML.
        #
        # @param obj [Object]
        # @return [Boolean]
        def html_string?(obj)
          obj.is_a?(String)
        end

        private

        # Merge caller-supplied global_options with config profile_opts.
        #
        # Caller values win on key conflict; profile_opts fill in gaps.
        # `MatchConfig#profile_options` already returns a fresh hash
        # (via `Hash#except`), so we can return it directly without dup.
        #
        # @param existing [Hash, nil] Caller-supplied options
        # @param profile_opts [Hash] Config-sourced options
        # @return [Hash] Merged hash
        def merge_profile_options(existing, profile_opts)
          return profile_opts if existing.nil?

          profile_opts.merge(existing)
        end

        # Parse a single document with cache lookup.
        #
        # @param doc [Object] Document (string or already-parsed)
        # @param format [Symbol] Document format
        # @param preprocessing [Symbol] Preprocessing option
        # @yield Block to parse the document if not cached
        # @return [Object] Parsed document
        def parse_with_cache(doc, format, preprocessing)
          return doc unless doc.is_a?(String)

          Cache.fetch(:document_parse,
                      Cache.key_for_document(doc, format, preprocessing)) do # rubocop:disable Lint/UselessDefaultValueArgument
            yield doc
          end
        end

        # Extract a string snapshot from various input types.
        #
        # Strings pass through; Nokogiri documents use to_html; Canon and
        # other XML nodes go through NodeSerializer; everything else
        # falls back to to_s.
        #
        # @param obj [Object]
        # @return [String] String snapshot
        def extract_original_string(obj)
          case obj
          when String
            obj
          when Nokogiri::XML::Document, Nokogiri::HTML::Document,
               Nokogiri::XML::DocumentFragment, Nokogiri::HTML::DocumentFragment
            obj.to_html
          else
            if Canon::XmlParsing.xml_node?(obj) || obj.is_a?(Canon::Xml::Node)
              Canon::XmlParsing.serialize(obj)
            else
              obj.to_s
            end
          end
        end
      end
    end
  end
end
