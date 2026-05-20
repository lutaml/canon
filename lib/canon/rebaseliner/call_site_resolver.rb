# frozen_string_literal: true

require "prism"

module Canon
  module Rebaseliner
    # Parse a spec file with Prism, locate the matcher invocation at a
    # specific line, and return enough context (matcher AST + enclosing
    # `it`/`example` block + full source) for the locator and rewriter to
    # work against.
    class CallSiteResolver
      Result = Struct.new(
        :source,            # full file source (UTF-8 string)
        :matcher_call_node, # Prism::CallNode for `be_*_equivalent_to(arg)`
        :expected_node,     # the `expected` argument node (first positional arg)
        :enclosing_block,   # the `it`/`example` block containing the call
        :matcher_line,      # 1-indexed line number of the matcher invocation
        keyword_init: true,
      )

      MATCHER_NAMES = %i[
        be_equivalent_to
        be_xml_equivalent_to
        be_html_equivalent_to
        be_json_equivalent_to
        be_yaml_equivalent_to
        be_serialization_equivalent_to
      ].freeze

      # @param spec_path [String]
      # @param line [Integer] 1-indexed line number where the matcher
      #   invocation lives (typically from `caller_locations`)
      # @return [Result, nil] nil if the file can't be parsed or no matcher
      #   call is found at that line
      def self.resolve(spec_path:, line:)
        source = File.read(spec_path)
        parse_result = Prism.parse(source)
        return nil unless parse_result.success?

        new(source: source,
            root: parse_result.value,
            line: line).resolve
      end

      def initialize(source:, root:, line:)
        @source = source
        @root = root
        @line = line
      end

      def resolve
        call_node = find_matcher_call(@root)
        return nil unless call_node

        expected = call_node.arguments&.arguments&.first
        return nil unless expected

        enclosing = find_enclosing_block(@root, call_node)
        return nil unless enclosing

        Result.new(
          source: @source,
          matcher_call_node: call_node,
          expected_node: expected,
          enclosing_block: enclosing,
          matcher_line: call_node.location.start_line,
        )
      end

      private

      # Locate a CallNode whose method name is one of MATCHER_NAMES and
      # whose location encompasses the target line.
      def find_matcher_call(root)
        match = nil
        walk(root) do |node|
          next unless node.is_a?(Prism::CallNode)
          next unless MATCHER_NAMES.include?(node.name)

          loc = node.location
          next unless loc.start_line <= @line && loc.end_line >= @line

          # Prefer the narrowest enclosing match (innermost matcher).
          if match.nil? ||
             (loc.end_line - loc.start_line) <
             (match.location.end_line - match.location.start_line)
            match = node
          end
        end
        match
      end

      # Locate the enclosing `it { ... }` / `example { ... }` block. RSpec
      # uses `it("...") do ... end` which Prism parses as a CallNode with
      # an attached BlockNode. The BlockNode is the body we want.
      def find_enclosing_block(root, target_call)
        candidates = []
        walk(root) do |node|
          next unless node.is_a?(Prism::CallNode)
          next if node.block.nil?
          next unless %i[it example specify focus].include?(node.name)

          loc = node.location
          target_loc = target_call.location
          next unless loc.start_line <= target_loc.start_line &&
                      loc.end_line >= target_loc.end_line

          candidates << node.block
        end
        # Innermost wins.
        candidates.min_by { |b| b.location.end_line - b.location.start_line }
      end

      def walk(node, &block)
        return unless node

        yield node
        return unless node.respond_to?(:child_nodes)

        node.child_nodes.each do |child|
          walk(child, &block) unless child.nil?
        end
      end
    end
  end
end
