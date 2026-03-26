# frozen_string_literal: true

module Canon
  module Diff
    # Detects if differences between lines are formatting-only
    # (whitespace, line breaks) with no semantic content changes
    class FormattingDetector
      # Detect if two lines differ only in formatting
      #
      # @param line1 [String, nil] First line to compare
      # @param line2 [String, nil] Second line to compare
      # @return [Boolean] true if lines differ only in formatting
      def self.formatting_only?(line1, line2)
        # If both are nil or empty, not a formatting diff (no difference)
        return false if blank?(line1) && blank?(line2)

        # If only one is blank, it's not just formatting
        return false if blank?(line1) || blank?(line2)

        # Compare normalized versions
        normalize_for_comparison(line1) == normalize_for_comparison(line2)
      end

      # Aggressive normalization for formatting comparison.
      # Collapses whitespace, decodes entities, normalizes attribute order,
      # and strips tag-delimiter whitespace.
      #
      # @param line [String, nil] Line to normalize
      # @return [String] Normalized line
      def self.normalize_for_comparison(line)
        return "" if line.nil?

        # Decode XML entities so &#x2014; and — compare as equal
        decoded = decode_xml_entities(line)

        # Collapse all whitespace (spaces, tabs, newlines) to single space
        # Avoid regex to prevent ReDoS vulnerability - use String methods
        normalized = decoded.strip.tr("\t\n\r\f\v", " ").squeeze(" ")

        # Normalize attribute order within tags.
        # For each tag (e.g., <std-id type="dated" id="foo">), sort attributes
        # so that attribute-order-only differences are treated as formatting.
        normalized = normalize_attribute_order(normalized)

        # Normalize whitespace around tag delimiters
        # Remove spaces before > and after < (avoid regex for ReDoS safety)
        normalize_attribute_order(normalized).gsub(" >", ">").gsub("< ", "<")
      end

      # Check if a line is blank (nil or whitespace-only)
      #
      # @param line [String, nil] Line to check
      # @return [Boolean] true if blank
      def self.blank?(line)
        line.nil? || line.strip.empty?
      end

      # Detect if a block of consecutive line changes is formatting-only.
      # Joins old and new parts with spaces and compares as a whole.
      # Handles multi-line tag wrapping (e.g., a tag on 2 lines vs 1 line).
      #
      # @param old_parts [Array<String>] Old line contents in the block
      # @param new_parts [Array<String>] New line contents in the block
      # @return [Boolean] true if the joined content differs only in formatting
      def self.formatting_block?(old_parts, new_parts)
        return false if old_parts.empty? || new_parts.empty?

        formatting_only?(old_parts.join(" "), new_parts.join(" "))
      end

      # Find the largest formatting-only prefix within old/new parts.
      # Tries all (old_end, new_end) combinations and returns the one
      # with the most old parts. Handles mixed-element blocks where
      # the first element is formatting but later elements are not.
      #
      # @param old_parts [Array<String>] Old line contents
      # @param new_parts [Array<String>] New line contents
      # @return [Hash, nil] { old_end:, new_end: } or nil
      def self.formatting_prefix(old_parts, new_parts)
        best = nil

        (1..old_parts.length).each do |old_end|
          (1..new_parts.length).each do |new_end|
            if formatting_only?(old_parts[0...old_end].join(" "),
                                new_parts[0...new_end].join(" "))
              best = { old_end: old_end, new_end: new_end }
            end
          end
        end

        best
      end

      # Decode XML entity references for comparison.
      # Delegates to XmlEntityDecoder (self-contained, no circular dependency).
      #
      # @param text [String] Text with potential entity references
      # @return [String] Text with entities decoded
      def self.decode_xml_entities(text)
        return text unless text.include?("&")

        require_relative "../tree_diff/core/xml_entity_decoder"
        Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(text)
      end

      # Attribute names whose values are case-insensitive per XML/XHTML specs.
      # Per the XML specification, the encoding declaration value is
      # case-insensitive (e.g., "UTF-8" equals "utf-8").
      # The standalone declaration in XML 1.1 is also case-insensitive.
      CASE_INSENSITIVE_ATTRS = %w[encoding standalone].freeze
      QUOTE_CHARS = ["\"", "'"].freeze
      SKIP_CHARS = [" ", "="].freeze

      # Normalize attribute order within XML tags so that
      # <elem b="2" a="1"> compares equal to <elem a="1" b="2">.
      # Uses iterative string scanning (no regex) for ReDoS safety.
      #
      # @param text [String] Text containing XML tags
      # @return [String] Text with sorted attributes in each tag
      def self.normalize_attribute_order(text)
        result = String.new(capacity: text.length)
        i = 0

        while i < text.length
          if text[i] == "<"
            # Handle processing instruction <?...?>, comment <!--...-->,
            # and regular tags
            new_i, tag_output = process_tag(text, i)
            if new_i
              result << tag_output
              i = new_i
              next
            end
          end

          result << text[i]
          i += 1
        end

        result
      end

      # Sort attributes within a tag's content string.
      # Splits into tag name + attributes, sorts attributes by name,
      # and reassembles. Also lowercases values of case-insensitive attrs
      # (encoding, standalone) per XML spec.
      #
      # @param tag_content [String] Content between < and >
      # @return [String] Content with attributes sorted alphabetically
      def self.sort_tag_attributes(tag_content)
        tokens = tokenize_tag_content(tag_content)
        return tag_content if tokens.nil?

        tag_name = tokens[:name]
        attrs = tokens[:attrs]
        return tag_content if attrs.empty?

        # Sort attributes by name (case-insensitive for stability)
        sorted_attrs = attrs.sort_by { |a| a[:name].downcase }

        # Reassemble
        parts = [tag_name]
        sorted_attrs.each do |attr|
          parts << " "
          parts << attr[:name]
          parts << "="
          parts << if CASE_INSENSITIVE_ATTRS.include?(attr[:name].downcase)
                     "\"#{attr[:value][1...-1].downcase}\""
                   else
                     attr[:value]
                   end
        end
        parts.join
      end

      # Tokenize tag content into name and attribute pairs.
      # Handles quoted attribute values with single or double quotes.
      #
      # @param tag_content [String] Content between < and >
      # @return [Hash, nil] { name: String, attrs: Array<{name:, value:}> }
      def self.tokenize_tag_content(tag_content)
        return nil if tag_content.strip.empty?

        i = 0
        # Find tag name (first non-whitespace word)
        i += 1 while i < tag_content.length && tag_content[i] == " "
        return nil if i >= tag_content.length

        name_start = i
        i += 1 while i < tag_content.length && tag_content[i] != " " &&
            tag_content[i] != "/" && tag_content[i] != ">"
        tag_name = tag_content[name_start...i]

        # Skip whitespace
        i += 1 while i < tag_content.length && tag_content[i] == " "

        # Parse attributes
        attrs = []
        while i < tag_content.length
          # Skip whitespace
          i += 1 while i < tag_content.length && tag_content[i] == " "
          break if i >= tag_content.length

          # Read attribute name
          attr_start = i
          i += 1 while i < tag_content.length && tag_content[i] != "=" &&
              tag_content[i] != " " && tag_content[i] != "/" &&
              tag_content[i] != ">"
          break if i >= tag_content.length || i == attr_start

          attr_name = tag_content[attr_start...i]

          # Skip whitespace and =
          i += 1 while i < tag_content.length &&
              SKIP_CHARS.include?(tag_content[i])
          break if i >= tag_content.length

          # Read quoted value
          quote = tag_content[i]
          break unless QUOTE_CHARS.include?(quote)

          i += 1
          value_start = i
          while i < tag_content.length && tag_content[i] != quote
            i += 1
          end
          break if i >= tag_content.length

          attr_value = tag_content[value_start...i]
          i += 1 # skip closing quote

          attrs << { name: attr_name, value: "#{quote}#{attr_value}#{quote}" }
        end

        { name: tag_name, attrs: attrs }
      end

      # Process a tag starting at position i, returning the new position
      # and the (possibly attribute-sorted) tag string.
      #
      # @param text [String] Full text
      # @param i [Integer] Position of '<'
      # @return [Array(Integer, String), nil] [new_position, tag_string] or nil
      def self.process_tag(text, pos)
        if text[pos + 1] == "?"
          process_processing_instruction(text, pos)
        elsif text[pos + 1] == "!" && text[(pos + 2)...(pos + 4)] == "--"
          process_comment(text, pos)
        else
          process_regular_tag(text, pos)
        end
      end

      # Process XML processing instruction <?...?>
      #
      # @param text [String] Full text
      # @param i [Integer] Position of '<'
      # @return [Array(Integer, String), nil] [new_position, tag_string] or nil
      def self.process_processing_instruction(text, pos)
        close_idx = text.index("?>", pos + 2)
        return nil unless close_idx

        pi_content = text[(pos + 2)...close_idx]
        sorted_pi = sort_tag_attributes(pi_content)
        [close_idx + 2, "<?#{sorted_pi}?>"]
      end

      # Process XML comment <!--...-->
      #
      # @param text [String] Full text
      # @param i [Integer] Position of '<'
      # @return [Array(Integer, String), nil] [new_position, comment_string] or nil
      def self.process_comment(text, pos)
        close_idx = text.index("-->", pos + 4)
        return nil unless close_idx

        [close_idx + 3, text[pos...(close_idx + 3)]]
      end

      # Process regular XML tag <tagname attrs...>
      #
      # @param text [String] Full text
      # @param i [Integer] Position of '<'
      # @return [Array(Integer, String), nil] [new_position, tag_string] or nil
      def self.process_regular_tag(text, pos)
        close_idx = text.index(">", pos + 1)
        return nil unless close_idx

        tag_inner = text[(pos + 1)...close_idx]
        return nil if tag_inner.include?("<")

        # Handle self-closing /> by trimming trailing /
        self_closing = tag_inner.end_with?("/")
        tc = self_closing ? tag_inner[0...-1] : tag_inner
        sorted = sort_tag_attributes(tc)
        suffix = self_closing ? "/>" : ">"
        [close_idx + 1, "<#{sorted}#{suffix}"]
      end

      private_class_method :normalize_for_comparison, :blank?,
                           :decode_xml_entities, :normalize_attribute_order,
                           :sort_tag_attributes, :tokenize_tag_content,
                           :process_tag, :process_processing_instruction,
                           :process_comment, :process_regular_tag
    end
  end
end
