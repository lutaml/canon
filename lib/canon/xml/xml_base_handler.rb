# frozen_string_literal: true

require "uri"

module Canon
  module Xml
    # Handler for xml:base fixup in document subsets
    # Implements RFC 3986 URI joining with C14N 1.1 modifications
    class XmlBaseHandler
      # Perform xml:base fixup on an element
      # Returns the fixed-up xml:base value or nil if no fixup needed
      def fixup_xml_base(element, omitted_ancestors)
        return nil if omitted_ancestors.empty?

        # Collect xml:base values from omitted ancestors
        base_values = collect_base_values(element, omitted_ancestors)
        return nil if base_values.empty?

        # Join the base values in reverse document order
        join_base_values(base_values)
      end

      private

      # Collect xml:base attribute values from element and omitted ancestors
      def collect_base_values(element, omitted_ancestors)
        values = []

        # Collect from omitted ancestors (in document order)
        omitted_ancestors.each do |ancestor|
          base_attr = ancestor.attribute_nodes.find(&:xml_base?)
          values << base_attr.value if base_attr
        end

        # Add element's own xml:base if present
        element_base = element.attribute_nodes.find(&:xml_base?)
        values << element_base.value if element_base

        values
      end

      # Join URI references per RFC 3986 with C14N 1.1 modifications
      def join_base_values(values)
        result = values.first

        values[1..].each do |ref|
          result = join_uri_references(result, ref)
        end

        result
      end

      # Join two URI references per RFC 3986 sections 5.2.1, 5.2.2, 5.2.4
      # with C14N 1.1 modifications
      def join_uri_references(base, ref)
        # Parse reference (ignore fragment per C14N 1.1)
        ref_parts = parse_uri(ref)

        # If ref has a scheme, return ref (without fragment)
        if ref_parts[:scheme]
          return remove_dot_segments(ref_parts[:path] || "")
        end

        # Parse base
        base_parts = parse_uri(base)

        # Build result
        result_parts = {}

        if ref_parts[:authority]
          result_parts[:authority] = ref_parts[:authority]
          result_parts[:path] = remove_dot_segments(ref_parts[:path] || "")
          result_parts[:query] = ref_parts[:query]
        else
          if ref_parts[:path].nil? || ref_parts[:path].empty?
            result_parts[:path] = base_parts[:path]
            result_parts[:query] = ref_parts[:query] || base_parts[:query]
          else
            if ref_parts[:path].start_with?("/")
              result_parts[:path] = remove_dot_segments(ref_parts[:path])
            else
              result_parts[:path] = merge_paths(base_parts[:path],
                                                ref_parts[:path])
              result_parts[:path] = remove_dot_segments(result_parts[:path])
            end
            result_parts[:query] = ref_parts[:query]
          end
          result_parts[:authority] = base_parts[:authority]
        end

        result_parts[:scheme] = base_parts[:scheme]

        # Reconstruct URI
        reconstruct_uri(result_parts)
      end

      # Parse URI into components
      def parse_uri(uri_str)
        parts = {}

        # Simple regex-based parsing
        if uri_str =~ %r{^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?}
          parts[:scheme] = Regexp.last_match(2)
          parts[:authority] = Regexp.last_match(4)
          parts[:path] = Regexp.last_match(5)
          parts[:query] = Regexp.last_match(7)
        end

        parts
      end

      # Merge paths per RFC 3986 section 5.2.3
      def merge_paths(base_path, ref_path)
        if base_path&.include?("/")
          base_path.sub(%r{/[^/]*$}, "/#{ref_path}")
        else
          ref_path
        end
      end

      # Remove dot segments per RFC 3986 section 5.2.4
      # with C14N 1.1 modifications
      def remove_dot_segments(path)
        input = path.dup
        output = ""

        # Replace trailing ".." with "../"
        input = input.sub(%r{/\.\.$}, "/../")

        while input.length.positive?
          # A: If input starts with "../" or "./"
          if input.start_with?("../")
            input[3..]
          elsif input.start_with?("./")
            input[2..]
          # B: If input starts with "/./" or is "/."
          elsif input.start_with?("/./")
            "/#{input[3..]}"
          elsif input == "/."
            "/"
          # C: If input starts with "/../" or is "/.."
          elsif input.start_with?("/../")
            "/#{input[4..]}"
            output = output.sub(%r{/[^/]*$}, "")
          elsif input == "/.."
            "/"
            output = output.sub(%r{/[^/]*$}, "")
          # D: If input is "." or ".."
          elsif [".", ".."].include?(input)
            ""
          # E: Move first path segment to output
          else
            if input.start_with?("/")
              seg_match = input.match(%r{^(/[^/]*)})
              seg = seg_match[1]
              input[seg.length..]
            else
              seg_match = input.match(/^([^\/]*)/)
              seg = seg_match[1]
              input = input[seg.length..]
            end
            output += seg
          end
        end

        # Replace multiple consecutive "/" with single "/"
        output = output.squeeze("/")

        # Append "/" to trailing ".."
        output += "/" if output.end_with?("/..")

        output
      end

      # Reconstruct URI from parts
      def reconstruct_uri(parts)
        result = ""

        result += "#{parts[:scheme]}:" if parts[:scheme]
        result += "//#{parts[:authority]}" if parts[:authority]
        result += parts[:path] if parts[:path]
        result += "?#{parts[:query]}" if parts[:query]

        result
      end
    end
  end
end
