# frozen_string_literal: true

require "moxml"
require "nokogiri"
require_relative "xml/whitespace_normalizer"

module Canon
  # Comparison module for XML, HTML, JSON, and YAML documents
  # Provides format detection and delegation to format-specific modules
  module Comparison
    # Comparison result constants
    EQUIVALENT = 1
    MISSING_ATTRIBUTE = 2
    MISSING_NODE = 3
    UNEQUAL_ATTRIBUTES = 4
    UNEQUAL_COMMENTS = 5
    UNEQUAL_DOCUMENTS = 6
    UNEQUAL_ELEMENTS = 7
    UNEQUAL_NODES_TYPES = 8
    UNEQUAL_TEXT_CONTENTS = 9
    MISSING_HASH_KEY = 10
    UNEQUAL_HASH_VALUES = 11
    UNEQUAL_ARRAY_LENGTHS = 12
    UNEQUAL_ARRAY_ELEMENTS = 13
    UNEQUAL_TYPES = 14
    UNEQUAL_PRIMITIVES = 15

    class << self
      # Auto-detect format and compare two objects
      #
      # @param obj1 [Object] First object to compare
      # @param obj2 [Object] Second object to compare
      # @param opts [Hash] Comparison options
      # @return [Boolean, Array] true if equivalent, or array of diffs if verbose
      def equivalent?(obj1, obj2, opts = {})
        format1 = detect_format(obj1)
        format2 = detect_format(obj2)

        # Allow comparing json/yaml strings with ruby objects
        # since they parse to the same structure
        formats_compatible = format1 == format2 ||
          (%i[json ruby_object].include?(format1) &&
           %i[json ruby_object].include?(format2)) ||
          (%i[yaml ruby_object].include?(format1) &&
           %i[yaml ruby_object].include?(format2))

        unless formats_compatible
          raise Canon::CompareFormatMismatchError.new(format1, format2)
        end

        # Normalize format for comparison
        comparison_format = case format1
                            when :ruby_object
                              # If comparing ruby_object with json/yaml, use that format
                              %i[json yaml].include?(format2) ? format2 : :json
                            else
                              format1
                            end

        case comparison_format
        when :xml
          Xml.equivalent?(obj1, obj2, opts)
        when :html
          Html.equivalent?(obj1, obj2, opts)
        when :json
          Json.equivalent?(obj1, obj2, opts)
        when :yaml
          Yaml.equivalent?(obj1, obj2, opts)
        end
      end

      private

      # Detect the format of an object
      #
      # @param obj [Object] Object to detect format of
      # @return [Symbol] Format type
      def detect_format(obj)
        case obj
        when Moxml::Node, Moxml::Document
          :xml
        when Nokogiri::XML::Document, Nokogiri::XML::Node
          # Check if it's HTML by looking at the document type
          obj.html? ? :html : :xml
        when Nokogiri::HTML::Document, Nokogiri::HTML5::Document
          :html
        when String
          detect_string_format(obj)
        when Hash, Array
          # Raw Ruby objects (from parsed JSON/YAML)
          :ruby_object
        else
          raise Canon::Error, "Unknown format for object: #{obj.class}"
        end
      end

      # Detect the format of a string
      #
      # @param str [String] String to detect format of
      # @return [Symbol] Format type
      def detect_string_format(str)
        trimmed = str.strip

        # YAML indicators
        return :yaml if trimmed.start_with?("---")
        return :yaml if trimmed.match?(/^[a-zA-Z_]\w*:\s/)

        # JSON indicators
        return :json if trimmed.start_with?("{", "[")

        # HTML indicators
        return :html if trimmed.start_with?("<!DOCTYPE html", "<html", "<HTML")

        # Default to XML
        :xml
      end
    end

    # XML comparison module
    module Xml
      # Default comparison options for XML
      DEFAULT_OPTS = {
        collapse_whitespace: true,
        flexible_whitespace: false,
        ignore_attr_order: true,
        force_children: false,
        ignore_children: false,
        ignore_attr_content: [],
        ignore_attrs: [],
        ignore_attrs_by_name: [],
        ignore_comments: true,
        ignore_nodes: [],
        ignore_text_nodes: false,
        normalize_tag_whitespace: false,
        verbose: false,
      }.freeze

      class << self
        # Compare two XML nodes for equivalence
        #
        # @param n1 [String, Moxml::Node] First node
        # @param n2 [String, Moxml::Node] Second node
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(n1, n2, opts = {}, child_opts = {})
          opts = DEFAULT_OPTS.merge(opts)
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings
          node1 = parse_node(n1)
          node2 = parse_node(n2)

          differences = []
          diff_children = opts[:diff_children] || false

          result = compare_nodes(node1, node2, opts, child_opts,
                                 diff_children, differences)

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        def parse_node(node)
          return node unless node.is_a?(String)

          # Use Moxml for XML
          Moxml.new.parse(node)
        end

        # Main comparison dispatcher
        def compare_nodes(n1, n2, opts, child_opts, diff_children, differences)
          # Check if nodes should be excluded
          return Comparison::EQUIVALENT if node_excluded?(n1, opts) &&
            node_excluded?(n2, opts)

          if node_excluded?(n1, opts) || node_excluded?(n2, opts)
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, opts, differences)
            return Comparison::MISSING_NODE
          end

          # Check node types match
          unless same_node_type?(n1, n2)
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, opts, differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          # Dispatch based on node type
          if n1.respond_to?(:element?) && n1.element?
            compare_element_nodes(n1, n2, opts, child_opts, diff_children,
                                  differences)
          elsif n1.respond_to?(:text?) && n1.text?
            compare_text_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:comment?) && n1.comment?
            compare_comment_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:cdata?) && n1.cdata?
            compare_text_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:processing_instruction?) &&
              n1.processing_instruction?
            compare_processing_instruction_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:root)
            # Document node
            compare_document_nodes(n1, n2, opts, child_opts, diff_children,
                                   differences)
          else
            Comparison::EQUIVALENT
          end
        end

        # Compare two element nodes
        def compare_element_nodes(n1, n2, opts, child_opts, diff_children,
                                  differences)
          # Compare element names
          unless n1.name == n2.name
            add_difference(n1, n2, Comparison::UNEQUAL_ELEMENTS,
                           Comparison::UNEQUAL_ELEMENTS, opts, differences)
            return Comparison::UNEQUAL_ELEMENTS
          end

          # Compare attributes
          attr_result = compare_attribute_sets(n1, n2, opts, differences)
          return attr_result unless attr_result == Comparison::EQUIVALENT

          # Compare children if not ignored
          return Comparison::EQUIVALENT if opts[:ignore_children]

          compare_children(n1, n2, opts, child_opts, diff_children, differences)
        end

        # Compare attribute sets
        def compare_attribute_sets(n1, n2, opts, differences)
          attrs1 = filter_attributes(n1.attributes, opts)
          attrs2 = filter_attributes(n2.attributes, opts)

          # Sort attributes if order should be ignored
          if opts[:ignore_attr_order]
            attrs1 = attrs1.sort_by { |k, _v| k.to_s }.to_h
            attrs2 = attrs2.sort_by { |k, _v| k.to_s }.to_h
          end

          unless attrs1.keys.map(&:to_s).sort == attrs2.keys.map(&:to_s).sort
            add_difference(n1, n2, Comparison::MISSING_ATTRIBUTE,
                           Comparison::MISSING_ATTRIBUTE, opts, differences)
            return Comparison::MISSING_ATTRIBUTE
          end

          attrs1.each do |name, value|
            unless attrs2[name] == value
              add_difference(n1, n2, Comparison::UNEQUAL_ATTRIBUTES,
                             Comparison::UNEQUAL_ATTRIBUTES, opts, differences)
              return Comparison::UNEQUAL_ATTRIBUTES
            end
          end

          Comparison::EQUIVALENT
        end

        # Filter attributes based on options
        def filter_attributes(attributes, opts)
          filtered = {}

          attributes.each do |name, attr|
            value = attr.respond_to?(:value) ? attr.value : attr

            # Skip if attribute name should be ignored
            next if should_ignore_attr_by_name?(name, opts)

            # Skip if attribute content should be ignored
            next if should_ignore_attr_content?(value, opts)

            filtered[name] = value
          end

          filtered
        end

        # Check if attribute should be ignored by name
        def should_ignore_attr_by_name?(name, opts)
          opts[:ignore_attrs_by_name].any? do |pattern|
            name.include?(pattern)
          end
        end

        # Check if attribute should be ignored by content
        def should_ignore_attr_content?(value, opts)
          opts[:ignore_attr_content].any? do |pattern|
            value.to_s.include?(pattern)
          end
        end

        # Compare text nodes
        def compare_text_nodes(n1, n2, opts, differences)
          return Comparison::EQUIVALENT if opts[:ignore_text_nodes]

          text1 = node_text(n1)
          text2 = node_text(n2)

          if opts[:normalize_tag_whitespace]
            text1 = normalize_tag_whitespace(text1)
            text2 = normalize_tag_whitespace(text2)
          elsif opts[:collapse_whitespace]
            text1 = collapse(text1)
            text2 = collapse(text2)
          end

          if text1 == text2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, opts, differences)
            Comparison::UNEQUAL_TEXT_CONTENTS
          end
        end

        # Compare comment nodes
        def compare_comment_nodes(n1, n2, opts, differences)
          return Comparison::EQUIVALENT if opts[:ignore_comments]

          content1 = n1.content.to_s.strip
          content2 = n2.content.to_s.strip

          if content1 == content2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_COMMENTS,
                           Comparison::UNEQUAL_COMMENTS, opts, differences)
            Comparison::UNEQUAL_COMMENTS
          end
        end

        # Compare processing instruction nodes
        def compare_processing_instruction_nodes(n1, n2, opts, differences)
          unless n1.target == n2.target
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, opts, differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          content1 = n1.content.to_s.strip
          content2 = n2.content.to_s.strip

          if content1 == content2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, opts, differences)
            Comparison::UNEQUAL_TEXT_CONTENTS
          end
        end

        # Compare document nodes
        def compare_document_nodes(n1, n2, opts, child_opts, diff_children,
                                   differences)
          # Compare root elements
          root1 = n1.root
          root2 = n2.root

          if root1.nil? || root2.nil?
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, opts, differences)
            return Comparison::MISSING_NODE
          end

          compare_nodes(root1, root2, opts, child_opts, diff_children,
                        differences)
        end

        # Compare children of two nodes
        def compare_children(n1, n2, opts, child_opts, diff_children,
                             differences)
          children1 = filter_children(n1.children, opts)
          children2 = filter_children(n2.children, opts)

          unless children1.length == children2.length
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, opts, differences)
            return Comparison::MISSING_NODE
          end

          children1.zip(children2).each do |child1, child2|
            result = compare_nodes(child1, child2, child_opts, child_opts,
                                   diff_children, differences)
            return result unless result == Comparison::EQUIVALENT
          end

          Comparison::EQUIVALENT
        end

        # Filter children based on options
        def filter_children(children, opts)
          children.reject do |child|
            node_excluded?(child, opts)
          end
        end

        # Check if node should be excluded
        def node_excluded?(node, opts)
          # Ignore comments if specified
          return true if opts[:ignore_comments] &&
            node.respond_to?(:comment?) && node.comment?

          # Ignore text nodes if specified
          return true if opts[:ignore_text_nodes] &&
            node.respond_to?(:text?) && node.text?

          # Ignore whitespace-only text nodes when collapsing whitespace
          if opts[:collapse_whitespace] &&
              node.respond_to?(:text?) && node.text?
            text = node_text(node)
            return true if collapse(text).empty?
          end

          false
        end

        # Check if two nodes are the same type
        def same_node_type?(n1, n2)
          return true if n1.respond_to?(:element?) && n1.element? &&
            n2.respond_to?(:element?) && n2.element?
          return true if n1.respond_to?(:text?) && n1.text? &&
            n2.respond_to?(:text?) && n2.text?
          return true if n1.respond_to?(:comment?) && n1.comment? &&
            n2.respond_to?(:comment?) && n2.comment?
          return true if n1.respond_to?(:cdata?) && n1.cdata? &&
            n2.respond_to?(:cdata?) && n2.cdata?
          return true if n1.respond_to?(:processing_instruction?) &&
            n1.processing_instruction? &&
            n2.respond_to?(:processing_instruction?) &&
            n2.processing_instruction?
          return true if n1.respond_to?(:root) && n2.respond_to?(:root)

          false
        end

        # Get text content from a node
        def node_text(node)
          if node.respond_to?(:content)
            node.content.to_s
          elsif node.respond_to?(:text)
            node.text.to_s
          else
            ""
          end
        end

        # Collapse whitespace in text
        def collapse(text)
          text.to_s.gsub(/\s+/, " ").strip
        end

        # Normalize tag whitespace - for forgiving whitespace mode
        # Treats whitespace boundaries of tags' open/close and newlines as single space or no space
        def normalize_tag_whitespace(text)
          text.to_s
            .gsub(/\s+/, " ")  # Collapse multiple whitespace to single space
            .strip             # Remove leading/trailing whitespace
        end

        # Add a difference to the differences array
        def add_difference(node1, node2, diff1, diff2, opts, differences)
          return unless opts[:verbose]

          differences << {
            node1: node1,
            node2: node2,
            diff1: diff1,
            diff2: diff2,
          }
        end
      end
    end

    # HTML comparison module
    module Html
      # Default comparison options for HTML
      DEFAULT_OPTS = {
        collapse_whitespace: true,
        ignore_attr_order: true,
        force_children: false,
        ignore_children: false,
        ignore_attr_content: [],
        ignore_attrs: [],
        ignore_attrs_by_name: [],
        ignore_comments: true,
        ignore_nodes: [],
        ignore_text_nodes: false,
        verbose: false,
      }.freeze

      class << self
        # Compare two HTML nodes for equivalence
        #
        # @param html1 [String, Nokogiri::HTML::Document] First HTML
        # @param html2 [String, Nokogiri::HTML::Document] Second HTML
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(html1, html2, opts = {}, child_opts = {})
          opts = DEFAULT_OPTS.merge(opts)
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings
          node1 = parse_node(html1)
          node2 = parse_node(html2)

          differences = []
          diff_children = opts[:diff_children] || false

          result = Xml.send(:compare_nodes, node1, node2, opts, child_opts,
                            diff_children, differences)

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        def parse_node(node)
          return node unless node.is_a?(String)

          # Use Nokogiri for HTML and normalize style/script comments
          doc = Nokogiri::HTML(node)
          normalize_html_style_script_comments(doc)
          doc
        end

        # Normalize HTML comments within style and script tags
        def normalize_html_style_script_comments(doc)
          doc.css("style, script").each do |element|
            next if element.content.strip.empty?

            # Remove HTML comments from style/script content
            normalized = element.content.gsub(/<!--.*?-->/m, "").strip
            element.content = normalized
          end
        end
      end
    end

    # JSON comparison module
    module Json
      # Default comparison options for JSON
      DEFAULT_OPTS = {
        ignore_attr_order: true,
        verbose: false,
      }.freeze

      class << self
        # Compare two JSON objects for equivalence
        #
        # @param json1 [String, Hash, Array] First JSON
        # @param json2 [String, Hash, Array] Second JSON
        # @param opts [Hash] Comparison options
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(json1, json2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Parse JSON if strings
          obj1 = parse_json(json1)
          obj2 = parse_json(json2)

          differences = []
          result = compare_ruby_objects(obj1, obj2, opts, differences, "")

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse JSON from string or return as-is
        def parse_json(obj)
          return obj unless obj.is_a?(String)

          require "json"
          JSON.parse(obj)
        end

        # Compare Ruby objects (Hash, Array, primitives) for JSON/YAML
        def compare_ruby_objects(obj1, obj2, opts, differences, path)
          # Check for type mismatch
          unless obj1.instance_of?(obj2.class)
            add_ruby_difference(path, obj1, obj2, Comparison::UNEQUAL_TYPES,
                                opts, differences)
            return Comparison::UNEQUAL_TYPES
          end

          case obj1
          when Hash
            compare_hashes(obj1, obj2, opts, differences, path)
          when Array
            compare_arrays(obj1, obj2, opts, differences, path)
          when NilClass, TrueClass, FalseClass, Numeric, String, Symbol
            compare_primitives(obj1, obj2, opts, differences, path)
          else
            # Fallback to equality comparison
            if obj1 == obj2
              Comparison::EQUIVALENT
            else
              add_ruby_difference(path, obj1, obj2,
                                  Comparison::UNEQUAL_PRIMITIVES, opts,
                                  differences)
              Comparison::UNEQUAL_PRIMITIVES
            end
          end
        end

        # Compare two hashes
        def compare_hashes(hash1, hash2, opts, differences, path)
          keys1 = hash1.keys
          keys2 = hash2.keys

          # Sort keys if order should be ignored
          if opts[:ignore_attr_order]
            keys1 = keys1.sort_by(&:to_s)
            keys2 = keys2.sort_by(&:to_s)
          end

          # Check for missing keys
          missing_in_2 = keys1 - keys2
          missing_in_1 = keys2 - keys1

          missing_in_2.each do |key|
            key_path = path.empty? ? key.to_s : "#{path}.#{key}"
            add_ruby_difference(key_path, hash1[key], nil,
                                Comparison::MISSING_HASH_KEY, opts, differences)
          end

          missing_in_1.each do |key|
            key_path = path.empty? ? key.to_s : "#{path}.#{key}"
            add_ruby_difference(key_path, nil, hash2[key],
                                Comparison::MISSING_HASH_KEY, opts, differences)
          end

          has_missing_keys = !missing_in_1.empty? || !missing_in_2.empty?

          # Compare common keys
          common_keys = keys1 & keys2
          all_equivalent = true
          common_keys.each do |key|
            key_path = path.empty? ? key.to_s : "#{path}.#{key}"
            result = compare_ruby_objects(hash1[key], hash2[key], opts,
                                          differences, key_path)
            all_equivalent = false unless result == Comparison::EQUIVALENT
          end

          # Return appropriate status
          return Comparison::MISSING_HASH_KEY if has_missing_keys && all_equivalent
          return Comparison::UNEQUAL_HASH_VALUES unless all_equivalent

          has_missing_keys ? Comparison::MISSING_HASH_KEY : Comparison::EQUIVALENT
        end

        # Compare two arrays
        def compare_arrays(arr1, arr2, opts, differences, path)
          unless arr1.length == arr2.length
            add_ruby_difference(path, arr1, arr2,
                                Comparison::UNEQUAL_ARRAY_LENGTHS, opts,
                                differences)
            return Comparison::UNEQUAL_ARRAY_LENGTHS
          end

          all_equivalent = true
          arr1.each_with_index do |elem1, index|
            elem2 = arr2[index]
            elem_path = "#{path}[#{index}]"
            result = compare_ruby_objects(elem1, elem2, opts, differences,
                                          elem_path)
            all_equivalent = false unless result == Comparison::EQUIVALENT
          end

          all_equivalent ? Comparison::EQUIVALENT : Comparison::UNEQUAL_ARRAY_ELEMENTS
        end

        # Compare primitive values
        def compare_primitives(val1, val2, opts, differences, path)
          if val1 == val2
            Comparison::EQUIVALENT
          else
            add_ruby_difference(path, val1, val2,
                                Comparison::UNEQUAL_PRIMITIVES, opts,
                                differences)
            Comparison::UNEQUAL_PRIMITIVES
          end
        end

        # Add a Ruby object difference
        def add_ruby_difference(path, obj1, obj2, diff_code, opts, differences)
          return unless opts[:verbose]

          differences << {
            path: path,
            value1: obj1,
            value2: obj2,
            diff_code: diff_code,
          }
        end
      end
    end

    # YAML comparison module
    module Yaml
      # Default comparison options for YAML
      DEFAULT_OPTS = {
        ignore_attr_order: true,
        verbose: false,
      }.freeze

      class << self
        # Compare two YAML objects for equivalence
        #
        # @param yaml1 [String, Hash, Array] First YAML
        # @param yaml2 [String, Hash, Array] Second YAML
        # @param opts [Hash] Comparison options
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(yaml1, yaml2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Parse YAML if strings
          obj1 = parse_yaml(yaml1)
          obj2 = parse_yaml(yaml2)

          differences = []
          result = Json.send(:compare_ruby_objects, obj1, obj2, opts,
                             differences, "")

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse YAML from string or return as-is
        def parse_yaml(obj)
          return obj unless obj.is_a?(String)

          require "yaml"
          YAML.safe_load(obj)
        end
      end
    end
  end
end
