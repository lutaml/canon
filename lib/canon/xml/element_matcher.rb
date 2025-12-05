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

      # Represents the result of matching an element across two DOM trees
      #
      # A MatchResult indicates whether an element was found in both trees
      # (matched), only in the first tree (deleted), or only in the second
      # tree (inserted).
      #
      # == Attributes
      #
      # - status: Symbol indicating match type (:matched, :deleted, :inserted)
      # - elem1: Element from first tree (nil if inserted)
      # - elem2: Element from second tree (nil if deleted)
      # - path: Array of element names showing location in tree
      # - pos1: Integer index of elem1 in its parent's children (nil if inserted)
      # - pos2: Integer index of elem2 in its parent's children (nil if deleted)
      #
      # == Position Change Detection
      #
      # When status is :matched and pos1 ≠ pos2, the element has moved positions.
      # This is tracked as a semantic difference via the :element_position dimension.
      #
      class MatchResult
        attr_reader :status, :elem1, :elem2, :path, :pos1, :pos2

        # @param status [Symbol] Match status (:matched, :deleted, :inserted)
        # @param elem1 [Object, nil] Element from first tree
        # @param elem2 [Object, nil] Element from second tree
        # @param path [Array<String>] Element path in tree
        # @param pos1 [Integer, nil] Position index in first tree
        # @param pos2 [Integer, nil] Position index in second tree
        def initialize(status:, elem1:, elem2:, path:, pos1: nil, pos2: nil)
          @status = status
          @elem1 = elem1
          @elem2 = elem2
          @path = path
          @pos1 = pos1
          @pos2 = pos2
        end

        # @return [Boolean] true if element found in both trees
        def matched?
          status == :matched
        end

        # @return [Boolean] true if element only in second tree
        def inserted?
          status == :inserted
        end

        # @return [Boolean] true if element only in first tree
        def deleted?
          status == :deleted
        end

        # @return [Boolean] true if element moved to different position
        def position_changed?
          matched? && pos1 && pos2 && pos1 != pos2
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

            # Track positions
            pos1 = elems1.index(elem1)
            pos2 = elems2.index(elem2)

            @matches << MatchResult.new(
              status: :matched,
              elem1: elem1,
              elem2: elem2,
              path: elem_path,
              pos1: pos1,
              pos2: pos2,
            )
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
          pos1 = elems1.index(elem1)

          @matches << MatchResult.new(
            status: :deleted,
            elem1: elem1,
            elem2: nil,
            path: elem_path,
            pos1: pos1,
            pos2: nil,
          )
        end

        unmatched2.each do |elem2|
          next if matched2.include?(elem2)

          elem_path = path + [elem2.name]
          pos2 = elems2.index(elem2)

          @matches << MatchResult.new(
            status: :inserted,
            elem1: nil,
            elem2: elem2,
            path: elem_path,
            pos1: nil,
            pos2: pos2,
          )
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

            # Track positions in original element lists
            pos1 = elems1.index(elem1)
            pos2 = elems2.index(elem2)

            @matches << MatchResult.new(
              status: :matched,
              elem1: elem1,
              elem2: elem2,
              path: elem_path,
              pos1: pos1,
              pos2: pos2,
            )
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
