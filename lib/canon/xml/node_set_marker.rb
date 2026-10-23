# frozen_string_literal: true

module Canon
  module Xml
    # Marks the XPath node-set on a data-model tree for both C14N
    # lanes (C14n and ExclusiveC14n): all nodes cleared, the matched
    # nodes and their descendants marked, the root always kept so
    # processing starts.
    module NodeSetMarker
      module_function

      # keep_root: the C14N subset lane pins the root into the set so
      # processing starts there (its selectors include it); the
      # exclusive corpus's selectors exclude the document element and
      # the output renders the included subtrees as fragments.
      def mark(root_node, matched, keep_root: true)
        mark_all(root_node, false)
        if matched.nil? || matched.empty?
          mark_all(root_node, true)
        else
          matched.each { |node| mark_node_and_descendants(node) }
          root_node.in_node_set = true if keep_root
        end
      end

      def mark_all(node, value)
        node.in_node_set = value
        node.children.each { |child| mark_all(child, value) }
      end

      def mark_node_and_descendants(node)
        node.in_node_set = true
        node.children.each { |child| mark_node_and_descendants(child) }
      end
    end
  end
end
