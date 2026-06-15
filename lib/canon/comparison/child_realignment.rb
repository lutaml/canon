# frozen_string_literal: true

module Canon
  module Comparison
    # Shared two-cursor walk over child arrays with noise-aware realignment.
    #
    # When positional pairing would match a noise node (whitespace-only
    # text or comment) against a content node, the walker treats the
    # noise node as a single-side gap: emits a diff for it and advances
    # only that cursor, so the next iteration aligns content against
    # content.
    #
    # Noise classification is delegated to +NodeInspector.noise_dimension_for+,
    # making the walk open for extension — new noise types only require
    # adding a branch there.
    #
    # The walk is parameterised by a diff emitter (a callable that
    # receives node1, node2, diff1, diff2, dimension) so both the HTML
    # comparator (DiffNodeBuilder.build) and the XML comparator
    # (comparator.add_difference) reuse the same cursor logic.
    module ChildRealignment
      class << self
        # Walk two child arrays, emitting diffs for noise nodes and
        # yielding matched content pairs.
        #
        # @param children1 [Array] Left-side children
        # @param children2 [Array] Right-side children
        # @param emitter [#call] Callable receiving
        #   (node1, node2, diff1, diff2, dimension)
        # @param emit_structural_orphans [Boolean] When true, trailing-edge
        #   non-noise orphans are emitted as +:element_structure+ diffs.
        #   HTML fragment path sets this to true (it has no separate
        #   length-mismatch step); XML path sets it to false (structural
        #   orphans are already recorded by +use_positional_comparison+).
        # @yield [child1, child2] Compare two matched content nodes.
        #   Must return a Comparison result constant.
        # @return [Symbol] Worst comparison result encountered
        def walk(children1, children2, emitter,
                 emit_structural_orphans: false)
          worst = Comparison::EQUIVALENT
          i = 0
          j = 0

          while i < children1.length || j < children2.length
            child1 = children1[i]
            child2 = children2[j]

            if child1.nil?
              result = emit_orphan(child2, :right, emitter,
                                   emit_structural_orphans)
              worst = result if result && result != Comparison::EQUIVALENT
              j += 1
              next
            elsif child2.nil?
              result = emit_orphan(child1, :left, emitter,
                                   emit_structural_orphans)
              worst = result if result && result != Comparison::EQUIVALENT
              i += 1
              next
            end

            dim1 = NodeInspector.noise_dimension_for(child1)
            dim2 = NodeInspector.noise_dimension_for(child2)

            if dim1 && !dim2
              result = emit_inline_noise(child1, child2, dim1, :left, emitter)
              worst = result unless result == Comparison::EQUIVALENT
              i += 1
              next
            elsif dim2 && !dim1
              result = emit_inline_noise(child1, child2, dim2, :right, emitter)
              worst = result unless result == Comparison::EQUIVALENT
              j += 1
              next
            end

            if block_given?
              child_result = yield(child1, child2)
              worst = child_result unless child_result == Comparison::EQUIVALENT
            end
            i += 1
            j += 1
          end

          worst
        end

        private

        # Emit a diff for an inline noise node that sits opposite a
        # content node.  Whitespace passes both nodes for context;
        # comments pass only the comment node.
        def emit_inline_noise(node_left, node_right, dimension, noise_side,
emitter)
          if dimension == :whitespace_adjacency
            emitter.call(node_left, node_right,
                         Comparison::UNEQUAL_TEXT_CONTENTS,
                         Comparison::UNEQUAL_TEXT_CONTENTS,
                         dimension)
            Comparison::UNEQUAL_TEXT_CONTENTS
          else
            n1 = noise_side == :left ? node_left : nil
            n2 = noise_side == :right ? node_right : nil
            emitter.call(n1, n2,
                         Comparison::MISSING_NODE,
                         Comparison::MISSING_NODE,
                         dimension)
            Comparison::UNEQUAL_ELEMENTS
          end
        end

        # Emit a diff for a trailing-edge orphan (one side exhausted).
        # Noise orphans are always emitted; structural orphans only when
        # +emit_structural+ is true.
        def emit_orphan(orphan, side, emitter, emit_structural)
          dim = NodeInspector.noise_dimension_for(orphan)
          if dim
            n1 = side == :left ? orphan : nil
            n2 = side == :right ? orphan : nil
            emitter.call(n1, n2,
                         Comparison::MISSING_NODE,
                         Comparison::MISSING_NODE,
                         dim)
            Comparison::UNEQUAL_ELEMENTS
          elsif emit_structural
            n1 = side == :left ? orphan : nil
            n2 = side == :right ? orphan : nil
            emitter.call(n1, n2,
                         Comparison::MISSING_NODE,
                         Comparison::MISSING_NODE,
                         :element_structure)
            Comparison::UNEQUAL_ELEMENTS
          end
        end
      end
    end
  end
end
