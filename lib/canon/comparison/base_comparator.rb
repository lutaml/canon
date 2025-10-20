# frozen_string_literal: true

module Canon
  module Comparison
    # Base module for comparators providing common patterns
    # Each comparator should include this module and implement:
    # - serialize_for_display(content, match_opts)
    module BaseComparator
      # Build verbose result hash with preprocessed strings
      #
      # @param differences [Array] Array of difference hashes
      # @param content1 [Object] First content to compare
      # @param content2 [Object] Second content to compare
      # @param match_opts [Hash] Match options used during comparison
      # @return [Hash] Hash with :differences and :preprocessed keys
      def build_verbose_result(differences, content1, content2, match_opts)
        {
          differences: differences,
          preprocessed: [
            serialize_for_display(content1, match_opts),
            serialize_for_display(content2, match_opts),
          ],
        }
      end

      # Serialize content for display in diffs
      # This method must be implemented by each comparator
      #
      # @param content [Object] Content to serialize
      # @param match_opts [Hash] Match options that were applied during comparison
      # @return [String] Serialized content reflecting match options
      # @raise [NotImplementedError] if not implemented by including class
      def serialize_for_display(content, match_opts)
        raise NotImplementedError,
              "#{self.class.name} must implement serialize_for_display"
      end
    end
  end
end
