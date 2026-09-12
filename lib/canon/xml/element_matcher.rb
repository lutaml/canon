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
      DEFAULT_IDENTITY_ATTRS = %w[id ref name key class].freeze

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

      # Match one level of children only — no descent into matched
      # pairs. The comparator walks descendants itself (compare_nodes →
      # ChildComparison per level), so the nested matches match_trees
      # would produce below this level are discarded by its direct-
      # children filter; matching them is wasted work.
      #
      # @param children1 [Array<Canon::Xml::Node>] First parent's children
      # @param children2 [Array<Canon::Xml::Node>] Second parent's children
      # @return [Array<MatchResult>] Match results for these children only
      def match_children_only(children1, children2)
        @matches = []
        match_level(children1, children2, [], recursive: false)
        @matches
      end

      private

      # Match children recursively
      def match_children(children1, children2, path)
        # FAST PATH: Same array object means all children match
        return if children1.equal?(children2)

        match_level(children1, children2, path, recursive: true)
      end

      # One matching level: identity attributes, then name+namespace
      # position, then class attribute, then deleted/inserted recording.
      # With +recursive:+ true, matched pairs descend immediately after
      # being recorded (match_trees' ordering contract).
      def match_level(children1, children2, path, recursive:)
        # Filter to only element nodes
        elems1 = children1.select { |n| n.node_type == :element }
        elems2 = children2.select { |n| n.node_type == :element }

        # FAST PATH: pairwise-corresponding children. When both lists
        # are the same length and every position pairs elements with
        # equal name, namespace URI, and identity value, the full
        # matcher's output is exactly the positional pairing: unique
        # identity keys pair same-with-same, duplicate keys pair
        # last-with-last in the identity phase and the rest pair in
        # order in the positional phase. No deleted/inserted results
        # either way. Skip the identity/positional/class machinery.
        if !elems1.empty? && elems1.length == elems2.length &&
            pairwise_corresponding?(elems1, elems2)
          record_positional_matches(elems1, elems2, path,
                                    recursive: recursive)
          return
        end

        # Positions by identity: elems.index(elem) was an O(n) scan per
        # recorded match — O(n²) per level on element-heavy parents.
        positions1 = {}
        elems1.each_with_index { |e, i| positions1[e] = i }
        positions2 = {}
        elems2.each_with_index { |e, i| positions2[e] = i }

        # Build identity maps for quick lookup
        map1 = build_identity_map(elems1)
        map2 = build_identity_map(elems2)

        matched1 = Set.new
        matched2 = Set.new

        # Match by identity attributes
        map1.each do |identity, elem1|
          if map2.key?(identity)
            elem2 = map2[identity]

            # Build path with namespace information for clarity
            elem_path_with_ns = if elem1.namespace_uri && !elem1.namespace_uri.empty?
                                  path + ["{#{elem1.namespace_uri}}#{elem1.name}"]
                                else
                                  path + [elem1.name]
                                end

            @matches << MatchResult.new(
              status: :matched,
              elem1: elem1,
              elem2: elem2,
              path: elem_path_with_ns,
              pos1: positions1[elem1],
              pos2: positions2[elem2],
            )

            matched1.add(elem1)
            matched2.add(elem2)

            # Recursively match children
            if recursive
              match_children(elem1.children, elem2.children, elem_path_with_ns)
            end
          end
        end

        # Match remaining elements by name and position
        unmatched1 = elems1.reject { |e| matched1.include?(e) }
        unmatched2 = elems2.reject { |e| matched2.include?(e) }

        match_by_position(unmatched1, unmatched2, path, matched1, matched2,
                          recursive: recursive)

        # Fallback: match remaining elements by class attribute
        # This handles insertions that shift positions
        still_unmatched1 = elems1.reject { |e| matched1.include?(e) }
        still_unmatched2 = elems2.reject { |e| matched2.include?(e) }
        match_by_class(still_unmatched1, still_unmatched2, path, matched1,
                       matched2, recursive: recursive)

        # Record unmatched as deleted/inserted
        unmatched1.each do |elem1|
          next if matched1.include?(elem1)

          elem_path_with_ns = if elem1.namespace_uri && !elem1.namespace_uri.empty?
                                path + ["{#{elem1.namespace_uri}}#{elem1.name}"]
                              else
                                path + [elem1.name]
                              end

          @matches << MatchResult.new(
            status: :deleted,
            elem1: elem1,
            elem2: nil,
            path: elem_path_with_ns,
            pos1: positions1[elem1],
            pos2: nil,
          )
        end

        unmatched2.each do |elem2|
          next if matched2.include?(elem2)

          elem_path_with_ns = if elem2.namespace_uri && !elem2.namespace_uri.empty?
                                path + ["{#{elem2.namespace_uri}}#{elem2.name}"]
                              else
                                path + [elem2.name]
                              end

          @matches << MatchResult.new(
            status: :inserted,
            elem1: nil,
            elem2: elem2,
            path: elem_path_with_ns,
            pos1: nil,
            pos2: positions2[elem2],
          )
        end
      end

      # True when every position pairs elements with equal name,
      # namespace URI, and identity value (nil-safe).
      def pairwise_corresponding?(elems1, elems2)
        elems1.each_index.all? do |i|
          e1 = elems1[i]
          e2 = elems2[i]
          e1.name == e2.name && e1.namespace_uri == e2.namespace_uri &&
            extract_identity(e1) == extract_identity(e2)
        end
      end

      # Record the positional pairing as :matched MatchResults,
      # descending per pair in recursive mode (match_trees' ordering
      # contract).
      def record_positional_matches(elems1, elems2, path, recursive:)
        elems1.each_index do |i|
          elem1 = elems1[i]
          elem_path = element_path(path, elem1)
          @matches << MatchResult.new(
            status: :matched,
            elem1: elem1,
            elem2: elems2[i],
            path: elem_path,
            pos1: i,
            pos2: i,
          )
          if recursive
            match_children(elem1.children, elems2[i].children, elem_path)
          end
        end
      end

      # Path segment for an element: expanded under a namespace,
      # bare otherwise.
      def element_path(path, elem)
        if elem.namespace_uri && !elem.namespace_uri.empty?
          path + ["{#{elem.namespace_uri}}#{elem.name}"]
        else
          path + [elem.name]
        end
      end

      # Match remaining elements by name and position
      def match_by_position(elems1, elems2, path, matched1, matched2,
                            recursive:)
        # Group by element name AND namespace_uri
        by_identity1 = elems1.group_by { |e| [e.name, e.namespace_uri] }
        by_identity2 = elems2.group_by { |e| [e.name, e.namespace_uri] }

        # Positions within these (already unmatched-filtered) lists —
        # elems.index(elem) was an O(n) scan per recorded match
        subset_positions1 = {}
        elems1.each_with_index { |e, i| subset_positions1[e] = i }
        subset_positions2 = {}
        elems2.each_with_index { |e, i| subset_positions2[e] = i }

        # For each name+namespace combination, match by position
        by_identity1.each do |identity, list1|
          next unless by_identity2.key?(identity)

          # Match pairs by position
          list2 = by_identity2[identity]
          name = identity[0] # Extract name from [name, namespace_uri] tuple
          namespace_uri = identity[1] # Extract namespace_uri

          [list1.length, list2.length].min.times do |i|
            elem1 = list1[i]
            elem2 = list2[i]

            next if matched1.include?(elem1) || matched2.include?(elem2)

            # Build path with namespace information for clarity
            elem_path_with_ns = if namespace_uri && !namespace_uri.empty?
                                  path + ["{#{namespace_uri}}#{name}"]
                                else
                                  path + [name]
                                end

            @matches << MatchResult.new(
              status: :matched,
              elem1: elem1,
              elem2: elem2,
              path: elem_path_with_ns,
              pos1: subset_positions1[elem1],
              pos2: subset_positions2[elem2],
            )
            matched1.add(elem1)
            matched2.add(elem2)

            # Recursively match children
            if recursive
              match_children(elem1.children, elem2.children, elem_path_with_ns)
            end
          end
        end
      end

      # Match remaining elements by class attribute (position-independent)
      # This handles cases where insertions shift positions but elements have class-based identity
      def match_by_class(elems1, elems2, path, matched1, matched2,
                         recursive:)
        # Build class maps for elements that have class attributes
        class_map1 = build_class_map(elems1)
        class_map2 = build_class_map(elems2)

        # Positions within these (still-unmatched-filtered) lists
        subset_positions1 = {}
        elems1.each_with_index { |e, i| subset_positions1[e] = i }
        subset_positions2 = {}
        elems2.each_with_index { |e, i| subset_positions2[e] = i }

        # Match by class attribute
        class_map1.each do |class_value, elem1|
          next if matched1.include?(elem1)
          next unless class_map2.key?(class_value)

          elem2 = class_map2[class_value]
          next if matched2.include?(elem2)

          # Only match if element names are the same
          next unless elem1.name == elem2.name
          next unless elem1.namespace_uri == elem2.namespace_uri

          # Build path with namespace information for clarity
          elem_path_with_ns = if elem1.namespace_uri && !elem1.namespace_uri.empty?
                                path + ["{#{elem1.namespace_uri}}#{elem1.name}"]
                              else
                                path + [elem1.name]
                              end

          @matches << MatchResult.new(
            status: :matched,
            elem1: elem1,
            elem2: elem2,
            path: elem_path_with_ns,
            pos1: subset_positions1[elem1],
            pos2: subset_positions2[elem2],
          )
          matched1.add(elem1)
          matched2.add(elem2)

          # Recursively match children
          if recursive
            match_children(elem1.children, elem2.children, elem_path_with_ns)
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

      # Build map of class attribute → element
      def build_class_map(elements)
        map = {}

        elements.each do |elem|
          class_attr = elem.attribute_nodes.find { |a| a.name == "class" }
          next unless class_attr

          # Use element name + class as key to handle multiple element types
          key = "#{elem.name}##{class_attr.value}"
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
