# frozen_string_literal: true

module Canon
  class Config
    # Resolves configuration values using priority chain
    # Priority: ENV > programmatic > defaults
    class OverrideResolver
      attr_reader :defaults, :programmatic, :env

      def initialize(defaults: {}, programmatic: {}, env: {})
        @defaults = defaults
        @programmatic = programmatic
        @env = env
      end

      # Resolve a single value using priority chain
      # Uses .key? to properly handle false values
      def resolve(key)
        return @env[key] if @env.key?(key)
        return @programmatic[key] if @programmatic.key?(key)

        @defaults[key]
      end

      # Update programmatic value
      def set_programmatic(key, value)
        @programmatic[key] = value
      end

      # Update ENV override
      def set_env(key, value)
        @env[key] = value
      end

      # Check if value is set by ENV
      def env_set?(key)
        @env.key?(key)
      end

      # Check if value is set programmatically
      def programmatic_set?(key)
        @programmatic.key?(key)
      end

      # Get the source of a value
      def source_for(key)
        return :env if @env.key?(key)
        return :programmatic if @programmatic.key?(key)
        return :default if @defaults.key?(key)

        nil
      end
    end
  end
end
