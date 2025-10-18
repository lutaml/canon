# frozen_string_literal: true

require_relative "../pretty_printer/xml"
require_relative "../pretty_printer/json"
require_relative "../pretty_printer/html"

module Canon
  module Commands
    # Command for canonicalizing files
    class FormatCommand
      def initialize(options = {})
        @options = options
      end

      # rubocop:disable Metrics/MethodLength
      def run(input_file)
        # Read input file
        content = File.read(input_file)

        # Detect or use specified format
        format = detect_format(input_file)

        # Format based on mode
        result = format_content(content, format)

        # Output
        if @options[:output]
          File.write(@options[:output], result)
          mode_name = @options[:mode] == "pretty" ? "Pretty-printed" : "Canonicalized"
          puts "#{mode_name} #{format.upcase} written to #{@options[:output]}"
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

      def format_content(content, format)
        mode = @options[:mode] || "c14n"

        case mode
        when "pretty"
          format_pretty(content, format)
        when "c14n"
          format_canonical(content, format)
        else
          abort "Error: Invalid mode '#{mode}'. Use 'c14n' or 'pretty'"
        end
      end

      # rubocop:disable Metrics/MethodLength
      def format_pretty(content, format)
        indent = (@options[:indent] || 2).to_i
        indent_type = @options[:indent_type] || "space"

        case format
        when :xml
          Canon::PrettyPrinter::Xml.new(
            indent: indent,
            indent_type: indent_type,
          ).format(content)
        when :json
          Canon::PrettyPrinter::Json.new(
            indent: indent,
            indent_type: indent_type,
          ).format(content)
        when :html
          Canon::PrettyPrinter::Html.new(
            indent: indent,
            indent_type: indent_type,
          ).format(content)
        when :yaml
          # YAML formatter already pretty-prints
          Canon.format(content, format)
        end
      end

      def format_canonical(content, format)
        if format == :xml && @options[:with_comments]
          Canon::Xml::C14n.canonicalize(content, with_comments: true)
        else
          Canon.format(content, format)
        end
      end

      # rubocop:disable Metrics/MethodLength
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
        when ".html", ".htm"
          :html
        else
          abort "Error: Cannot detect format from extension '#{ext}'. " \
                "Please specify --format (xml, json, yaml, or html)"
        end
      end
    end
  end
end
