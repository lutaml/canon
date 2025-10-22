# frozen_string_literal: true

module Canon
  module Xml
    # Matches XML elements semantically across two DOM trees
    #
    # This class implements intelligent element matching for XML diffs.
    # Instead of naive line-by-line comparison, it semantically matches
    # elements across documents using identity attributes and structural
    # position.
    #
    # == Matching Strategy
    #
    # Elements are matched in two passes:
    #
    # 1. **Identity attribute matching**: Elements with same identity attribute
    #    values are matched (e.g., id="foo" matches id="foo")
    # 2. **Position-based matching**: Remaining elements matched by name and
    #    document position
    #
    # This allows detecting when elements:
    # - Move to different positions (matched by ID)
    # - Have content changes (matched, diff shows changes)
    # - Are added/deleted (no match found)
    #
    # == Identity Attributes
    #
    # By default, these attributes identify elements:
    # - id
    # - ref
    # - name
    # - key
    #
    # Custom identity attributes can be provided to the constructor.
    #
    # == Usage
    #
    #   matcher = ElementMatcher.new
    #   root1 = Canon::Xml::DataModel.from_xml(xml1)
    #   root2 = Canon::Xml::DataModel.from_xml(xml2)
    #   matches = matcher.match_trees(root1, root2)
    #
    #   matches.each do |match|
    #     case match.status
    #     when :matched
    #       # Elements found in both trees
    #     when :deleted
    #       # Element only in first tree
    #     when :inserted
    #       # Element only in second tree
    #     end
    #   end
    #
    class ElementMatcher
      # Default attributes used to identify elements
      DEFAULT_IDENTITY_ATTRS = %w[id ref name key].freeze

      # Match result for an element
      MatchResult = Struct.new(:status, :elem1, :elem2, :path) do
        def matched?
          status == :matched
        end

        def inserted?
          status == :inserted
        end

        def deleted?
          status == :deleted
        end
      end

      def initialize(identity_attrs: DEFAULT_IDENTITY_ATTRS)
        @identity_attrs = identity_attrs
        @matches = []
      end

      # Match elements between two DOM trees
      #
      # @param root1 [Canon::Xml::Nodes::RootNode] First DOM tree
      # @param root2 [Canon::Xml::Nodes::RootNode] Second DOM tree
      # @return [Array<MatchResult>] Array of match results
      def match_trees(root1, root2)
        @matches = []
        match_children(root1.children, root2.children, [])
        @matches
      end

      private

      # Match children recursively
      def match_children(children1, children2, path)
        # Filter to only element nodes
        elems1 = children1.select { |n| n.node_type == :element }
        elems2 = children2.select { |n| n.node_type == :element }

        # Build identity maps for quick lookup
        map1 = build_identity_map(elems1)
        map2 = build_identity_map(elems2)

        matched1 = Set.new
        matched2 = Set.new

        # Match by identity attributes
        map1.each do |identity, elem1|
          if map2.key?(identity)
            elem2 = map2[identity]
            elem_path = path + [elem1.name]
            @matches << MatchResult.new(:matched, elem1, elem2, elem_path)
            matched1.add(elem1)
            matched2.add(elem2)

            # Recursively match children
            match_children(elem1.children, elem2.children, elem_path)
          end
        end

        # Match remaining elements by name and position
        unmatched1 = elems1.reject { |e| matched1.include?(e) }
        unmatched2 = elems2.reject { |e| matched2.include?(e) }

        match_by_position(unmatched1, unmatched2, path, matched1, matched2)

        # Record unmatched as deleted/inserted
        unmatched1.each do |elem1|
          next if matched1.include?(elem1)

          elem_path = path + [elem1.name]
          @matches << MatchResult.new(:deleted, elem1, nil, elem_path)
        end

        unmatched2.each do |elem2|
          next if matched2.include?(elem2)

          elem_path = path + [elem2.name]
          @matches << MatchResult.new(:inserted, nil, elem2, elem_path)
        end
      end

      # Match remaining elements by name and position
      def match_by_position(elems1, elems2, path, matched1, matched2)
        # Group by element name
        by_name1 = elems1.group_by(&:name)
        by_name2 = elems2.group_by(&:name)

        # For each name, match by position
        by_name1.each do |name, list1|
          next unless by_name2.key?(name)

          list2 = by_name2[name]

          # Match pairs by position
          [list1.length, list2.length].min.times do |i|
            elem1 = list1[i]
            elem2 = list2[i]

            next if matched1.include?(elem1) || matched2.include?(elem2)

            elem_path = path + [name]
            @matches << MatchResult.new(:matched, elem1, elem2, elem_path)
            matched1.add(elem1)
            matched2.add(elem2)

            # Recursively match children
            match_children(elem1.children, elem2.children, elem_path)
          end
        end
      end

      # Build map of identity → element
      def build_identity_map(elements)
        map = {}

        elements.each do |elem|
          identity = extract_identity(elem)
          next unless identity

          # Use element name + identity as key to handle multiple element types
          key = "#{elem.name}##{identity}"
          map[key] = elem
        end

        map
      end

      # Extract identity from element attributes
      def extract_identity(elem)
        @identity_attrs.each do |attr_name|
          attr = elem.attribute_nodes.find { |a| a.name == attr_name }
          return attr.value if attr
        end
        nil
      end
    end
  end
end
