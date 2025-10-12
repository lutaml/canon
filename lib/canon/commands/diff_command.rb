# frozen_string_literal: true

require "diffy"

module Canon
  module Commands
    # Command for diffing two canonicalized files
    class DiffCommand
      def initialize(options = {})
        @options = options
      end

      def run(file1, file2)
        # Read and canonicalize both files
        content1 = canonicalize_file(file1, @options[:format1] || @options[:format])
        content2 = canonicalize_file(file2, @options[:format2] || @options[:format])

        # Create diff
        diff = Diffy::Diff.new(content1, content2, context: 3)

        # Check if files are identical
        if diff.to_s.empty?
          puts "Files are canonically equivalent"
          exit 0
        end

        # Output diff
        if @options[:color]
          puts diff.to_s(:color)
        else
          puts diff.to_s
        end

        exit 1
      rescue Errno::ENOENT => e
        abort "Error: #{e.message}"
      rescue Canon::Error => e
        abort "Error: #{e.message}"
      rescue StandardError => e
        abort "Error processing files: #{e.message}"
      end

      private

      def canonicalize_file(filename, format_override = nil)
        content = File.read(filename)
        format = format_override ? format_override.to_sym : detect_format(filename)

        if format == :xml && @options[:with_comments]
          Canon::Xml::C14n.canonicalize(content, with_comments: true)
        else
          Canon.format(content, format)
        end
      end

      def detect_format(filename)
        ext = File.extname(filename).downcase
        case ext
        when ".xml"
          :xml
        when ".json"
          :json
        when ".yaml", ".yml"
          :yaml
        else
          abort "Error: Cannot detect format from extension '#{ext}'. " \
                "Please specify --format (xml, json, or yaml)"
        end
      end
    end
  end
end
