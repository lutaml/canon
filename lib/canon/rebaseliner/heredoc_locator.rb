# frozen_string_literal: true

require "prism"
require_relative "heredoc_spec"

module Canon
  module Rebaseliner
    # Resolve a Prism AST node (the `expected` argument passed to a Canon
    # matcher) to a {HeredocSpec} that can be rewritten in-place, or to a
    # skip reason. Handles the metanorma-iso pattern of multiple sequential
    # assignments to the same local var via "most-recent assignment before
    # the matcher line" semantics.
    class HeredocLocator
      Result = Struct.new(:status, :heredoc_spec, keyword_init: true) do
        def rewritable?
          status == :ok
        end
      end

      # @param spec_path [String] absolute path of the spec file (passed through
      #   into any returned HeredocSpec)
      # @param source [String] full file source string
      # @param enclosing_block [Prism::Node] the `it`/`example` block node
      #   that contains the matcher invocation
      # @param expected_node [Prism::Node] the AST node passed as `expected`
      #   to the matcher
      # @param matcher_line [Integer] 1-indexed line of the matcher call;
      #   used as the upper bound when walking backward for the most recent
      #   local-var assignment
      def initialize(spec_path:, source:, enclosing_block:, expected_node:,
                     matcher_line:)
        @spec_path = spec_path
        @source = source
        @enclosing_block = enclosing_block
        @expected_node = expected_node
        @matcher_line = matcher_line
      end

      # @return [Result] :ok with a HeredocSpec, or a :skipped_* status
      def resolve
        resolve_node(@expected_node)
      end

      private

      def resolve_node(node)
        case node
        when Prism::StringNode
          resolve_string_node(node)
        when Prism::InterpolatedStringNode
          resolve_interpolated_string_node(node)
        when Prism::LocalVariableReadNode
          resolve_local_variable(node)
        else
          # CallNode, ConstantReadNode, IndexReadNode, etc.
          Result.new(status: :skipped_method_call)
        end
      end

      def resolve_string_node(node)
        opening = node.opening_loc&.slice
        return Result.new(status: :skipped_inline_string) unless heredoc_opening?(opening)

        spec = build_heredoc_spec(node, opening)
        Result.new(status: :ok, heredoc_spec: spec)
      end

      def resolve_interpolated_string_node(node)
        opening = node.opening_loc&.slice
        return Result.new(status: :skipped_inline_string) unless heredoc_opening?(opening)

        # Any interpolation part means we can't rewrite mechanically in v1.
        Result.new(status: :skipped_interpolation)
      end

      def resolve_local_variable(node)
        name = node.name
        most_recent = find_most_recent_assignment(@enclosing_block, name,
                                                  @matcher_line)
        return Result.new(status: :skipped_cross_file) unless most_recent

        resolve_node(most_recent.value)
      end

      # Walk all statements inside the enclosing block recursively and
      # collect every LocalVariableWriteNode whose name matches and whose
      # line is strictly before `matcher_line`. Return the one with the
      # greatest line number.
      def find_most_recent_assignment(block_node, name, matcher_line)
        candidates = []
        walk(block_node) do |child|
          next unless child.is_a?(Prism::LocalVariableWriteNode)
          next unless child.name == name
          next unless child.location.start_line < matcher_line

          candidates << child
        end
        candidates.max_by { |c| c.location.start_line }
      end

      def walk(node, &block)
        return unless node.respond_to?(:child_nodes)

        node.child_nodes.each do |child|
          next if child.nil?

          yield child
          walk(child, &block)
        end
      end

      def heredoc_opening?(opening)
        opening&.start_with?("<<")
      end

      def heredoc_style(opening)
        case opening
        when /\A<<~/ then :squiggly
        when /\A<<-/ then :dash
        else :strict
        end
      end

      def build_heredoc_spec(node, opening)
        content_loc = node.content_loc
        closing_loc = node.closing_loc
        style = heredoc_style(opening)
        terminator_indent = closing_loc.start_column

        HeredocSpec.new(
          spec_path: @spec_path,
          source: @source,
          style: style,
          content_start_offset: content_loc.start_offset,
          content_end_offset: content_loc.end_offset,
          terminator_indent: terminator_indent,
        )
      end
    end
  end
end
