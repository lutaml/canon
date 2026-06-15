# frozen_string_literal: true

require "yaml"

module Canon
  class Config
    # Loads configuration profiles from YAML files.
    # Supports built-in profiles (shipped with the gem) and external file paths.
    # Profiles can inherit from other profiles via the +inherits+ key.
    class ProfileLoader
      PROFILES_DIR = File.expand_path("profiles", __dir__).freeze

      class << self
        # Load a profile by name (Symbol for built-in) or file path (String).
        # Returns a merged Hash with inheritance resolved.
        def load(name_or_path)
          key = cache_key(name_or_path)
          cache[key] ||= resolve(name_or_path, [])
        end

        # List available built-in profile names.
        def available_profiles
          return [] unless Dir.exist?(PROFILES_DIR)

          Dir.glob(File.join(PROFILES_DIR, "*.yml")).map do |path|
            File.basename(path, ".yml").to_sym
          end.sort
        end

        def reset_cache!
          @cache = nil
        end

        # Deep merge two hashes. Arrays are replaced (not concatenated).
        def deep_merge(base, overlay)
          result = base.dup
          overlay.each do |key, value|
            result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
                            deep_merge(result[key], value)
                          else
                            value
                          end
          end
          result
        end

        private

        def cache
          @cache ||= {}
        end

        def cache_key(name_or_path)
          if name_or_path.is_a?(Symbol)
            name_or_path
          else
            File.expand_path(name_or_path.to_s)
          end
        end

        # Resolve a profile, following inheritance chain.
        # +seen+ tracks visited profiles for cycle detection.
        def resolve(name_or_path, seen)
          path = resolve_path(name_or_path)
          resolve_from_path(path, seen)
        end

        def resolve_from_path(path, seen)
          canonical = File.expand_path(path)

          if seen.include?(canonical)
            chain = seen.map { |s| File.basename(s, ".yml") }.join(" -> ")
            raise Canon::Error,
                  "Profile inheritance cycle detected: #{chain} -> #{File.basename(
                    canonical, '.yml'
                  )}"
          end

          seen = seen + [canonical]
          data = load_yaml(path)

          if data["inherits"]
            parent_path = resolve_inherits_path(data["inherits"])
            parent = resolve_from_path(parent_path, seen)
            data = deep_merge(parent, data)
          end

          data.delete("inherits")
          data
        end

        # Determine the YAML file path from a name or path value.
        # Symbols are looked up as built-in profiles; strings are treated
        # as file paths.
        def resolve_path(name_or_path)
          if name_or_path.is_a?(Symbol)
            path = File.join(PROFILES_DIR, "#{name_or_path}.yml")
            unless File.exist?(path)
              available = available_profiles.join(", ")
              raise Canon::Error,
                    "Unknown config profile: #{name_or_path}. Available: #{available}"
            end

            path
          else
            expanded = File.expand_path(name_or_path.to_s)
            unless File.exist?(expanded)
              raise Canon::Error, "Profile file not found: #{expanded}"
            end

            expanded
          end
        end

        # Resolve an +inherits+ value from YAML (always a string).
        # Tries built-in profile name first, then file path.
        def resolve_inherits_path(value)
          builtin = File.join(PROFILES_DIR, "#{value}.yml")
          return builtin if File.exist?(builtin)

          expanded = File.expand_path(value)
          return expanded if File.exist?(expanded)

          raise Canon::Error, "Inherited profile not found: #{value}"
        end

        def load_yaml(path)
          content = File.read(path)
          YAML.safe_load(content, permitted_classes: [Symbol]) || {}
        end
      end
    end
  end
end
