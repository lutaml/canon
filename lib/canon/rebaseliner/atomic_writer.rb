# frozen_string_literal: true

require "tempfile"
require "fileutils"

module Canon
  module Rebaseliner
    # Write a file atomically by writing to a same-directory tempfile and
    # renaming over the target. Preserves the original file's mode. Avoids
    # half-written files on Ctrl-C.
    module AtomicWriter
      module_function

      # @param path [String] absolute path to write
      # @param contents [String] new file contents
      # @return [void]
      def write(path, contents)
        original_mode = File.stat(path).mode
        dir = File.dirname(path)
        Tempfile.create(["canon-rebaseline", ".tmp"], dir) do |tmp|
          tmp.binmode
          tmp.write(contents)
          tmp.flush
          tmp.fsync
          tmp.close
          File.chmod(original_mode, tmp.path)
          File.rename(tmp.path, path)
        end
      end
    end
  end
end
