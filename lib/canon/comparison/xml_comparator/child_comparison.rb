# frozen_string_literal: true

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Child comparison service for XML nodes
      #
      # Handles comparison of child nodes using both semantic matching (ElementMatcher)
      # and simple positional comparison. Delegates back to the comparator for
      # individual node comparisons.
      #
      # This module encapsulates the complex child comparison logic, making the
      # main XmlComparator cleaner and more maintainable.
      module ChildComparison
        class << self
          # Compare children of two nodes using semantic matching
          #
          # Uses ElementMatcher to pair children semantically (by identity attributes
          # or position), then compares matched pairs and detects position changes.
          #
          # @param node1 [Object] First parent node
          # @param node2 [Object] Second parent node
          # @param comparator [XmlComparator] The comparator instance for delegation
          # @param opts [Hash] Comparison options
          # @param child_opts [Hash] Options for child comparison
          # @param diff_children [Boolean] Whether to diff children
          # @param differences [Array] Array to collect differences
          # @return [Integer] Comparison result code
          def compare(node1, node2, comparator, opts, child_opts,
                      diff_children, differences)
            # FAST PATH: Object identity - same object means equivalent children
            return Comparison::EQUIVALENT if node1.equal?(node2)

            # Apply side-specific pretty-print heuristic when either flag is set:
            # pretty_printed_expected → drop \n-starting whitespace nodes from node1
            # pretty_printed_received → drop \n-starting whitespace nodes from node2
            # The ephemeral _pretty_print_side_active flag is consumed by node_excluded?
            # and must NOT be forwarded into recursive compare_nodes calls.
            opts1 = XmlNodeComparison.opts_for_side(opts, :expected)
            opts2 = XmlNodeComparison.opts_for_side(opts, :received)

            children1 = comparator.filter_children(node1.children, opts1)
            children2 = comparator.filter_children(node2.children, opts2)

            # Quick check: if both have no children, they're equivalent
            return Comparison::EQUIVALENT if children1.empty? && children2.empty?

            # FAST PATH: Identical children arrays mean equivalent subtrees
            return Comparison::EQUIVALENT if children1.equal?(children2)

            # Check if we can use ElementMatcher (requires Canon::Xml::DataModel nodes)
            if can_use_element_matcher?(children1, children2)
              use_element_matcher_comparison(children1, children2, node1, comparator,
                                             opts, child_opts, diff_children, differences)
            else
              use_positional_comparison(children1, children2, node1, comparator,
                                        opts, child_opts, diff_children, differences)
            end
          end

          private

          # Check if ElementMatcher can be used for these children
          #
          # ElementMatcher expects Canon::Xml::DataModel nodes with .node_type
          # method that returns symbols, and only works with element nodes.
          def can_use_element_matcher?(children1, children2)
            !children1.empty? && !children2.empty? &&
              children1.all? do |c|
                c.is_a?(Canon::Xml::Node) && c.node_type == :element
              end &&
              children2.all? { |c| c.is_a?(Canon::Xml::Node) && c.node_type == :element }
          end

          # Use ElementMatcher for semantic comparison
          def use_element_matcher_comparison(children1, children2, parent_node, comparator,
                                             opts, child_opts, diff_children, differences)
            # Create temporary RootNode wrappers
            temp_root1 = Canon::Xml::Nodes::RootNode.new
            temp_root1.children = children1.dup

            temp_root2 = Canon::Xml::Nodes::RootNode.new
            temp_root2.children = children2.dup

            matcher = Canon::Xml::ElementMatcher.new
            matches = matcher.match_trees(temp_root1, temp_root2)

            # Filter matches to only include direct children
            matches = matches.select do |m|
              (m.elem1.nil? || children1.include?(m.elem1)) &&
                (m.elem2.nil? || children2.include?(m.elem2))
            end

            # If no matches and children exist, they're all different
            if matches.empty? && (!children1.empty? || children2.empty?)
              comparator.add_difference(parent_node, parent_node,
                                        Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                        :text_content, opts, differences)
              return Comparison::UNEQUAL_ELEMENTS
            end

            process_matches(matches, children1, children2, parent_node, comparator,
                            opts, child_opts, diff_children, differences)
          end

          # Process ElementMatcher results
          def process_matches(matches, _children1, _children2, _parent_node, comparator,
                             opts, child_opts, diff_children, differences)
            all_equivalent = true

            matches.each do |match|
              case match.status
              when :matched
                # Check if element position changed
                if match.position_changed?
                  match_opts = opts[:match_opts]
                  position_behavior = match_opts[:element_position] || :strict

                  # Only create DiffNode if element_position is not :ignore
                  if position_behavior != :ignore
                    comparator.add_difference(match.elem1, match.elem2,
                                              "position #{match.pos1}", "position #{match.pos2}",
                                              :element_position, opts, differences)
                    all_equivalent = false if position_behavior == :strict
                  end
                end

                # Compare the matched elements for content/attribute differences
                result = comparator.compare_nodes(match.elem1, match.elem2,
                                                  child_opts, child_opts, diff_children, differences)
                all_equivalent = false unless result == Comparison::EQUIVALENT

              when :deleted
                # Element present in first tree but not second
                comparator.add_difference(match.elem1, nil,
                                          Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                          :element_structure, opts, differences)
                all_equivalent = false

              when :inserted
                # Element present in second tree but not first
                comparator.add_difference(nil, match.elem2,
                                          Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                          :element_structure, opts, differences)
                all_equivalent = false
              end
            end

            all_equivalent ? Comparison::EQUIVALENT : Comparison::UNEQUAL_ELEMENTS
          end

          # Use simple positional comparison for children, with
          # noise-aware re-alignment via ChildRealignment. When the
          # children arrays differ in length, a pre-walk step records
          # structural orphans (or suppresses them when the length
          # difference is fully explained by noise nodes). The shared
          # walk then handles noise realignment and content comparison.
          # See lutaml/canon#137 (whitespace) and #144 (comments).
          def use_positional_comparison(
            children1, children2, parent_node, comparator,
            opts, child_opts, diff_children, differences
          )
            has_mismatch = false

            # Length check
            unless children1.length == children2.length
              has_mismatch = true

              noise_asymmetric = asymmetric_noise_explains_length_diff?(
                children1, children2
              )

              if noise_asymmetric
                dimension = nil
                mismatched_children = []
              else
                dimension = determine_dimension_for_mismatch(
                  children1, children2, comparator
                )
                mismatched_children, children1, children2 =
                  determine_mismatch_children(
                    children1, children2, comparator
                  )
              end

              if mismatched_children.empty?
                unless noise_asymmetric
                  comparator.add_difference(parent_node, parent_node,
                                            Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                            dimension, opts, differences)
                end
              else
                mismatched_children.each do |child|
                  child_dim = comparator.determine_node_dimension(child)
                  if children1.length > children2.length
                    comparator.add_difference(child, nil,
                                              Comparison::MISSING_NODE,
                                              Comparison::MISSING_NODE,
                                              child_dim, opts, differences)
                  else
                    comparator.add_difference(nil, child,
                                              Comparison::MISSING_NODE,
                                              Comparison::MISSING_NODE,
                                              child_dim, opts, differences)
                  end
                end
              end
            end

            result = has_mismatch ? Comparison::UNEQUAL_ELEMENTS : Comparison::EQUIVALENT

            emitter = xml_diff_emitter(comparator, opts, differences)
            walk_result = ChildRealignment.walk(children1, children2,
                                                emitter) do |c1, c2|
              comparator.compare_nodes(c1, c2, child_opts, child_opts,
                                       diff_children, differences)
            end
            result = walk_result unless walk_result == Comparison::EQUIVALENT
            result
          end

          # Build a diff emitter for the XML comparator path that
          # delegates to comparator.add_difference.
          def xml_diff_emitter(comparator, opts, differences)
            proc do |n1, n2, d1, d2, dim|
              comparator.add_difference(n1, n2, d1, d2, dim, opts, differences)
            end
          end

          # True when the length difference is fully explained by
          # asymmetric noise nodes (whitespace-only text and/or comments).
          def asymmetric_noise_explains_length_diff?(children1, children2)
            signal1 = children1.reject { |c| NodeInspector.noise_node?(c) }
            signal2 = children2.reject { |c| NodeInspector.noise_node?(c) }
            signal1.length == signal2.length
          end

          # Determine dimension for length mismatch
          def determine_dimension_for_mismatch(children1, children2, comparator)
            dimension = :text_content # default

            # Compare position by position to find first difference
            max_len = [children1.length, children2.length].max
            (0...max_len).each do |i|
              if i >= children1.length
                # Extra child in children2
                dimension = comparator.determine_node_dimension(children2[i])
                break
              elsif i >= children2.length
                # Extra child in children1
                dimension = comparator.determine_node_dimension(children1[i])
                break
              elsif !comparator.same_node_type?(children1[i], children2[i])
                # Different node types at same position
                # Check both nodes - if either is a comment, use :comments dimension
                dim1 = comparator.determine_node_dimension(children1[i])
                dim2 = comparator.determine_node_dimension(children2[i])
                dimension = [dim1, dim2].include?(:comments) ? :comments : dim1
                break
              end
            end

            dimension
          end

          # Determine mismatch children
          def determine_mismatch_children(children1, children2, _comparator)
            mismatch_children = []

            first_set_longer = children1.length > children2.length
            larger_set = children2
            smaller_set = children1
            if first_set_longer
              larger_set = children1
              smaller_set = children2
            end

            smaller_set_names = smaller_set.filter_map do |c|
              next nil unless c.is_a?(Canon::Xml::Node) || Canon::XmlParsing.xml_node?(c)
              # Exclude generic node-type names (e.g. "#text") that are
              # shared by all text nodes and cannot be used for matching.
              next nil if c.name.start_with?("#")

              c.name
            end

            new_larger_set = []
            max_len = larger_set.length
            (0...max_len).each do |i|
              if mismatch_children.empty? && smaller_set[i].nil?
                # If the smaller set has no child at this position,
                # consider it a mismatch
                mismatch_children << larger_set[i]
              elsif (larger_set[i].is_a?(Canon::Xml::Node) ||
                     Canon::XmlParsing.xml_node?(larger_set[i])) &&
                  !larger_set[i].name.start_with?("#") &&
                  !smaller_set_names.include?(larger_set[i].name)
                # If the name of the node is not found in the smaller set,
                # consider it a mismatch. Skip nodes with generic names
                # starting with "#" (e.g. "#text") since those names are
                # shared by all nodes of that type and not useful for matching.
                mismatch_children << larger_set[i]
              else
                new_larger_set << larger_set[i]
              end
            end

            if first_set_longer
              [mismatch_children, new_larger_set, smaller_set]
            else
              [mismatch_children, smaller_set, new_larger_set]
            end
          end
        end
      end
    end
  end
end
