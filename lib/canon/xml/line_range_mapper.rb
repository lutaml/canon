# frozen_string_literal: true

require_relative "../pretty_printer/xml"

module Canon
  module Xml
    # Maps DOM elements to line ranges in pretty-printed XML
    #
    # This class builds a mapping between DOM elements and their corresponding
    # line numbers in pretty-printed XML output. This enables line-accurate
    # diff display that can highlight specific elements even when the XML
    # structure is complex.
    #
    # == How it works
    #
    # 1. Pretty-prints the XML with consistent indentation
    # 2. Traverses the DOM tree depth-first
    # 3. For each element, finds its opening and closing tags in the pretty-printed output
    # 4. Records the line range (start_line..end_line) for that element
    # 5. Returns a Hash mapping element → LineRange
    #
    # == Usage
    #
    #   mapper = LineRangeMapper.new(indent: 2)
    #   root = Canon::Xml::DataModel.from_xml(xml_string)
    #   line_map = mapper.build_map(root, xml_string)
    #
    #   # Look up line range for an element
    #   range = line_map[element]
    #   puts "Element spans lines #{range.start_line} to #{range.end_line}"
    #
    # == Line Range Format
    #
    # Each LineRange contains:
    # - start_line: First line of the element (0-indexed)
    # - end_line: Last line of the element (0-indexed)
    # - elem: Reference to the DOM element
    #
    class LineRangeMapper
      # Line range for an element
      LineRange = Struct.new(:start_line, :end_line, :elem) do
        def contains?(line_num)
          line_num >= start_line && line_num <= end_line
        end

        def length
          end_line - start_line + 1
        end
      end

      def initialize(indent: 2)
        @indent = indent
        @ranges = []
      end

      # Build line range map for a DOM tree
      #
      # @param root [Canon::Xml::Nodes::RootNode] DOM tree
      # @param xml_string [String] Original XML (for pretty-printing)
      # @return [Hash] Map of element => LineRange
      def build_map(root, xml_string)
        @ranges = []
        @map = {}

        # Pretty-print to get consistent formatting
        pretty_xml = Canon::PrettyPrinter::Xml.new(indent: @indent).format(xml_string)
        @lines = pretty_xml.split("\n")

        # Track current line number
        @current_line = 0

        # Build map recursively
        root.children.each do |child|
          map_node(child)
        end

        @map
      end

      private

      # Map a node to its line range
      def map_node(node)
        return unless node.node_type == :element

        # Find opening tag line
        opening_tag = find_opening_tag(node)
        return unless opening_tag

        start_line = opening_tag[:line]
        @current_line = start_line

        # Map children recursively
        node.children.each do |child|
          map_node(child)
        end

        # Find closing tag line
        closing_tag = find_closing_tag(node, start_line)
        if closing_tag
          @current_line = closing_tag[:line]
        end

        # Create range
        end_line = @current_line
        range = LineRange.new(start_line, end_line, node)
        @map[node] = range
        @ranges << range

        # Move to next line after this element
        @current_line = end_line + 1
      end

      # Find opening tag line for element
      def find_opening_tag(elem)
        tag_pattern = if elem.prefix && !elem.prefix.empty?
                        /<#{Regexp.escape(elem.prefix)}:#{Regexp.escape(elem.name)}[\s>\/]/
                      else
                        /<#{Regexp.escape(elem.name)}[\s>\/]/
                      end

        (@current_line...@lines.length).each do |i|
          line = @lines[i]
          if line.match?(tag_pattern)
            return { line: i, content: line }
          end
        end

        nil
      end

      # Find closing tag line for element
      def find_closing_tag(elem, start_line)
        tag_pattern = if elem.prefix && !elem.prefix.empty?
                        /<\/#{Regexp.escape(elem.prefix)}:#{Regexp.escape(elem.name)}>/
                      else
                        /<\/#{Regexp.escape(elem.name)}>/
                      end

        # Check if self-closing
        start_content = @lines[start_line]
        if start_content&.include?("/>")
          return { line: start_line, content: start_content }
        end

        # Find closing tag
        (start_line...@lines.length).each do |i|
          line = @lines[i]
          if line.match?(tag_pattern)
            return { line: i, content: line }
          end
        end

        { line: start_line, content: start_content }
      end
    end
  end
end
