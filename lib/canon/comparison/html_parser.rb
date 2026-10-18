# frozen_string_literal: true

module Canon
  module Comparison
    # HTML parsing service with version detection and fragment support
    #
    # Provides HTML parsing capabilities with automatic HTML4/HTML5 version
    # detection. Handles both full documents and fragments.
    #
    # @example Parse HTML string
    #   HtmlParser.parse("<div>content</div>", :html5)
    #
    # @example Auto-detect and parse
    #   HtmlParser.detect_and_parse("<!DOCTYPE html><html>...</html>")
    class HtmlParser
      class << self
        # Parse HTML string into the comparison tree.
        #
        # The engine lane (moxml Context#parse_html_fragment, moxml#353
        # riding leptris' WHATWG fragment parsing) builds a Canon tree
        # through the same TreeBuilder walk the XML lane uses: same
        # tree construction as Nokogiri::HTML5.fragment (the #118
        # html4/html5 unification semantics), native named-entity
        # decoding, and a ~5x faster parse. The Nokogiri fragment
        # path remains for runtimes without the engine surface.
        #
        # @param content [String, Object] Content to parse (returns as-is if not a string)
        # @param format [Symbol] HTML format (:html, :html4, :html5)
        # @return [Canon::Xml::Nodes::RootNode, Object] Canon tree or content
        def parse(content, format)
          return content unless content.is_a?(String)

          # Normalize HTML to ensure consistent parsing by HTML4.fragment
          # The key issue is that HTML4.fragment treats newlines after </head>
          # differently than no newlines, causing inconsistent parsing
          content = normalize_html_for_parsing(content)

          return engine_fragment(content) if engine_html_fragments?

          # Nokogiri fallback lane (runtimes without the engine HTML
          # surface): Nokogiri is required lazily, at use — the engine
          # lane above keeps HTML comparison nokogiri-less.
          Canon::NokogiriLoader.require!("the HTML fallback lane")

          begin
            case format
            when :html5
              Nokogiri::HTML5.fragment(content)
            when :html4
              Nokogiri::HTML4.fragment(content)
            when :html
              detect_and_parse(content)
            else
              content
            end
          rescue StandardError
            # Fallback to raw string if parsing fails (maintains backward compatibility)
            content
          end
        end

        # Parse an HTML string through the engine's WHATWG fragment
        # parsing and build a Canon tree. Canon::Html::DataModel owns
        # the conversion (the single home for HTML→Canon-tree building).
        def engine_fragment(html)
          Canon::Html::DataModel.engine_fragment(html)
        end

        # Engine HTML fragments are served by adapters with an engine
        # HTML mode (leptris, nokogiri) — moxml#353 pins WHATWG tree
        # construction on both.
        def engine_html_fragments?
          %i[leptris nokogiri].include?(Canon::XmlParsing.moxml_adapter_name)
        end

        # Check if content is already a parsed HTML document/fragment
        #
        # @param content [Object] Content to check
        # @return [Boolean] true if already parsed
        def already_parsed?(content)
          content.is_a?(Nokogiri::HTML::Document) ||
            content.is_a?(Nokogiri::HTML5::Document) ||
            content.is_a?(Nokogiri::HTML::DocumentFragment) ||
            content.is_a?(Nokogiri::HTML5::DocumentFragment)
        end

        # Detect HTML version from content and parse with appropriate parser
        #
        # @param content [String] HTML content to parse
        # @return [Nokogiri::HTML::DocumentFragment] Parsed fragment
        def detect_and_parse(content)
          version = detect_version(content)
          if version == :html5
            Nokogiri::HTML5.fragment(content)
          else
            Nokogiri::HTML4.fragment(content)
          end
        end

        # Detect HTML version from content string
        #
        # @param content [String] HTML content
        # @return [Symbol] :html5 or :html4
        def detect_version(content)
          # Check for HTML5 DOCTYPE (case-insensitive)
          content.include?("<!DOCTYPE html>") ? :html5 : :html4
        end

        # Normalize HTML to ensure consistent parsing by HTML4.fragment
        #
        # The key issue is that HTML4.fragment treats whitespace after </head>
        # differently than no whitespace, causing inconsistent parsing:
        # - "</head>\n<body>" parses to [body, ...] (body is treated as content)
        # - "</head><body>" parses to [meta, div, ...] (wrapper tags stripped)
        #
        # This method normalizes the HTML to ensure consistent parsing.
        #
        # @param content [String] HTML content
        # @return [String] Normalized HTML content
        def normalize_html_for_parsing(content)
          # Remove whitespace between </head> and <body> to ensure consistent parsing
          # This makes formatted and minified HTML parse the same way
          content.gsub(%r{</head>\s*<body>}i, "</head><body>")
        end
      end
    end
  end
end
