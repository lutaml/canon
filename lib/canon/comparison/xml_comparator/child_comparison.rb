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
            children1 = comparator.send(:filter_children, node1.children, opts)
            children2 = comparator.send(:filter_children, node2.children, opts)

            # Quick check: if both have no children, they're equivalent
            return Comparison::EQUIVALENT if children1.empty? && children2.empty?

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
            require_relative "../../xml/element_matcher"
            require_relative "../../xml/nodes/root_node"

            # Create temporary RootNode wrappers
            temp_root1 = Canon::Xml::Nodes::RootNode.new
            temp_root1.instance_variable_set(:@children, children1.dup)

            temp_root2 = Canon::Xml::Nodes::RootNode.new
            temp_root2.instance_variable_set(:@children, children2.dup)

            matcher = Canon::Xml::ElementMatcher.new
            matches = matcher.match_trees(temp_root1, temp_root2)

            # Filter matches to only include direct children
            matches = matches.select do |m|
              (m.elem1.nil? || children1.include?(m.elem1)) &&
                (m.elem2.nil? || children2.include?(m.elem2))
            end

            # If no matches and children exist, they're all different
            if matches.empty? && (!children1.empty? || !children2.empty?)
              comparator.send(:add_difference, parent_node, parent_node,
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
                    comparator.send(:add_difference, match.elem1, match.elem2,
                                    "position #{match.pos1}", "position #{match.pos2}",
                                    :element_position, opts, differences)
                    all_equivalent = false if position_behavior == :strict
                  end
                end

                # Compare the matched elements for content/attribute differences
                result = comparator.send(:compare_nodes, match.elem1, match.elem2,
                                         child_opts, child_opts, diff_children, differences)
                all_equivalent = false unless result == Comparison::EQUIVALENT

              when :deleted
                # Element present in first tree but not second
                comparator.send(:add_difference, match.elem1, nil,
                                Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                :element_structure, opts, differences)
                all_equivalent = false

              when :inserted
                # Element present in second tree but not first
                comparator.send(:add_difference, nil, match.elem2,
                                Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                :element_structure, opts, differences)
                all_equivalent = false
              end
            end

            all_equivalent ? Comparison::EQUIVALENT : Comparison::UNEQUAL_ELEMENTS
          end

          # Use simple positional comparison for children
          def use_positional_comparison(children1, children2, parent_node, comparator,
                                        opts, child_opts, diff_children, differences)
            # Length check
            unless children1.length == children2.length
              dimension = determine_dimension_for_mismatch(children1,
                                                           children2, comparator)

              # Skip creating parent-level difference for comments when comments: :ignore
              # The child comparison will handle the comment vs element comparison
              # This avoids creating duplicate differences
              match_opts = opts[:match_opts]
              unless dimension == :comments && match_opts && match_opts[:comments] == :ignore
                comparator.send(:add_difference, parent_node, parent_node,
                                Comparison::MISSING_NODE, Comparison::MISSING_NODE,
                                dimension, opts, differences)
              end
              # Continue comparing children to find deeper differences like attribute values
              # Use zip to compare up to the shorter length
            end

            # Compare children pairwise by position
            result = Comparison::EQUIVALENT
            children1.zip(children2).each do |child1, child2|
              # Skip if one is nil (due to different lengths)
              next if child1.nil? || child2.nil?

              child_result = comparator.send(:compare_nodes, child1, child2,
                                             child_opts, child_opts, diff_children, differences)
              result = child_result unless child_result == Comparison::EQUIVALENT
            end

            result
          end

          # Determine dimension for length mismatch
          def determine_dimension_for_mismatch(children1, children2, comparator)
            dimension = :text_content # default

            # Compare position by position to find first difference
            max_len = [children1.length, children2.length].max
            (0...max_len).each do |i|
              if i >= children1.length
                # Extra child in children2
                dimension = comparator.send(:determine_node_dimension,
                                            children2[i])
                break
              elsif i >= children2.length
                # Extra child in children1
                dimension = comparator.send(:determine_node_dimension,
                                            children1[i])
                break
              elsif !comparator.send(:same_node_type?, children1[i],
                                     children2[i])
                # Different node types at same position
                dimension = comparator.send(:determine_node_dimension,
                                            children1[i])
                break
              end
            end

            dimension
          end
        end
      end
    end
  end
end
