# frozen_string_literal: true

module Canon
  module Comparison
    # Whitespace sensitivity utilities for element-level control
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

      # HTML inline elements — whitespace between these is semantically
      # significant (renders as a visible space).  Whitespace-only text
      # nodes that sit between two inline siblings must not be stripped.
      INLINE_ELEMENTS = %w[
        a abbr acronym b bdo big br button cite code dfn em i img input kbd
        label map object output q s samp select small span strong sub sup
        time tt u var wbr
      ].freeze

      class << self
        # Classify the whitespace behaviour for an element using ancestor walk.
        def classify_element(element, match_opts)
          return :strip unless element
          return :strip unless node_name(element)

          preserve_set  = resolved_preserve_elements_set(match_opts)
          collapse_set  = resolved_collapse_elements_set(match_opts)
          strip_set = resolved_strip_elements_set(match_opts)

          walk_ancestor_classification(element, preserve_set, collapse_set,
                                       strip_set)
        end

        # Check if an element is whitespace-sensitive based on configuration.
        def element_sensitive?(node, opts)
          match_opts = opts[:match_opts]
          return false unless match_opts
          return false unless text_node_parent?(node)

          parent = node_parent(node)

          unless respect_xml_space?(match_opts)
            return user_config_sensitive?(parent, match_opts)
          end

          return true if xml_space_preserve?(parent)
          return false if xml_space_default?(parent)

          classification = classify_element(parent, match_opts)
          %i[preserve collapse].include?(classification)
        end

        # Check if whitespace-only text node should be filtered
        def preserve_whitespace_node?(node, opts)
          parent = node_parent(node)
          return false unless parent

          element_sensitive?(node, opts)
        end

        # Return the whitespace class for a text node used during comparison.
        def classify_text_node(node, opts)
          match_opts = opts[:match_opts]
          return :strip unless match_opts
          return :strip unless text_node_parent?(node)

          parent = node_parent(node)

          unless respect_xml_space?(match_opts)
            return user_config_sensitive?(parent,
                                          match_opts) ? :preserve : :strip
          end

          return :preserve if xml_space_preserve?(parent)
          return :strip if xml_space_default?(parent)

          classify_element(parent, match_opts)
        end

        # Check if structural whitespace is preserved (not stripped) for an element.
        def whitespace_preserved?(element, match_opts)
          if respect_xml_space?(match_opts)
            return true  if xml_space_preserve?(element)
            return false if xml_space_default?(element)
          end

          classification = classify_element(element, match_opts)
          %i[preserve collapse].include?(classification)
        end

        def resolved_preserve_elements(match_opts)
          resolved_preserve_elements_set(match_opts).to_a
        end

        def resolved_collapse_elements(match_opts)
          resolved_collapse_elements_set(match_opts).to_a
        end

        def format_default_preserve_elements(match_opts)
          format = match_opts[:format] || :xml
          case format
          when :html, :html4, :html5
            HTML_PRESERVE_ELEMENTS.map(&:to_sym).freeze
          else
            [].freeze
          end
        end

        def format_default_collapse_elements(match_opts)
          format = match_opts[:format] || :xml
          case format
          when :html, :html4, :html5
            HTML_COLLAPSE_ELEMENTS.map(&:to_sym).freeze
          else
            [].freeze
          end
        end

        def default_sensitive_element?(element_name, match_opts)
          format_default_preserve_elements(match_opts)
            .include?(element_name.to_sym)
        end

        # Check if whitespace-only text node sits between two inline element
        # siblings, making the whitespace semantically significant.
        def inline_whitespace_significant?(text_node)
          parent = NodeInspector.parent(text_node)
          return false unless parent

          siblings = NodeInspector.children(parent)
          idx = siblings.index(text_node)
          return false unless idx

          prev_neighbour = nearest_non_whitespace_sibling(siblings, idx, -1)
          next_neighbour = nearest_non_whitespace_sibling(siblings, idx,  1)

          inline_element?(prev_neighbour) && inline_element?(next_neighbour)
        end

        def nearest_non_whitespace_sibling(siblings, idx, direction)
          i = idx + direction
          while i >= 0 && i < siblings.length
            s = siblings[i]
            unless whitespace_text_node?(s)
              return s
            end

            i += direction
          end
          nil
        end

        def contains_nbsp?(text)
          text.to_s.include?(" ")
        end

        private

        def whitespace_text_node?(node)
          NodeInspector.whitespace_only_text?(node)
        end

        def node_name(node)
          NodeInspector.name(node)
        end

        def node_parent(node)
          NodeInspector.parent(node)
        end

        def node_children(node)
          NodeInspector.children(node)
        end

        def element?(node)
          NodeInspector.element_node?(node)
        end

        def resolved_preserve_elements_set(match_opts)
          set = Set.new(format_default_preserve_elements(match_opts).map(&:to_s))

          if match_opts[:preserve_whitespace_elements]
            set |= match_opts[:preserve_whitespace_elements].map(&:to_s)
          end

          strip_set = resolved_strip_elements_set(match_opts)
          set.reject { |e| strip_set.include?(e) }.to_set
        end

        def resolved_collapse_elements_set(match_opts)
          set = Set.new(format_default_collapse_elements(match_opts).map(&:to_s))

          if match_opts[:collapse_whitespace_elements]
            set |= match_opts[:collapse_whitespace_elements].map(&:to_s)
          end

          strip_set = resolved_strip_elements_set(match_opts)
          set.reject { |e| strip_set.include?(e) }.to_set
        end

        def resolved_strip_elements_set(match_opts)
          raw = match_opts[:strip_whitespace_elements]
          Set.new((raw || []).map(&:to_s))
        end

        def walk_ancestor_classification(element, preserve_set, collapse_set,
                                         strip_set)
          current = element
          while current
            name = node_name(current)
            break unless name

            return :strip    if strip_set.include?(name.to_s)
            return :preserve if preserve_set.include?(name.to_s)
            return :collapse if collapse_set.include?(name.to_s)

            parent = node_parent(current)
            break if parent.nil?
            break if parent == current

            current = parent
          end

          :strip
        end

        def respect_xml_space?(match_opts)
          if match_opts.key?(:respect_xml_space)
            match_opts[:respect_xml_space]
          else
            true
          end
        end

        def xml_space_preserve?(element)
          if element.is_a?(Canon::Xml::Nodes::ElementNode)
            element.attribute_nodes.any? do |attr|
              attr.name == "space" &&
                attr.namespace_uri == "http://www.w3.org/XML/1998/namespace" &&
                attr.value == "preserve"
            end
          else
            Canon::XmlParsing.attribute_value(element, "xml:space") == "preserve"
          end
        end

        def xml_space_default?(element)
          if element.is_a?(Canon::Xml::Nodes::ElementNode)
            element.attribute_nodes.any? do |attr|
              attr.name == "space" &&
                attr.namespace_uri == "http://www.w3.org/XML/1998/namespace" &&
                attr.value == "default"
            end
          else
            Canon::XmlParsing.attribute_value(element, "xml:space") == "default"
          end
        end

        def user_config_sensitive?(element, match_opts)
          list = match_opts[:preserve_whitespace_elements]
          return false unless list

          name = node_name(element)
          return false unless name

          list.map(&:to_s).include?(name.to_s)
        end

        def text_node_parent?(node)
          parent = node_parent(node)
          return false unless parent

          element?(parent)
        end

        def parent_element_of(text_node)
          parent = node_parent(text_node)
          return nil unless parent

          parent if element?(parent)
        end

        def inline_element?(node)
          name = node_name(node)
          return false unless name

          INLINE_ELEMENTS.include?(name.to_s.downcase)
        end
      end
    end
  end
end
