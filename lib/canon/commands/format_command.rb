# frozen_string_literal: true

module Canon
  module Commands
    # Command for canonicalizing files
    class FormatCommand
      def initialize(options = {})
        @options = options
      end

      def run(input_file)
        # Read input file
        content = File.read(input_file)

        # Detect or use specified format
        format = detect_format(input_file)

        # Canonicalize
        result = if format == :xml && @options[:with_comments]
                   Canon::Xml::C14n.canonicalize(content, with_comments: true)
                 else
                   Canon.format(content, format)
                 end

        # Output
        if @options[:output]
          File.write(@options[:output], result)
          puts "Canonicalized #{format.upcase} written to #{@options[:output]}"
        else
          puts result
        end
      rescue Errno::ENOENT
        abort "Error: File '#{input_file}' not found"
      rescue Canon::Error => e
        abort "Error: #{e.message}"
      rescue StandardError => e
        abort "Error processing file: #{e.message}"
      end

      private

      def detect_format(filename)
        return @options[:format].to_sym if @options[:format]

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
