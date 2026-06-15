# frozen_string_literal: true

module Canon
  module Comparison
    module Dimensions
      # Pre-built dimension sets with format lookup.
      #
      # XML/HTML share 7 dimensions.  JSON has 3.  YAML has 4.
      # Format aliases (html, html4, html5) resolve to the XML set.
      module Registry
        SETS = {
          xml: DimensionSet.new(:xml, [
                                  Dimension.new(
                                    name: :text_content,
                                    valid_behaviors: %i[strict normalize
                                                        ignore],
                                    formatting_detection: true,
                                  ),
                                  Dimension.new(
                                    name: :structural_whitespace,
                                    valid_behaviors: %i[strict normalize
                                                        ignore],
                                    normative_rule: :strict_only,
                                    formatting_detection: true,
                                  ),
                                  Dimension.new(
                                    name: :attribute_presence,
                                    valid_behaviors: %i[strict ignore],
                                  ),
                                  Dimension.new(
                                    name: :attribute_order,
                                    valid_behaviors: %i[strict ignore],
                                  ),
                                  Dimension.new(
                                    name: :attribute_values,
                                    valid_behaviors: %i[strict strip compact
                                                        normalize ignore],
                                  ),
                                  Dimension.new(
                                    name: :element_position,
                                    valid_behaviors: %i[strict ignore],
                                  ),
                                  Dimension.new(
                                    name: :comments,
                                    valid_behaviors: %i[strict ignore],
                                  ),
                                ]),

          json: DimensionSet.new(:json, [
                                   Dimension.new(
                                     name: :text_content,
                                     valid_behaviors: %i[strict normalize
                                                         ignore],
                                   ),
                                   Dimension.new(
                                     name: :structural_whitespace,
                                     valid_behaviors: %i[strict normalize
                                                         ignore],
                                     normative_rule: :strict_only,
                                   ),
                                   Dimension.new(
                                     name: :key_order,
                                     valid_behaviors: %i[strict ignore],
                                   ),
                                 ]),

          yaml: DimensionSet.new(:yaml, [
                                   Dimension.new(
                                     name: :text_content,
                                     valid_behaviors: %i[strict normalize
                                                         ignore],
                                   ),
                                   Dimension.new(
                                     name: :structural_whitespace,
                                     valid_behaviors: %i[strict normalize
                                                         ignore],
                                     normative_rule: :strict_only,
                                   ),
                                   Dimension.new(
                                     name: :key_order,
                                     valid_behaviors: %i[strict ignore],
                                   ),
                                   Dimension.new(
                                     name: :comments,
                                     valid_behaviors: %i[strict ignore],
                                   ),
                                 ]),
        }.freeze

        FORMAT_ALIASES = {
          html: :xml,
          html4: :xml,
          html5: :xml,
        }.freeze

        class << self
          # Look up the DimensionSet for a format.
          # Format aliases (html, html4, html5) resolve to the :xml set.
          # Unknown formats fall back to :xml.
          #
          # @param format [Symbol]
          # @return [DimensionSet]
          def for(format)
            key = FORMAT_ALIASES[format] || format
            SETS[key] || SETS[:xml]
          end

          # All format names with explicit sets (excluding aliases).
          #
          # @return [Array<Symbol>]
          def format_names
            SETS.keys
          end
        end
      end
    end
  end
end
