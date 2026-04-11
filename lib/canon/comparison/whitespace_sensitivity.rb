# frozen_string_literal: true

module Canon
  module Comparison
    # Whitespace sensitivity utilities for element-level control
    #
    # This module provides three-way classification of whitespace behaviour
    # at the element level:
    #
    # * **:preserve** — every whitespace character is significant. `" "` ≠ `"\n"`.
    #   Configured via +preserve_whitespace_elements+ (HTML default: pre, code,
    #   textarea, script, style; XML default: none).
    #
    # * **:collapse** — presence ≠ absence, but all whitespace forms are
    #   equivalent: `" "` == `"\n  "`. Configured via +collapse_whitespace_elements+
    #   (HTML default: p, li, dt, dd, td, th, h1-h6, caption, figcaption, label,
    #   legend, summary, blockquote, address; XML default: none).
    #
    # * **:strip** — all whitespace is structural formatting noise and is
    #   dropped. Default for XML; HTML elements not in the above lists.
    #
    # Classification is **ancestor-based**: the closest matching ancestor
    # determines the class. The strip blacklist (+strip_whitespace_elements+)
    # overrides any sensitive ancestor.
    #
    # == Priority Order
    #
    # 1. respect_xml_space: false → User config only (ignore xml:space)
    # 2. Ancestor walk (strip blacklist wins; then preserve; then collapse)
    # 3. xml:space="preserve" → preserve
    # 4. xml:space="default" → use configured behaviour
    # 5. Format defaults (HTML: collapse for most elements; XML: strip)
    #
    # == Usage
    #
    #   WhitespaceSensitivity.classify_element(element, match_opts)
    #   => :preserve, :collapse, or :strip
    #
    #   WhitespaceSensitivity.element_sensitive?(node, opts)
    #   => true if whitespace should be preserved (preserve or collapse)
    module WhitespaceSensitivity
      # HTML mixed-content "leaf block" elements where whitespace presence
      # matters but all forms are equivalent (CSS block whitespace collapsing).
      HTML_COLLAPSE_ELEMENTS = %w[
        p li dt dd td th caption figcaption label legend summary
        h1 h2 h3 h4 h5 h6
        blockquote address button
      ].freeze

      # HTML elements where every whitespace character is significant.
      HTML_PRESERVE_ELEMENTS = %w[pre code textarea script style].freeze

      class << self
        # Classify the whitespace behaviour for an element using ancestor walk.
        #
        # @param element [Object] The element node to classify
        # @param match_opts [Hash] Resolved match options
        # @return [Symbol] :preserve, :collapse, or :strip
        def classify_element(element, match_opts)
          return :strip unless element
          return :strip unless element.respond_to?(:name)

          preserve_set  = resolved_preserve_elements_set(match_opts)
          collapse_set  = resolved_collapse_elements_set(match_opts)
          strip_set = resolved_strip_elements_set(match_opts)

          # Ancestor walk: start at the element itself, walk up.
          # Strip blacklist wins over any sensitive ancestor.
          walk_ancestor_classification(element, preserve_set, collapse_set,
                                       strip_set, match_opts)
        end

        # Check if an element is whitespace-sensitive based on configuration.
        # Returns true for :preserve or :collapse classification.
        #
        # @param node [Object] The element node to check
        # @param opts [Hash] Comparison options containing match_opts
        # @return [Boolean] true if whitespace should be preserved for this element
        def element_sensitive?(node, opts)
          match_opts = opts[:match_opts]
          return false unless match_opts
          return false unless text_node_parent?(node)

          parent = node.parent

          # 1. Check if we should ignore xml:space (user override)
          unless respect_xml_space?(match_opts)
            return user_config_sensitive?(parent, match_opts)
          end

          # 2. Check xml:space="preserve" (document declaration)
          return true if xml_space_preserve?(parent)

          # 3. Check xml:space="default" (use configured behavior)
          return false if xml_space_default?(parent)

          # 4. Three-way classification (ancestor-based)
          classification = classify_element(parent, match_opts)
          %i[preserve collapse].include?(classification)
        end

        # Check if whitespace-only text node should be filtered
        #
        # @param node [Object] The text node to check
        # @param opts [Hash] Comparison options
        # @return [Boolean] true if node should be preserved (not filtered)
        def preserve_whitespace_node?(node, opts)
          return false unless node.respond_to?(:parent)
          return false unless node.parent

          element_sensitive?(node, opts)
        end

        # Return the whitespace class for a text node used during comparison.
        #
        # :preserve   → preserve all whitespace character-by-character
        # :collapse   → preserve presence (normalize to single space)
        # :strip      → drop whitespace-only text nodes
        #
        # @param node [Object] Text node to classify
        # @param opts [Hash] Comparison options containing match_opts
        # @return [Symbol] :preserve, :collapse, or :strip
        def classify_text_node(node, opts)
          match_opts = opts[:match_opts]
          return :strip unless match_opts
          return :strip unless text_node_parent?(node)

          parent = node.parent

          unless respect_xml_space?(match_opts)
            return user_config_sensitive?(parent, match_opts) ? :preserve : :strip
          end

          return :preserve if xml_space_preserve?(parent)
          return :strip if xml_space_default?(parent)

          classify_element(parent, match_opts)
        end

        # Check if structural whitespace is preserved (not stripped) for an element.
        #
        # Uses the same priority chain as element_sensitive? / classify_text_node:
        #   1. xml:space="preserve" → always preserved
        #   2. xml:space="default"  → use configured behaviour
        #   3. ancestor-walk classification (strip = dropped)
        #
        # @param element [Object] Element node to check
        # @param match_opts [Hash] Resolved match options
        # @return [Boolean] true if whitespace is preserved (not stripped)
        def whitespace_preserved?(element, match_opts)
          if respect_xml_space?(match_opts)
            return true  if xml_space_preserve?(element)
            return false if xml_space_default?(element)
          end

          classification = classify_element(element, match_opts)
          %i[preserve collapse].include?(classification)
        end

        # Get resolved list of preserve whitespace element names (strings).
        #
        # @param match_opts [Hash] Resolved match options
        # @return [Array<String>] Preserve element names
        def resolved_preserve_elements(match_opts)
          resolved_preserve_elements_set(match_opts).to_a
        end

        # Get resolved list of collapse whitespace element names (strings).
        #
        # @param match_opts [Hash] Resolved match options
        # @return [Array<String>] Collapse element names
        def resolved_collapse_elements(match_opts)
          resolved_collapse_elements_set(match_opts).to_a
        end

        # Get format-specific default preserve (exact-whitespace) elements.
        # This is the SINGLE SOURCE OF TRUTH for default preserve-whitespace elements.
        #
        # @param match_opts [Hash] Resolved match options
        # @return [Array<Symbol>] Default preserve element names
        def format_default_preserve_elements(match_opts)
          format = match_opts[:format] || :xml
          case format
          when :html, :html4, :html5
            HTML_PRESERVE_ELEMENTS.map(&:to_sym).freeze
          else
            [].freeze
          end
        end

        # Get format-specific default collapse elements.
        #
        # @param match_opts [Hash] Resolved match options
        # @return [Array<Symbol>] Default collapse element names
        def format_default_collapse_elements(match_opts)
          format = match_opts[:format] || :xml
          case format
          when :html, :html4, :html5
            HTML_COLLAPSE_ELEMENTS.map(&:to_sym).freeze
          else
            [].freeze
          end
        end

        # Check if an element is in the default sensitive list for its format
        #
        # @param element_name [String, Symbol] The element name to check
        # @param match_opts [Hash] Resolved match options
        # @return [Boolean] true if element is in default sensitive list
        def default_sensitive_element?(element_name, match_opts)
          format_default_preserve_elements(match_opts)
            .include?(element_name.to_sym)
        end

        private

        # Build the Set of preserve whitespace element names (strings).
        def resolved_preserve_elements_set(match_opts)
          set = Set.new(format_default_preserve_elements(match_opts).map(&:to_s))

          if match_opts[:preserve_whitespace_elements]
            set |= match_opts[:preserve_whitespace_elements].map(&:to_s)
          end

          # Remove blacklisted elements
          strip_set = resolved_strip_elements_set(match_opts)
          set.reject { |e| strip_set.include?(e) }.to_set
        end

        # Build the Set of collapse whitespace element names (strings).
        def resolved_collapse_elements_set(match_opts)
          set = Set.new(format_default_collapse_elements(match_opts).map(&:to_s))

          if match_opts[:collapse_whitespace_elements]
            set |= match_opts[:collapse_whitespace_elements].map(&:to_s)
          end

          # Remove blacklisted elements
          strip_set = resolved_strip_elements_set(match_opts)
          set.reject { |e| strip_set.include?(e) }.to_set
        end

        # Build the Set of strip (blacklist) element names (strings).
        def resolved_strip_elements_set(match_opts)
          raw = match_opts[:strip_whitespace_elements]
          Set.new((raw || []).map(&:to_s))
        end

        # Perform the ancestor walk classification.
        # The element itself is checked first, then its ancestors.
        # Strip blacklist wins over any sensitive ancestor.
        def walk_ancestor_classification(element, preserve_set, collapse_set,
                                         strip_set, _match_opts)
          current = element
          while current.respond_to?(:name)
            name = current.name.to_s

            return :strip    if strip_set.include?(name)
            return :preserve if preserve_set.include?(name)
            return :collapse if collapse_set.include?(name)

            # Walk up
            break unless current.respond_to?(:parent)

            parent = current.parent
            break if parent.nil?
            break unless parent.respond_to?(:name)
            break if parent == current # guard infinite loop

            current = parent
          end

          # No matching ancestor — whitespace sensitivity is always opt-in.
          # Elements not in any list are strip regardless of format.
          # (HTML_COLLAPSE_ELEMENTS are already merged into the collapse_set
          #  by resolved_collapse_elements_set, so they are found during the walk.)
          :strip
        end

        # Check if we should respect xml:space attribute
        def respect_xml_space?(match_opts)
          if match_opts.key?(:respect_xml_space)
            match_opts[:respect_xml_space]
          else
            true
          end
        end

        # Check if xml:space="preserve" is set
        def xml_space_preserve?(element)
          if element.is_a?(Canon::Xml::Nodes::ElementNode)
            element.attribute_nodes.any? do |attr|
              attr.name == "space" &&
                attr.namespace_uri == "http://www.w3.org/XML/1998/namespace" &&
                attr.value == "preserve"
            end
          elsif element.respond_to?(:[])
            element["xml:space"] == "preserve"
          else
            false
          end
        end

        # Check if xml:space="default" is set
        def xml_space_default?(element)
          if element.is_a?(Canon::Xml::Nodes::ElementNode)
            element.attribute_nodes.any? do |attr|
              attr.name == "space" &&
                attr.namespace_uri == "http://www.w3.org/XML/1998/namespace" &&
                attr.value == "default"
            end
          elsif element.respond_to?(:[])
            element["xml:space"] == "default"
          else
            false
          end
        end

        # Check sensitivity based on user configuration (binary, no ancestor)
        def user_config_sensitive?(element, match_opts)
          list = match_opts[:preserve_whitespace_elements]
          return false unless list

          list.map(&:to_s).include?(element.name.to_s)
        end

        # Check if node has a parent that's an element (not document root)
        def text_node_parent?(node)
          return false unless node.respond_to?(:parent)
          return false unless node.parent

          parent = node.parent
          return true if parent.respond_to?(:element?) && parent.element?

          # Nokogiri compatibility
          parent.respond_to?(:node_type) && parent.node_type == :element
        end
      end
    end
  end
end
