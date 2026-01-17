# frozen_string_literal: true

require "set"

module Canon
  module TreeDiff
    module OperationConverterHelpers
      # Reason string builders for operations
      # Handles creation of human-readable reason messages for DiffNodes
      module ReasonBuilder
        # Build reason string for INSERT operation
        #
        # @param operation [Operation] Operation
        # @return [String] Reason description
        def self.build_insert_reason(operation)
          node = operation[:node]
          content = operation[:content]

          if node.respond_to?(:label)
            # Include content preview for clarity
            "Element inserted: #{content || "<#{node.label}>"}"
          else
            "Element inserted"
          end
        end

        # Build reason string for DELETE operation
        #
        # @param operation [Operation] Operation
        # @return [String] Reason description
        def self.build_delete_reason(operation)
          node = operation[:node]
          content = operation[:content]

          if node.respond_to?(:label)
            # Include content preview for clarity
            "Element deleted: #{content || "<#{node.label}>"}"
          else
            "Element deleted"
          end
        end

        # Build reason string for UPDATE operation
        #
        # @param operation [Operation] Operation
        # @return [String] Reason description
        def self.build_update_reason(operation)
          change_type = operation[:change_type] || "content"
          "updated #{change_type}"
        end

        # Build reason string for MOVE operation
        #
        # @param operation [Operation] Operation
        # @return [String] Reason description
        def self.build_move_reason(operation)
          from_pos = operation[:from_position]
          to_pos = operation[:to_position]

          if from_pos && to_pos
            "moved from position #{from_pos} to #{to_pos}"
          else
            "moved to different position"
          end
        end

        # Build detailed reason for attribute differences
        #
        # @param old_attrs [Hash] Old attributes
        # @param new_attrs [Hash] New attributes
        # @return [String] Detailed reason
        def self.build_attribute_diff_details(old_attrs, new_attrs)
          old_keys = Set.new(old_attrs.keys)
          new_keys = Set.new(new_attrs.keys)

          missing = old_keys - new_keys
          extra = new_keys - old_keys
          changed = (old_keys & new_keys).reject do |k|
            old_attrs[k] == new_attrs[k]
          end

          parts = []
          parts << "Missing: #{missing.to_a.join(', ')}" if missing.any?
          parts << "Extra: #{extra.to_a.join(', ')}" if extra.any?
          if changed.any?
            parts << "Changed: #{changed.map do |k|
              "#{k}=\"#{truncate(old_attrs[k],
                                 20)}\" → \"#{truncate(new_attrs[k], 20)}\""
            end.join(', ')}"
          end

          parts.any? ? "Attributes differ (#{parts.join('; ')})" : "Attribute values differ"
        end

        # Build reason for attribute value changes
        #
        # @param changes [Hash] Changes hash
        # @return [String] Reason description
        def self.build_attribute_value_reason(changes)
          # Changes can be either true (flag) or { old: ..., new: ... } (detailed)
          if changes.is_a?(Hash) && changes.key?(:old)
            build_attribute_diff_details(changes[:old], changes[:new])
          else
            "attribute values differ"
          end
        end

        # Build reason for attribute order changes
        #
        # @param changes [Hash] Changes hash
        # @return [String] Reason description
        def self.build_attribute_order_reason(changes)
          if changes.is_a?(Hash) && changes.key?(:old)
            old_order = changes[:old]
            new_order = changes[:new]
            "Attribute order changed: [#{old_order.join(', ')}] → [#{new_order.join(', ')}]"
          else
            "attribute order differs"
          end
        end

        # Build reason for text content changes
        #
        # @param changes [Hash] Changes hash
        # @return [String] Reason description
        def self.build_text_content_reason(changes)
          if changes.is_a?(Hash) && changes.key?(:old)
            old_val = changes[:old] || ""
            new_val = changes[:new] || ""
            preview_old = truncate(old_val.to_s, 40)
            preview_new = truncate(new_val.to_s, 40)
            "Text content changed: \"#{preview_old}\" → \"#{preview_new}\""
          else
            "text content differs"
          end
        end

        # Build reason for element name changes
        #
        # @param changes [Hash] Changes hash
        # @return [String] Reason description
        def self.build_element_name_reason(changes)
          if changes.is_a?(Hash) && changes.key?(:old)
            old_label = changes[:old]
            new_label = changes[:new]
            "Element name changed: <#{old_label}> → <#{new_label}>"
          else
            "element name differs"
          end
        end

        # Truncate text for reason messages
        #
        # @param text [String] Text to truncate
        # @param max_length [Integer] Maximum length
        # @return [String] Truncated text
        def self.truncate(text, max_length)
          return "" if text.nil?

          text = text.to_s
          return text if text.length <= max_length

          "#{text[0...max_length - 3]}..."
        end
      end
    end
  end
end
