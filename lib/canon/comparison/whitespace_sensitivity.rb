# frozen_string_literal: true

module Canon
  module Comparison
    # Whitespace sensitivity utilities for element-level control
    #
    # This module provides logic to determine whether whitespace should be
    # preserved during comparison based on:
    # - Format-specific defaults (HTML has built-in sensitive elements)
    # - User-configured whitelist (elements that care about whitespace)
    # - User-configured blacklist (elements that don't care about whitespace)
    # - xml:space attribute in the document itself
    # - respect_xml_space flag (whether to honor or override xml:space)
    #
    # == Priority Order
    #
    # 1. respect_xml_space: false → User config only (ignore xml:space)
    # 2. User whitelist → Use whitelist (user explicitly declared)
    # 3. Format defaults → HTML: [:pre, :textarea, :script, :style], XML: []
    # 4. User blacklist → Remove from defaults/whitelist
    # 5. xml:space="preserve" → Element is sensitive
    # 6. xml:space="default" → Use steps 1-4
    #
    # == Usage
    #
    #   WhitespaceSensitivity.element_sensitive?(node, opts)
    #   => true if whitespace should be preserved for this element
    module WhitespaceSensitivity
      class << self
        # Check if an element is whitespace-sensitive based on configuration
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
          if !respect_xml_space?(match_opts)
            return user_config_sensitive?(parent, match_opts)
          end

          # 2. Check xml:space="preserve" (document declaration)
          return true if xml_space_preserve?(parent)

          # 3. Check xml:space="default" (use configured behavior)
          return false if xml_space_default?(parent)

          # 4. Use user configuration + format defaults
          configured_sensitive?(parent, match_opts)
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

        # Get format-specific default sensitive elements
        #
        # This is the SINGLE SOURCE OF TRUTH for default whitespace-sensitive
        # elements. All other code should use this method to get the list.
        #
        # @param match_opts [Hash] Resolved match options
        # @return [Array<Symbol>] Default sensitive element names
        def format_default_sensitive_elements(match_opts)
          format = match_opts[:format] || :xml

          case format
          when :html, :html4, :html5
            # HTML specification: these elements preserve whitespace
            %i[pre code textarea script style].freeze
          when :xml
            # XML has no default sensitive elements - purely user-controlled
            [].freeze
          else
            [].freeze
          end
        end

        # Check if an element is in the default sensitive list for its format
        #
        # Convenience method for checking element sensitivity without building
        # the full list first.
        #
        # @param element_name [String, Symbol] The element name to check
        # @param match_opts [Hash] Resolved match options
        # @return [Boolean] true if element is in default sensitive list
        def default_sensitive_element?(element_name, match_opts)
          format_default_sensitive_elements(match_opts)
            .include?(element_name.to_sym)
        end

        private

        # Check if we should respect xml:space attribute
        #
        # @param match_opts [Hash] Resolved match options
        # @return [Boolean] true if xml:space should be respected
        def respect_xml_space?(match_opts)
          if match_opts.key?(:respect_xml_space)
            match_opts[:respect_xml_space]
          else
            true
          end
        end

        # Check if xml:space="preserve" is set
        #
        # @param element [Object] The element to check
        # @return [Boolean] true if xml:space="preserve"
        def xml_space_preserve?(element)
          if element.is_a?(Canon::Xml::Nodes::ElementNode)
            # Check attribute_nodes for xml:space attribute
            # xml:space is stored with name="space" and namespace_uri="http://www.w3.org/XML/1998/namespace"
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
        #
        # @param element [Object] The element to check
        # @return [Boolean] true if xml:space="default"
        def xml_space_default?(element)
          if element.is_a?(Canon::Xml::Nodes::ElementNode)
            # Check attribute_nodes for xml:space attribute
            # xml:space is stored with name="space" and namespace_uri="http://www.w3.org/XML/1998/namespace"
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

        # Check sensitivity based on user configuration
        #
        # @param element [Object] The element to check
        # @param match_opts [Hash] Resolved match options
        # @return [Boolean] true if element is in whitelist
        def user_config_sensitive?(element, match_opts)
          return false unless match_opts[:whitespace_sensitive_elements]

          match_opts[:whitespace_sensitive_elements].include?(element.name.to_sym)
        end

        # Check sensitivity based on user config + format defaults
        #
        # @param element [Object] The element to check
        # @param match_opts [Hash] Resolved match options
        # @return [Boolean] true if element should be sensitive
        def configured_sensitive?(element, match_opts)
          # Start with format defaults
          sensitive = format_default_sensitive_elements(match_opts).to_set

          # Apply whitelist (adds to defaults)
          if match_opts[:whitespace_sensitive_elements]
            sensitive |= match_opts[:whitespace_sensitive_elements]
          end

          # Apply blacklist (removes from everything)
          if match_opts[:whitespace_insensitive_elements]
            sensitive -= match_opts[:whitespace_insensitive_elements]
          end

          sensitive.include?(element.name.to_sym)
        end

        # Check if node has a parent that's an element (not document root)
        #
        # @param node [Object] The node to check
        # @return [Boolean] true if node has an element parent
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
