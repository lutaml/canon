# frozen_string_literal: true

module Canon
  module Xml
    # XPath evaluation engine for C14N subset selection.
    #
    # Supports a focused subset of XPath 1.0 sufficient for W3C C14N
    # subset canonicalization:
    #
    # - Absolute paths: /root/child, /root/child[1]
    # - Descendant-or-self: //element, //ns:element
    # - Predicates: [1] (position), [@attr], [@attr='value']
    # - Wildcards: *
    # - Union: expr1 | expr2
    #
    # Not supported (not needed for C14N subset):
    # - Axes other than child and descendant-or-self
    # - Functions (last(), position(), etc.)
    # - Variables
    #
    class XPathEngine
      # Evaluate an XPath expression against a data model tree.
      #
      # @param root [Nodes::RootNode] Root of the data model tree
      # @param xpath [String] XPath expression
      # @return [Array<Node>] Matched nodes in document order
      def self.evaluate(root, xpath)
        new(root).evaluate(xpath)
      end

      def initialize(root)
        @root = root
      end

      # Evaluate an XPath expression and return matched nodes.
      #
      # @param xpath [String] XPath expression
      # @return [Array<Node>] Matched nodes in document order
      def evaluate(xpath)
        # Handle union operator (|)
        if xpath.include?("|")
          xpath.split("|").flat_map { |expr| evaluate(expr.strip) }.uniq
        else
          evaluate_path(xpath.strip)
        end
      end

      private

      def evaluate_path(xpath)
        if xpath.start_with?("//")
          # Descendant-or-self: anywhere in the tree
          evaluate_descendant(xpath[2..])
        elsif xpath.start_with?("/")
          # Absolute path
          evaluate_absolute(xpath[1..])
        else
          # Relative path — treat as descendant
          evaluate_descendant(xpath)
        end
      end

      def evaluate_absolute(path)
        return [] if path.empty?

        steps = parse_steps(path)
        return [] if steps.empty?

        # Start from root's children
        current_nodes = @root.children
        apply_steps(current_nodes, steps)
      end

      def evaluate_descendant(path)
        steps = parse_steps(path)
        return [] if steps.empty?

        # Collect all descendant element nodes
        all_elements = []
        collect_elements(@root, all_elements)

        # For each element, try to match the full path starting there
        result = []
        all_elements.each do |element|
          first_step = steps.first
          next unless step_matches?(element, first_step)

          if steps.length == 1
            result << element
          else
            remaining = steps[1..]
            matched = apply_steps(element.children, remaining)
            result.concat(matched)
          end
        end

        result.uniq
      end

      def collect_elements(node, result)
        node.children.each do |child|
          next unless child.is_a?(Nodes::ElementNode)

          result << child
          collect_elements(child, result)
        end
      end

      def apply_steps(nodes, steps)
        return nodes if steps.empty?

        step = steps.first
        remaining = steps[1..]

        matched = nodes.select { |n| step_matches?(n, step) }

        if remaining.empty?
          matched
        else
          matched.flat_map do |node|
            apply_steps(node.children, remaining)
          end
        end
      end

      def step_matches?(node, step)
        return false unless node.is_a?(Nodes::ElementNode)

        name_matches?(node, step[:name]) &&
          predicates_match?(node, step[:predicates])
      end

      def name_matches?(node, name)
        return true if name == "*"

        # Handle prefixed names (ns:element)
        if name.include?(":")
          prefix, local = name.split(":", 2)
          node.prefix == prefix && node.name == local
        else
          node.name == name
        end
      end

      def predicates_match?(node, predicates)
        return true if predicates.empty?

        predicates.all? { |pred| predicate_matches?(node, pred) }
      end

      def predicate_matches?(node, pred)
        case pred[:type]
        when :position
          # [1] — position among siblings with same name
          position_predicate?(node, pred[:value])
        when :attribute_exists
          # [@attr]
          node.attribute_nodes.any? { |a| a.local_name == pred[:name] }
        when :attribute_value
          # [@attr='value']
          node.attribute_nodes.any? do |a|
            a.local_name == pred[:name] && a.value == pred[:value]
          end
        else
          false
        end
      end

      def position_predicate?(node, position)
        siblings = node.parent&.children&.select { |n| n.is_a?(Nodes::ElementNode) && n.name == node.name } || []
        idx = siblings.index(node)
        idx && (idx + 1) == position
      end

      # Parse a path string into an array of steps.
      #
      # @param path [String] XPath path (without leading /)
      # @return [Array<Hash>] Array of { name:, predicates: }
      def parse_steps(path)
        steps = []
        scanner = StringScanner.new(path)

        until scanner.eos?
          scanner.skip(/\s+/)
          break if scanner.eos?

          # Skip /
          scanner.scan(%r{/})

          name = scan_name(scanner)
          break if name.nil?

          predicates = scan_predicates(scanner)

          steps << { name: name, predicates: predicates }
        end

        steps
      end

      def scan_name(scanner)
        scanner.scan(%r{[a-zA-Z_][\w:.-]*|\*})
      end

      def scan_predicates(scanner) # rubocop:disable Metrics/AbcSize
        predicates = []
        while scanner.scan(/\[/) # rubocop:disable Style/RedundantRegexpArgument
          scanner.skip(/\s*/)
          pred = scan_predicate(scanner)
          scanner.skip(/\s*/)
          scanner.scan(/\]/) # rubocop:disable Style/RedundantRegexpArgument
          predicates << pred if pred
        end
        predicates
      end

      def scan_predicate(scanner)
        if scanner.scan(/(\d+)/)
          { type: :position, value: scanner[1].to_i }
        elsif scanner.scan(/@/)
          name = scanner.scan(/[a-zA-Z_][\w.-]*/)

          if scanner.scan(/=/) # rubocop:disable Style/RedundantRegexpArgument
            # Remove surrounding quotes if present
            scanner.scan(/['"]/)
            value = scanner.scan(/[^'"\]]+/)
            scanner.scan(/['"]/)
            { type: :attribute_value, name: name, value: value }
          else
            { type: :attribute_exists, name: name }
          end
        end
      end
    end
  end
end
