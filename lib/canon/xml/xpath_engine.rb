# frozen_string_literal: true

require "strscan"

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
    # - Self and parent steps: ., ..
    # - Attribute steps: @attr (selects the attribute node; per C14N
    #   law it renders only when its owner element is in the node-set,
    #   so @attr/.. is the productive form — XPath 1.0 section 2.2
    #   names the owner element)
    #
    # Not supported (not needed for C14N subset):
    # - Axes other than child, parent, self, descendant-or-self
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
        elsif xpath.start_with?("./")
          # Document-rooted self step: the subset context is the
          # document, so ./rest resolves from the root like /rest
          evaluate_absolute(xpath[2..])
        else
          # Relative path — treat as descendant
          evaluate_descendant(xpath)
        end
      end

      def evaluate_absolute(path)
        return [] if path.empty?

        steps = parse_steps(path)
        return [] if steps.empty?

        # Start from root's children; the first element step filters
        # this entry set directly
        apply_steps(@root.children, steps, descend_first: false)
      end

      def evaluate_descendant(path)
        steps = parse_steps(path)
        return [] if steps.empty?

        # ./ is transparent on the relative law: the subset context is
        # the document, so ./rest searches descendants like rest
        steps.shift while steps.first&.dig(:type) == :self
        return [] if steps.empty?

        # Collect all descendant element nodes
        all_elements = []
        collect_elements(@root, all_elements)

        first_step = steps.first
        remaining = steps[1..]

        context =
          case first_step[:type]
          when :attribute
            # //@attr — every matching attribute in the tree
            all_elements.flat_map do |element|
              attribute_matches(element, first_step)
            end
          when :parent
            return [] # no meaningful parents above descendants
          else
            all_elements.select do |element|
              step_matches?(element, first_step)
            end
          end
        return context.uniq if remaining.empty?

        # The remaining steps run from the matches: element steps
        # descend (block semantics), axis steps apply to the nodes
        # themselves
        apply_steps(context, remaining, descend_first: true).uniq
      end

      def collect_elements(node, result)
        node.children.each do |child|
          next unless child.is_a?(Nodes::ElementNode)

          result << child
          collect_elements(child, result)
        end
      end

      # Linear context model: each step transforms the current node
      # set. Element steps filter one level down from the context
      # (block semantics — the first step filters the entry set
      # itself); parent/self/attribute steps are context steps and
      # operate on the nodes themselves.
      def apply_steps(nodes, steps, descend_first:)
        steps.reduce(nodes) do |current, step|
          break [] if current.empty?

          if element_step?(step)
            level = descend_first ? descend(current) : current
            current = level.select { |n| step_matches?(n, step) }.uniq
          else
            current = axis_apply(current, step)
          end
          descend_first = true
          current
        end
      end

      def element_step?(step)
        step[:type] == :element
      end

      def descend(nodes)
        nodes.flat_map do |n|
          next [] if n.is_a?(Nodes::AttributeNode)

          n.children
        end
      end

      # Context steps: navigate from the nodes themselves.
      def axis_apply(nodes, step)
        case step[:type]
        when :parent
          nodes.filter_map(&:parent).uniq
        when :self
          nodes
        when :attribute
          nodes.grep(Nodes::ElementNode)
            .flat_map { |el| attribute_matches(el, step) }.uniq
        end
      end

      def attribute_matches(element, step)
        element.attribute_nodes.select do |a|
          attr_name_matches?(a, step[:name])
        end
      end

      def step_matches?(node, step)
        return false unless node.is_a?(Nodes::ElementNode)

        name_matches?(node, step[:name]) &&
          predicates_match?(node, step[:predicates])
      end

      def attr_name_matches?(attr, name)
        return true if name == "*"

        if name.include?(":")
          prefix, local = name.split(":", 2)
          attr.prefix == prefix && attr.name == local
        else
          attr.name == name
        end
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
        siblings = node.parent&.children&.select do |n|
          n.is_a?(Nodes::ElementNode) && n.name == node.name
        end || []
        idx = siblings.index(node)
        idx && (idx + 1) == position
      end

      # Parse a path string into an array of steps.
      #
      # @param path [String] XPath path (without leading /)
      # @return [Array<Hash>] Array of { type:, name:, predicates: }
      def parse_steps(path)
        steps = []
        scanner = StringScanner.new(path)

        until scanner.eos?
          scanner.skip(/\s+/)
          break if scanner.eos?

          # Skip /
          scanner.skip(%r{/})
          scanner.skip(/\s+/)

          if scanner.scan("..")
            steps << { type: :parent, name: nil, predicates: [] }
            next
          elsif scanner.scan(".")
            steps << { type: :self, name: nil, predicates: [] }
            next
          elsif scanner.scan(/@/)
            name = scanner.scan(/[a-zA-Z_][\w.-]*/)
            steps << { type: :attribute, name: name, predicates: [] }
            next
          end

          name = scan_name(scanner)
          break if name.nil?

          predicates = scan_predicates(scanner)

          steps << { type: :element, name: name, predicates: predicates }
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
