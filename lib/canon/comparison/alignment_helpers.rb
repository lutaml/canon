# frozen_string_literal: true

require "set"

module Canon
  module Comparison
    # Two-ended alignment helpers for locating orphans in child-list
    # comparisons.
    #
    # Used by both:
    # - +HtmlComparator#record_fragment_length_mismatch+ (top-level
    #   fragment children, see lutaml/canon#128)
    # - +XmlComparatorHelpers::ChildComparison#use_positional_comparison+
    #   (per-element children, see lutaml/canon#132)
    #
    # The shape: peel off the longest aligned prefix and the longest
    # aligned suffix between two child arrays; the gap between is the
    # set of genuinely-different children.  Falls back gracefully to
    # the surplus tail (or the whole longer array) when no alignment
    # exists.  Never produces *worse* output than naive zip.
    module AlignmentHelpers
      module_function

      # Identify the orphan region in +longer+ given the corresponding
      # +shorter+ child list.
      #
      # @param longer [Array] The longer child list
      # @param shorter [Array] The shorter child list
      # @return [Array] Orphan child nodes from +longer+
      def locate_orphans(longer, shorter)
        prefix = aligned_prefix_length(longer, shorter)
        suffix = aligned_suffix_length(longer, shorter, prefix)
        longer[prefix...(longer.length - suffix)]
      end

      # Two-array prefix length, scanning lock-step over the parallel
      # positions in +longer+ and +shorter+.  This is used by
      # +locate_orphans+ to identify the orphan region in +longer+,
      # so the prefix length is reported in *longer*'s coordinate
      # system: it is the index in +longer+ at which alignment first
      # breaks.
      def aligned_prefix_length(longer, shorter)
        i = 0
        i += 1 while i < shorter.length && nodes_align?(longer[i],
                                                        shorter[i])
        i
      end

      # Two-array suffix length, scanning from the end pair-by-pair.
      # Returned in +longer+'s coordinate system (number of trailing
      # elements that align with the trailing elements of +shorter+),
      # never crossing into the prefix region.
      def aligned_suffix_length(longer, shorter, prefix)
        i = 0
        while i < (shorter.length - prefix) &&
            nodes_align?(longer[longer.length - 1 - i],
                         shorter[shorter.length - 1 - i])
          i += 1
        end
        i
      end

      # Element-aware alignment: locate orphans while *ignoring*
      # whitespace-only text nodes during the scan.  Lock-step scan
      # advances past whitespace on either side independently, so that
      # asymmetric inter-sibling whitespace (a pretty-printed fixture
      # vs a compacted receiver, or vice versa) does not break the
      # alignment after the first whitespace mismatch.  See
      # lutaml/canon#132.
      #
      # The alignment is computed over the element-only skeletons of
      # both sides, then mapped back to the original positions.
      # Orphans = original positions of +longer+ that fall outside the
      # aligned regions in either coordinate system.  Whitespace text
      # nodes in the gap region surface as their own orphans; element
      # orphans are reported as elements; nothing is hidden.
      #
      # @param longer [Array] Longer child list
      # @param shorter [Array] Shorter child list
      # @return [Array] Orphan child nodes from +longer+
      def locate_orphans_skipping_whitespace(longer, shorter)
        long_idx = element_indices(longer)
        short_idx = element_indices(shorter)
        long_elems  = long_idx.map  { |i| longer[i]  }
        short_elems = short_idx.map { |i| shorter[i] }

        # Align element-only skeletons.
        prefix = aligned_prefix_length(long_elems, short_elems)
        suffix = aligned_suffix_length(long_elems, short_elems, prefix)

        # Map back: keep original-array positions that fall inside an
        # aligned element pair.  Everything else in +longer+ is an
        # orphan in this coordinate system.
        kept = Set.new
        prefix.times { |k| kept << long_idx[k] }
        suffix.times { |k| kept << long_idx[long_idx.length - 1 - k] }

        (0...longer.length).reject { |i| kept.include?(i) }.map do |i|
          longer[i]
        end
      end

      # Indices of element-typed children (non-whitespace text included
      # for now -- only whitespace-only text nodes are skipped, since
      # those are the noise the alignment needs to ignore).
      def element_indices(children)
        children.each_with_index.filter_map do |c, i|
          next i unless whitespace_only_text?(c)

          nil
        end
      end

      # Element-aware alignment that returns both the orphan list and
      # the aligned-position pairs in one pass.  Pairs preserve the
      # caller's original side ordering: the returned pairs are
      # +[children1[i], children2[j]]+ regardless of which side was
      # the longer one in the alignment scan.
      #
      # @param children1 [Array] First child list
      # @param children2 [Array] Second child list
      # @return [Hash] +{ orphans: [...], orphan_side: :first|:second,
      #   aligned_pairs: [[c1, c2], ...] }+
      def align_with_pairs(children1, children2)
        if children1.length >= children2.length
          longer  = children1
          shorter = children2
          orphan_side = :first
        else
          longer  = children2
          shorter = children1
          orphan_side = :second
        end

        long_idx  = element_indices(longer)
        short_idx = element_indices(shorter)
        long_elems  = long_idx.map  { |i| longer[i]  }
        short_elems = short_idx.map { |i| shorter[i] }

        prefix = aligned_prefix_length(long_elems, short_elems)
        suffix = aligned_suffix_length(long_elems, short_elems, prefix)

        # Aligned-element pairs in (longer, shorter) coordinates.
        long_paired_idx  = []
        short_paired_idx = []
        prefix.times do |k|
          long_paired_idx  << long_idx[k]
          short_paired_idx << short_idx[k]
        end
        suffix.times do |k|
          long_paired_idx  << long_idx[long_idx.length - 1 - k]
          short_paired_idx << short_idx[short_idx.length - 1 - k]
        end

        # Orphans = positions of +longer+ outside the aligned set.
        kept = long_paired_idx.to_set
        orphans = (0...longer.length).reject { |i| kept.include?(i) }
          .map { |i| longer[i] }

        # Pairs in (children1, children2) ordering.
        aligned_pairs = long_paired_idx.zip(short_paired_idx)
          .map do |li, si|
          if orphan_side == :first
            [longer[li], shorter[si]]
          else
            [shorter[si], longer[li]]
          end
        end

        { orphans: orphans, orphan_side: orphan_side,
          aligned_pairs: aligned_pairs }
      end

      # Whitespace-only text node test.  Used by element-aware
      # alignment to skip cosmetic whitespace during the scan.
      def whitespace_only_text?(node)
        return false unless node

        is_text = if node.respond_to?(:node_type) &&
            node.node_type.is_a?(Symbol)
                    node.node_type == :text
                  elsif node.respond_to?(:text?)
                    node.text?
                  else
                    false
                  end
        return false unless is_text

        text = if node.respond_to?(:value)
                 node.value
               elsif node.respond_to?(:content)
                 node.content
               else
                 ""
               end
        text.to_s.match?(/\A\s*\z/)
      end

      # Two nodes align for orphan-locating purposes when they have
      # the same node kind, the same name (for elements), and the
      # same attribute key set.  Shallow by design -- deep equality
      # would defeat the point of running the alignment to *locate*
      # a structural difference.
      def nodes_align?(node_a, node_b)
        return false unless node_a && node_b
        return false unless same_kind?(node_a, node_b)

        a_name = node_a.respond_to?(:name) ? node_a.name : nil
        b_name = node_b.respond_to?(:name) ? node_b.name : nil
        return false unless a_name == b_name

        node_attribute_keys(node_a) == node_attribute_keys(node_b)
      end

      # Two nodes are the same "kind" when both are elements, both are
      # text, both are comments, etc.  Uses +node_type+ when available
      # (Canon nodes), falling back to class equality (Nokogiri
      # nodes), so the helpers work across both DOM models.
      def same_kind?(node_a, node_b)
        if node_a.respond_to?(:node_type) &&
            node_b.respond_to?(:node_type) &&
            node_a.node_type.is_a?(Symbol) &&
            node_b.node_type.is_a?(Symbol)
          return node_a.node_type == node_b.node_type
        end

        node_a.instance_of?(node_b.class)
      end

      # Sorted attribute key list for a node, or [] for non-elements.
      def node_attribute_keys(node)
        return [] unless node.respond_to?(:attribute_nodes)

        node.attribute_nodes.map { |a| a.name.to_s }.sort
      end
    end
  end
end
