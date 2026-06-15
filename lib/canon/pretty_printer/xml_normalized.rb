# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"

module Canon
  module PrettyPrinter
    # Mixed-content-aware XML serializer for diff display preprocessing.
    #
    # == The mixed-content problem
    #
    # Standard XML pretty-printers (including Nokogiri's built-in serializer)
    # keep elements that contain both text and child elements on a single line.
    # They have no choice: inserting a newline between, say, `<p>See ` and
    # `<xref.../>` would create a new whitespace text node, changing the
    # document's semantic content.  The result for line-by-line diffs is that
    # any change inside such an element forces the entire line — potentially
    # hundreds or thousands of characters — to be marked as changed.  Issue #53
    # documented this as "1000-character long lines" from HTML diffs.
    #
    # == Three-way whitespace classification
    #
    # This serializer distinguishes three categories of element-level whitespace
    # behaviour, configured via element-name lists:
    #
    # * **Preserve** (`preserve_whitespace_elements`) — every whitespace character is
    #   significant. `" "` ≠ `"\n"`. Typical: `<pre>`, `<code>`, `<textarea>`.
    #   Whitespace-only text nodes are visualized character-by-character.
    #
    # * **Collapse** (`collapse_whitespace_elements`) — presence ≠ absence,
    #   but all whitespace forms are equivalent: `" "` == `"\n  "` == `"\t"`.
    #   Typical: `<p>`, `<li>`, `<td>`, heading elements.
    #   Whitespace-only text nodes are collapsed to a single `░` visualization,
    #   so `<p>\n  <em>` (indented fixture) and `<p> <em>` (compact source)
    #   both render as `<p>░<em>` — identical display lines, no spurious diff.
    #
    # * **Strip** (everything else, or explicit `strip_whitespace_elements`) —
    #   all whitespace between child elements is structural formatting noise.
    #   `" "` == `"\n  "` == nothing. Whitespace-only text nodes are silently
    #   dropped. Typical: `<section>`, `<ul>`, `<formattedref>`, `<bibitem>`.
    #
    # Classification is **ancestor-based**: a text node's class is determined
    # by the closest matching ancestor. This means `<em>` inside `<p>` inherits
    # `<p>`'s normalize behaviour without needing to be listed explicitly.
    #
    # == Format defaults
    #
    # * **XML**: all three lists are empty by default — insensitive everywhere.
    #   Whitespace sensitivity is opt-in, consistent with XML's data-first usage.
    #
    # * **HTML**: built-in defaults are provided (but overridable):
    #   - preserve: `pre`, `code`, `textarea`, `script`, `style`
    #   - collapse: `p`, `li`, `dt`, `dd`, `td`, `th`, `h1`–`h6`, `caption`,
    #     `figcaption`, `label`, `legend`, `summary`, `blockquote`, `address`
    #
    # == Structural vs. content whitespace
    #
    # * **Structural whitespace** — indentation characters emitted by the
    #   serializer itself.  These do not exist in the source document.
    #   They are rendered as ordinary ASCII space and newline characters.
    # * **Content whitespace** — whitespace that exists as text-node content
    #   in the source document.  Classification (above) decides how to render it.
    #
    # The invariant is: every XML element always starts on its own line.
    # Content whitespace is never confused with structural indentation.
    #
    # == Example (normalize element <p>)
    #
    # Input — compact source (Metanorma-style):
    #   <p>See <xref target="M"/></p>
    #
    # Input — indented fixture heredoc:
    #   <p>
    #     See
    #     <xref target="M"/>
    #   </p>
    #
    # Both serialize to:
    #   <p>
    #     See░
    #     <xref target="M"/>
    #   </p>
    #
    # Result: zero diff lines for a semantically identical document.
    #
    # == Example (insensitive element <formattedref>)
    #
    # Input — compact source:
    #   <formattedref><em>Cereals</em>.</formattedref>
    #
    # Input — indented fixture:
    #   <formattedref>
    #     <em>Cereals</em>.
    #   </formattedref>
    #
    # Both serialize to (whitespace-only nodes silently dropped):
    #   <formattedref>
    #     <em>Cereals</em>
    #     .
    #   </formattedref>
    #
    # Result: zero diff lines.
    #
    # == Usage
    #
    #   printer = Canon::PrettyPrinter::XmlNormalized.new
    #   formatted = printer.format(xml_string)
    #
    #   # With element lists (XML):
    #   printer = Canon::PrettyPrinter::XmlNormalized.new(
    #     collapse_whitespace_elements: %w[p formattedref title],
    #     preserve_whitespace_elements: %w[sourcecode pre],
    #   )
    #
    class XmlNormalized
      # @param indent [Integer] number of indent characters per level (default 2)
      # @param indent_type [String] "space" or "tab"
      # @param visualization_map [Hash, nil] character visualization map
      # @param preserve_whitespace_elements [Array<String>] element names where
      #   every whitespace character is significant (e.g. pre, code).
      # @param collapse_whitespace_elements [Array<String>] element names where
      #   presence of whitespace matters but all forms are equivalent (e.g. p, li).
      # @param strip_whitespace_elements [Array<String>] explicit blacklist — these
      #   elements and their children always have whitespace dropped, even if an
      #   ancestor would otherwise be preserve or collapse.
      # @param pretty_printed [Boolean] when true, whitespace-only text nodes
      #   that begin with "\n" inside +:collapse+ elements are treated as
      #   structural indentation and silently dropped.  This matches the
      #   comparison-side behaviour activated by +pretty_printed_expected+ /
      #   +pretty_printed_received+ match options.  Nodes under +:preserve+ elements
      #   are always preserved; nodes under +:strip+ elements are already dropped.
      def initialize(indent: 2, indent_type: "space", visualization_map: nil,
                     preserve_whitespace_elements: [],
                     collapse_whitespace_elements: [],
                     strip_whitespace_elements: [],
                     pretty_printed: false,
                     sort_attributes: false,
                     html_mode: false)
        @indent = indent.to_i
        @indent_char = indent_type == "tab" ? "\t" : " "
        @vis_map = visualization_map || default_vis_map
        @pretty_printed = pretty_printed
        @sort_attributes = sort_attributes
        @html_mode = html_mode

        @strict_ws  = Set.new((preserve_whitespace_elements || []).map(&:to_s))
        @norm_ws    = Set.new((collapse_whitespace_elements || []).map(&:to_s))
        @insens_ws  = Set.new((strip_whitespace_elements || []).map(&:to_s))
      end

      # Format an XML string with mixed-content-aware serialization.
      #
      # @param xml_string [String] Input XML
      # @return [String] Serialized XML, one node per line, with content
      #   whitespace visualized at line boundaries
      def format(xml_string)
        doc = if Canon::XmlBackend.moxml?
                Canon::XmlParsing.parse(xml_string)
              elsif @html_mode
                Nokogiri::HTML5(xml_string)
              else
                Nokogiri::XML(xml_string)
              end
        lines = []

        if !@html_mode && doc.version
          enc = doc.encoding ? " encoding=\"#{doc.encoding}\"" : ""
          lines << "<?xml version=\"#{doc.version}\"#{enc}?>"
        end

        lines << serialize_element(doc.root, 0) if doc.root
        lines.join("\n")
      end

      private

      # Return indent string for depth.
      def ind(depth)
        @indent_char * (@indent * depth)
      end

      # Classify the whitespace behaviour for a given Nokogiri element node.
      #
      # Walks up the ancestor chain from the element itself.  The first
      # matching ancestor determines the class.  Insensitive blacklist wins
      # over any sensitive ancestor.
      #
      # @param element [Nokogiri::XML::Element] The element to classify
      # @return [Symbol] :strict, :normalize, or :drop
      def classify_whitespace(element)
        current = element
        while current && !Canon::XmlParsing.document?(current)
          name = current.name.to_s
          return :drop      if @insens_ws.include?(name)
          return :strict    if @strict_ws.include?(name)
          return :normalize if @norm_ws.include?(name)

          current = current.parent
        end
        # No matching ancestor — default: drop (insensitive)
        :drop
      end

      # Serialize a single element node.
      def serialize_element(node, depth)
        # Filter out empty text nodes (zero-length, not whitespace-only).
        children = node.children.reject { |c| c.text? && c.content.empty? }

        if children.empty?
          if @html_mode && !HtmlVoidElements.void?(node.name)
            return "#{ind(depth)}#{open_tag(node)}</#{node.name}>"
          end

          return "#{ind(depth)}#{open_tag(node,
                                          self_close: true)}"
        end

        elem_children = children.select(&:element?)
        text_with_content = children.select do |c|
          c.text? && !c.content.strip.empty?
        end

        if elem_children.empty?
          # Pure-text element — keep on one line.
          return "#{ind(depth)}#{open_tag(node)}#{node.text}</#{node.name}>"
        end

        if text_with_content.empty?
          # Element-only children (may have whitespace-only text nodes between them).
          # Apply classification to decide whether to drop or visualize them.
          ws_class = classify_whitespace(node)
          lines = ["#{ind(depth)}#{open_tag(node)}"]
          children.each do |child|
            if child.text?
              # Whitespace-only text node between element children
              vis = render_whitespace_only(child.content, ws_class)
              next if vis.nil? # :drop

              # Append to previous line (do not create a new line)
              lines[-1] = lines[-1] + vis
            else
              lines << serialize_element(child, depth + 1)
            end
          end
          lines << "#{ind(depth)}</#{node.name}>"
          return lines.join("\n")
        end

        # Mixed content: both text-with-content and element children.
        serialize_mixed(node, children, depth)
      end

      # Serialize a mixed-content element.
      #
      # Each child is processed in document order.  Text nodes are split into:
      # * leading whitespace  → rendered according to whitespace classification
      # * non-whitespace content → put on its OWN indented line
      # * trailing whitespace → rendered according to classification, appended
      #
      # Element children flush the current accumulated line, then are
      # serialized recursively.
      def serialize_mixed(node, children, depth)
        child_depth = depth + 1
        lines = []
        current_line = "#{ind(depth)}#{open_tag(node)}"
        ws_class = classify_whitespace(node)

        children.each do |child|
          if child.text?
            process_text_node(child.content, child_depth, lines, current_line,
                              ws_class) do |nl|
              current_line = nl
            end
          else
            lines << current_line
            current_line = serialize_element(child, child_depth)
          end
        end

        lines << current_line
        lines << "#{ind(depth)}</#{node.name}>"
        lines.join("\n")
      end

      # Render a whitespace-only string according to classification.
      #
      # When +@pretty_printed+ is true and +ws_class+ is +:normalize+:
      # * Content starting with "\n" (e.g. "\n  " indentation) is treated as
      #   structural pretty-print formatting and **dropped** (returns nil).
      # * All other whitespace (e.g. " " inline space) is still rendered as the
      #   usual single-space visualization.
      # This aligns display output with the comparison-side behaviour controlled
      # by +pretty_printed_expected+ / +pretty_printed_received+.
      #
      # @param content [String] Whitespace-only string
      # @param ws_class [Symbol] :strict, :normalize, or :drop
      # @return [String, nil] Rendered string, or nil to indicate "drop"
      def render_whitespace_only(content, ws_class)
        case ws_class
        when :strict
          visualize(content)
        when :normalize
          # In pretty_printed mode, \n-leading whitespace is structural — drop it
          return nil if @pretty_printed && content.start_with?("\n")

          # Any other whitespace → single space visualization
          content.empty? ? nil : @vis_map.fetch(" ", "░")
          # :drop — fall through to nil
        end
      end

      # Process a text node in mixed-content context.
      #
      # Yields the new current_line (string the caller should adopt).
      #
      # === Pure-whitespace text nodes
      #
      # Whitespace-only text nodes are rendered via +render_whitespace_only+
      # according to the element's whitespace classification:
      # - :strict   → visualize every character (e.g. ↵░░░)
      # - :normalize → single ░ regardless of whitespace form
      # - :drop     → silently discarded
      #
      # === Text nodes with printable content
      #
      # Leading and trailing whitespace are split off and rendered according
      # to the whitespace classification at line boundaries.  The printable
      # content occupies its own indented line.
      def process_text_node(content, child_depth, lines, current_line, ws_class)
        stripped = content.strip

        if stripped.empty?
          # Pure whitespace between elements
          vis = render_whitespace_only(content, ws_class)
          if vis.nil?
            yield current_line # :drop — no change
          else
            yield current_line + vis
          end
          return
        end

        leading  = content[/\A\s*/]
        trailing = content[/\s*\z/]
        middle   = stripped

        # Leading whitespace: append to current line (then flush), or drop
        unless leading.empty?
          vis = render_whitespace_only(leading, ws_class)
          current_line += vis unless vis.nil?
        end
        lines << current_line

        # Trailing whitespace visualization
        trailing_vis = if trailing.empty?
                         ""
                       else
                         v = render_whitespace_only(trailing, ws_class)
                         v.nil? ? "" : v
                       end
        yield "#{ind(child_depth)}#{middle}#{trailing_vis}"
      end

      # Build an opening XML tag with namespace declarations and attributes.
      def open_tag(node, self_close: false)
        ns_decls = node.namespace_definitions.map do |ns|
          ns.prefix ? " xmlns:#{ns.prefix}=\"#{ns.href}\"" : " xmlns=\"#{ns.href}\""
        end.join

        attr_nodes = node.attribute_nodes
        if @sort_attributes
          attr_nodes = attr_nodes.sort_by do |a|
            [a.namespace&.href.to_s, a.name]
          end
        end

        attrs = attr_nodes.map do |a|
          prefix = a.namespace&.prefix ? "#{a.namespace.prefix}:" : ""
          " #{prefix}#{a.name}=\"#{escape_attr(a.value)}\""
        end.join

        close = self_close ? "/>" : ">"
        "<#{node.name}#{ns_decls}#{attrs}#{close}"
      end

      # Escape characters that are special inside attribute values.
      def escape_attr(value)
        value.gsub("&", "&amp;").gsub('"', "&quot;").gsub("<", "&lt;")
      end

      # Visualize a whitespace string using the character map.
      # Non-whitespace characters are passed through unchanged (safety net).
      def visualize(str)
        return "" if str.nil? || str.empty?

        str.chars.map { |c| @vis_map.fetch(c, c) }.join
      end

      # Load the default visualization map from DiffFormatter constants.
      def default_vis_map
        Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP
      rescue LoadError, NameError
        { " " => "░", "\t" => "⇥", "\n" => "↵", "\r" => "⏎", "\u00A0" => "␣" }
      end
    end
  end
end
