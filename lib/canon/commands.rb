# frozen_string_literal: true

module Canon
  # Thor command implementations invoked by {CLI}. Children are autoloaded.
  module Commands
    autoload :DiffCommand, "canon/commands/diff_command"
    autoload :FormatCommand, "canon/commands/format_command"
  end
end
