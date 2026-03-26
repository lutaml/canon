# frozen_string_literal: true

module Canon
  module Diff
    # Decomposes two strings into their common prefix, changed portion, and
    # common suffix. Used during DiffNode enrichment (Phase 1) to produce
    # the 3-part decomposition: before-text, changed-text, after-text.
    #
    # This is a pure function with no side effects. It operates on short
    # serialized strings (e.g., "Hello World" vs "Hello Universe"), NOT
    # on full document text.
    #
    # @example Simple substitution
    #   TextDecomposer.decompose("Hello World", "Hello Universe")
    #   # => { common_prefix: "Hello ", changed_old: "World",
    #   #      changed_new: "Universe", common_suffix: "" }
    #
    # @example Mid-string insertion
    #   TextDecomposer.decompose("abc", "aXbc")
    #   # => { common_prefix: "a", changed_old: "",
    #   #      changed_new: "X", common_suffix: "bc" }
    #
    # @example Full replacement
    #   TextDecomposer.decompose("foo", "bar")
    #   # => { common_prefix: "", changed_old: "foo",
    #   #      changed_new: "bar", common_suffix: "" }
    class TextDecomposer
      # Decompose two strings into common prefix / changed / common suffix.
      #
      # Algorithm: character-by-character prefix scan from the start,
      # then reverse suffix scan from the end. The middle portion is
      # the actual change. O(n) where n is the string length.
      #
      # @param text1 [String] the old text (serialized_before)
      # @param text2 [String] the new text (serialized_after)
      # @return [Hash] with keys :common_prefix, :changed_old, :changed_new, :common_suffix
      def self.decompose(text1, text2)
        return empty_result if text1.nil? && text2.nil?

        if text2.nil?
          return { common_prefix: "", changed_old: text1.to_s,
                   changed_new: "", common_suffix: "" }
        end
        if text1.nil?
          return { common_prefix: "", changed_old: "",
                   changed_new: text2.to_s, common_suffix: "" }
        end

        prefix_len = find_common_prefix_length(text1, text2)
        suffix_len = find_common_suffix_length(text1, text2, prefix_len)

        {
          common_prefix: text1[0...prefix_len],
          changed_old: text1[prefix_len...(text1.length - suffix_len)],
          changed_new: text2[prefix_len...(text2.length - suffix_len)],
          common_suffix: text1[(text1.length - suffix_len)..],
        }
      end

      class << self
        private

        def empty_result
          { common_prefix: "", changed_old: "", changed_new: "",
            common_suffix: "" }
        end

        # Find the length of the common prefix of two strings.
        # @param text1 [String]
        # @param text2 [String]
        # @return [Integer] number of matching characters from the start
        def find_common_prefix_length(text1, text2)
          max_len = [text1.length, text2.length].min
          count = 0
          while count < max_len && text1[count] == text2[count]
            count += 1
          end
          count
        end

        # Find the length of the common suffix of two strings,
        # excluding the common prefix.
        # @param text1 [String]
        # @param text2 [String]
        # @param prefix_len [Integer] length of already-matched prefix
        # @return [Integer] number of matching characters from the end
        def find_common_suffix_length(text1, text2, prefix_len)
          remaining1 = text1.length - prefix_len
          remaining2 = text2.length - prefix_len
          max_suffix = [remaining1, remaining2].min
          return 0 if max_suffix <= 0

          count = 0
          while count < max_suffix &&
              text1[text1.length - 1 - count] == text2[text2.length - 1 - count]
            count += 1
          end
          count
        end
      end
    end
  end
end
