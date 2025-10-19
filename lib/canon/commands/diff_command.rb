# frozen_string_literal: true

require_relative "../comparison"
require_relative "../diff_formatter"
require "json"
require "yaml"

module Canon
  module Commands
    # Command for semantic diffing of two files
    class DiffCommand
      def initialize(options = {})
        @options = options
      end

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def run(file1, file2)
        # Detect formats
        format1 = @options[:format1] || @options[:format] || detect_format(file1)
        format2 = @options[:format2] || @options[:format] || detect_format(file2)

        # Read raw content for potential by-line diff
        content1 = File.read(file1)
        content2 = File.read(file2)

        # Parse documents
        doc1 = parse_document_content(content1, format1)
        doc2 = parse_document_content(content2, format2)

        # Build comparison options
        comp_opts = build_comparison_options

        # Perform semantic comparison
        result = Canon::Comparison.equivalent?(doc1, doc2, comp_opts)

        # Determine diff mode
        mode = determine_mode(format1)

        # Prepare formatted content for by-line mode
        formatted1, formatted2 = prepare_formatted_content(
          content1, content2, format1, mode
        )

        # Format and output results
        formatter = Canon::DiffFormatter.new(
          use_color: @options[:color],
          mode: mode,
          context_lines: @options.fetch(:context_lines, 3),
          diff_grouping_lines: @options[:diff_grouping_lines],
        )
        if comp_opts[:verbose]
          # result is an array of differences
          output = formatter.format(
            result,
            format1,
            doc1: formatted1,
            doc2: formatted2,
          )
          puts output
          exit result.empty? ? 0 : 1
        elsif result
          # result is a boolean
          puts formatter.send(:success_message)
          exit 0
        else
          puts "Files are semantically different"
          exit 1
        end
      rescue Errno::ENOENT => e
        abort "Error: #{e.message}"
      rescue JSON::ParserError => e
        abort "Error parsing JSON: #{e.message}"
      rescue Psych::SyntaxError => e
        abort "Error parsing YAML: #{e.message}"
      rescue Canon::Error => e
        abort "Error: #{e.message}"
      rescue StandardError => e
        abort "Error processing files: #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength

      private

      # Build comparison options from CLI options
      def build_comparison_options
        opts = build_profile_and_preprocessing_options
        match_opts = build_match_dimension_options

        opts[:match] = match_opts unless match_opts.empty?
        opts[:ignore_attr_order] = @options.fetch(:ignore_attr_order, true)
        opts[:verbose] = @options.fetch(:verbose, false)

        opts
      end

      # Build profile and preprocessing options
      def build_profile_and_preprocessing_options
        opts = {}
        if @options[:match_profile]
          opts[:match_profile] =
            @options[:match_profile].to_sym
        end
        if @options[:preprocessing]
          opts[:preprocessing] =
            @options[:preprocessing].to_sym
        end
        opts
      end

      # Build match dimension options
      def build_match_dimension_options
        dimensions = %i[
          text_content structural_whitespace attribute_whitespace
          comments key_order
        ]

        dimensions.each_with_object({}) do |dim, opts|
          opts[dim] = @options[dim].to_sym if @options[dim]
        end
      end

      # Determine diff mode based on format and options
      def determine_mode(format)
        # HTML always uses by-line mode
        return :by_line if format == :html

        # Check for explicit --by-line flag for XML, JSON, YAML
        return :by_line if @options[:by_line]

        # Default: by-object mode for JSON and YAML, by-object for XML
        :by_object
      end

      # Parse document content based on its format
      def parse_document_content(content, format)
        case format
        when :xml
          # Return string for Canon::Comparison to parse
          content
        when :html
          # Return string for Canon::Comparison to parse
          content
        when :json
          # Parse JSON to Ruby object
          JSON.parse(content)
        when :yaml
          # Parse YAML to Ruby object
          YAML.safe_load(content)
        else
          abort "Error: Unsupported format '#{format}'"
        end
      end

      # Prepare formatted content for by-line diff
      def prepare_formatted_content(content1, content2, format, mode)
        return [content1, content2] unless mode == :by_line

        case format
        when :xml
          require_relative "../pretty_printer/xml"
          formatted1 = Canon::PrettyPrinter::Xml.new(indent: 2).format(content1)
          formatted2 = Canon::PrettyPrinter::Xml.new(indent: 2).format(content2)
          [formatted1, formatted2]
        when :html
          require_relative "../pretty_printer/html"
          formatted1 = Canon::PrettyPrinter::Html.new(indent: 2).format(content1)
          formatted2 = Canon::PrettyPrinter::Html.new(indent: 2).format(content2)
          [formatted1, formatted2]
        else
          [content1, content2]
        end
      end

      # Detect format from file extension
      def detect_format(filename)
        ext = File.extname(filename).downcase
        case ext
        when ".xml"
          :xml
        when ".html", ".htm"
          :html
        when ".json"
          :json
        when ".yaml", ".yml"
          :yaml
        else
          abort "Error: Cannot detect format from extension '#{ext}'. " \
                "Please specify --format (xml, html, json, or yaml)"
        end
      end
    end
  end
end
