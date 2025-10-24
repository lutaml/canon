# frozen_string_literal: true

module Canon
  class DiffFormatter
    module ByObject
      # Base class for by-object diff formatters
      # Provides tree visualization for semantic differences
      class BaseFormatter
        attr_reader :use_color, :visualization_map

        def initialize(use_color: true, visualization_map: nil)
          @use_color = use_color
          @visualization_map = visualization_map ||
            Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP
        end

        # Format differences for display
        # @param differences [ComparisonResult, Array] ComparisonResult object or legacy Array
        # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
        # @return [String] Formatted output
        def format(differences, _format)
          # Handle both ComparisonResult (production) and Array (low-level tests)
          if differences.respond_to?(:equivalent?)
            # ComparisonResult object
            return success_message if differences.equivalent?

            diffs_array = differences.differences
          else
            # Legacy Array
            return success_message if differences.empty?

            diffs_array = differences
          end

          output = []
          output << colorize("Visual Diff:", :cyan, :bold)

          # Group differences by path for tree building
          tree = build_diff_tree(diffs_array)

          # Render tree
          output << render_tree(tree)

          output.join("\n")
        end

        # Factory method to create format-specific formatter
        def self.for_format(format, use_color: true, visualization_map: nil)
          case format
          when :xml, :html
            require_relative "xml_formatter"
            XmlFormatter.new(use_color: use_color,
                             visualization_map: visualization_map)
          when :json
            require_relative "json_formatter"
            JsonFormatter.new(use_color: use_color,
                              visualization_map: visualization_map)
          when :yaml
            require_relative "yaml_formatter"
            YamlFormatter.new(use_color: use_color,
                              visualization_map: visualization_map)
          else
            new(use_color: use_color, visualization_map: visualization_map)
          end
        end

        private

        # Generate success message
        def success_message
          emoji = @use_color ? "✅ " : ""
          message = "Files are semantically equivalent"
          colorize("#{emoji}#{message}\n", :green, :bold)
        end

        # Build a tree structure from differences
        def build_diff_tree(differences)
          tree = {}

          differences.each do |diff|
            # Handle both DiffNode and Hash formats
            if diff.is_a?(Hash) && diff.key?(:path)
              # Ruby object difference (Hash format)
              add_to_tree(tree, diff[:path], diff)
            elsif diff.is_a?(Canon::Diff::DiffNode)
              # DiffNode format - extract path from nodes
              path = extract_dom_path_from_diffnode(diff)
              add_to_tree(tree, path, diff)
            else
              # Legacy DOM difference (Hash format) - extract path from node
              path = extract_dom_path(diff)
              add_to_tree(tree, path, diff)
            end
          end

          tree
        end

        # Add a difference to the tree structure
        def add_to_tree(tree, path, diff)
          parts = path.to_s.split(/[.\[\]]/).reject(&:empty?)
          current = tree

          parts.each_with_index do |part, index|
            current[part] ||= {}
            if index == parts.length - 1
              current[part][:__diff__] = diff
            else
              current = current[part]
            end
          end
        end

        # Extract path from DOM node difference
        def extract_dom_path(diff)
          node = diff[:node1] || diff[:node2]
          return "" unless node

          parts = []
          current = node

          while current.respond_to?(:name)
            parts.unshift(current.name) if current.name
            current = current.parent if current.respond_to?(:parent)
          end

          parts.join(".")
        end

        # Extract path from DiffNode object
        def extract_dom_path_from_diffnode(diff_node)
          # Extract path from node1 or node2 in the DiffNode
          node = diff_node.node1 || diff_node.node2
          return diff_node.dimension.to_s unless node

          parts = []
          current = node

          while current.respond_to?(:name)
            parts.unshift(current.name) if current.name
            current = current.parent if current.respond_to?(:parent)
          end

          parts.empty? ? diff_node.dimension.to_s : parts.join(".")
        end

        # Render tree structure with box-drawing characters
        def render_tree(tree, prefix: "", is_last: true)
          output = []

          sorted_keys = tree.keys.reject { |k| k == :__diff__ }
          begin
            sorted_keys = sorted_keys.sort_by(&:to_s)
          rescue ArgumentError
            # If sorting fails, just use the keys as-is
          end

          sorted_keys.each_with_index do |key, index|
            is_last_item = (index == sorted_keys.length - 1)
            connector = is_last_item ? "└── " : "├── "
            continuation = is_last_item ? "    " : "│   "

            value = tree[key]
            diff = value[:__diff__] if value.is_a?(Hash)

            if diff
              # Render difference
              output << render_diff_node(key, diff, prefix, connector)
            else
              # Render intermediate path
              output << colorize("#{prefix}#{connector}#{key}:", :cyan)
              # Recurse into subtree
              if value.is_a?(Hash)
                output << render_tree(value, prefix: prefix + continuation,
                                             is_last: is_last_item)
              end
            end
          end

          output.join("\n")
        end

        # Render a single diff node - to be overridden by subclasses
        def render_diff_node(key, diff, prefix, connector)
          raise NotImplementedError,
                "Subclasses must implement render_diff_node"
        end

        # Colorize text if color is enabled
        def colorize(text, *colors)
          return text unless @use_color

          require "paint"
          "\e[0m#{Paint[text, *colors]}"
        end
      end
    end
  end
end
