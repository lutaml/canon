# frozen_string_literal: true

module Canon
  module Rebaseliner
    # Single-line stderr writes prefixed with `[canon:rebaseline]`. CI- and
    # grep-friendly. No color, no buffering.
    module Logger
      PREFIX = "[canon:rebaseline]"

      module_function

      # @param status [Symbol] :rewritten / :skipped_* / :error
      # @param spec_path [String]
      # @param line [Integer]
      # @param detail [String, nil] short reason or contextual note
      # @return [void]
      def log(status, spec_path:, line:, detail: nil)
        location = "#{spec_path}:#{line}"
        suffix = detail ? " (#{detail})" : ""
        warn "#{PREFIX} #{status} #{location}#{suffix}"
      end
    end
  end
end
