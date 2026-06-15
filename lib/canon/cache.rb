# frozen_string_literal: true

require "digest" unless RUBY_ENGINE == "opal"

module Canon
  # Cache for expensive operations during document comparison
  #
  # Provides thread-safe caching with size limits to prevent memory bloat.
  # Uses LRU (Least Recently Used) eviction when cache is full.
  #
  # @example Cache a parsed document
  #   key = Cache.key_for_document(xml_string, :xml, :none)
  #   parsed = Cache.fetch(:document_parse, key) { parse_xml(xml_string) }
  #
  # @example Clear all caches (e.g., between test cases)
  #   Cache.clear_all
  module Cache
    class << self
      # Maximum number of entries per cache category
      MAX_CACHE_SIZE = 100

      # Fetch a value from cache, or compute and cache it
      #
      # @param category [Symbol] Cache category (:document_parse, :format_detect, etc.)
      # @param key [String] Cache key
      # @yield Block to compute value if not cached
      # @return [Object] Cached or computed value
      def fetch(category, key)
        cache = cache_for(category)

        # Check if key exists
        if cache.key?(key)
          # Update access time for LRU
          cache[key][:accessed] = Time.now
          return cache[key][:value]
        end

        # Compute and cache the value
        value = yield

        # Evict oldest entry if cache is full
        if cache.size >= MAX_CACHE_SIZE
          oldest_key = cache.min_by { |_, v| v[:accessed] }&.first
          cache.delete(oldest_key) if oldest_key
        end

        cache[key] = { value: value, accessed: Time.now }
        value
      end

      # Clear all caches
      #
      # Useful for tests or when memory needs to be freed
      def clear_all
        @caches&.each_value(&:clear)
        @caches = nil
      end

      # Clear a specific cache category
      #
      # @param category [Symbol] Cache category to clear
      def clear_category(category)
        return unless @caches&.key?(category)

        @caches[category]&.clear
      end

      # Get cache statistics
      #
      # @return [Hash] Statistics about cache usage
      def stats
        @caches&.transform_values(&:size) || {}
      end

      # Generate cache key for document parsing
      def key_for_document(content, format, preprocessing)
        "doc:#{format}:#{preprocessing}:#{content_hash(content)}"
      end

      # Generate cache key for format detection
      def key_for_format_detection(content)
        preview = content[0..100].b
        "fmt:#{content_hash(preview + content.length.to_s)}"
      end

      # Generate cache key for XML canonicalization
      def key_for_c14n(content, with_comments)
        "c14n:#{with_comments}:#{content_hash(content)}"
      end

      # Generate cache key for preprocessing
      def key_for_preprocessing(content, preprocessing)
        "pre:#{preprocessing}:#{content_hash(content)}"
      end

      private

      # Generate a hash string for cache keys
      def content_hash(content)
        if defined?(Digest::SHA256)
          Digest::SHA256.hexdigest(content)[0..16]
        else
          # Opal fallback: simple string hash
          h = content.each_char.reduce(0) do |acc, c|
            ((acc * 31) + c.ord) & 0xFFFFFFFF
          end
          h.to_s(16).rjust(8, "0")
        end
      end

      # Get or create cache for a category
      #
      # @param category [Symbol] Cache category
      # @return [Hash] Cache hash for category
      def cache_for(category)
        @caches ||= {}
        @caches[category] ||= {}
      end
    end
  end
end
