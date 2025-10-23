# frozen_string_literal: true

require_relative "registry"

module Canon
  module Options
    # Generates Thor CLI options from the Options Registry
    # This ensures CLI options stay in sync with the centralized registry
    module CliGenerator
      class << self
        # Generate Thor method_option calls for diff command
        def generate_diff_options
          lambda do |thor_class|
            Canon::Options::Registry.all_options.each do |opt|
              add_thor_option(thor_class, opt)
            end
          end
        end

        private

        # Add a single Thor option
        def add_thor_option(thor_class, opt)
          thor_opts = build_thor_opts(opt)

          thor_class.method_option(
            opt[:name],
            **thor_opts
          )
        end

        # Build Thor option hash from registry option
        def build_thor_opts(opt)
          result = {}

          # Add aliases if present
          result[:aliases] = opt[:aliases] if opt[:aliases]

          # Map type
          result[:type] = map_type(opt[:type])

          # Add enum values for enum types
          result[:enum] = opt[:values] if opt[:type] == :enum

          # Add default if present
          result[:default] = opt[:default] if opt[:default]

          # Add description
          result[:desc] = opt[:description]

          result
        end

        # Map registry type to Thor type
        def map_type(registry_type)
          case registry_type
          when :enum
            :string
          when :numeric
            :numeric
          when :boolean
            :boolean
          else
            :string
          end
        end
      end
    end
  end
end
