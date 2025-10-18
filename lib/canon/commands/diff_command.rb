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
        opts = {}

        # New MECE match options system
        if has_new_match_options?
          build_mece_options(opts)
        else
          # Legacy options - convert to new system
          build_legacy_options(opts)
        end

        # Always include verbose flag
        opts[:verbose] = @options.fetch(:verbose, false)

        opts
      end

      # Check if user provided any new MECE options
      def has_new_match_options?
        @options[:match_profile] ||
          @options[:preprocessing] ||
          @options[:text_content] ||
          @options[:structural_whitespace] ||
          @options[:attribute_whitespace] ||
          @options[:comments]
      end

      # Build options using new MECE match system
      def build_mece_options(opts)
        # Set match profile if provided
        opts[:match_profile] = @options[:match_profile].to_sym if @options[:match_profile]

        # Set preprocessing if provided
        opts[:preprocessing] = @options[:preprocessing].to_sym if @options[:preprocessing]

        # Build match_options hash for individual dimension overrides
        match_opts = {}
        match_opts[:text_content] = @options[:text_content].to_sym if @options[:text_content]
        match_opts[:structural_whitespace] = @options[:structural_whitespace].to_sym if @options[:structural_whitespace]
        match_opts[:attribute_whitespace] = @options[:attribute_whitespace].to_sym if @options[:attribute_whitespace]
        match_opts[:comments] = @options[:comments].to_sym if @options[:comments]

        opts[:match_options] = match_opts unless match_opts.empty?

        # Always pass ignore_attr_order (not part of MECE system)
        opts[:ignore_attr_order] = @options.fetch(:ignore_attr_order, true)
      end

      # Build legacy options and convert to match_options
      def build_legacy_options(opts)
        legacy_opts = {}

        # Map CLI options to legacy Canon::Comparison options
        legacy_opts[:collapse_whitespace] = @options[:collapse_whitespace] if @options.key?(:collapse_whitespace)
        legacy_opts[:ignore_attr_order] = @options.fetch(:ignore_attr_order, true)
        legacy_opts[:ignore_text_nodes] = @options[:ignore_text_nodes] if @options.key?(:ignore_text_nodes)

        # Handle comments option
        # --with-comments means ignore_comments: false
        # --no-with-comments (default) means ignore_comments: true
        if @options.key?(:with_comments)
          legacy_opts[:ignore_comments] = !@options[:with_comments]
        elsif @options.key?(:ignore_comments)
          legacy_opts[:ignore_comments] = @options[:ignore_comments]
        end

        # Convert legacy options to new system if any were provided
        unless legacy_opts.empty?
          require_relative "../comparison/match_options"
          converted = Canon::Comparison::MatchOptions.from_legacy_options(legacy_opts)
          opts[:match_options] = converted[:match_options] if converted[:match_options]
        end

        # Always pass ignore_attr_order
        opts[:ignore_attr_order] = legacy_opts.fetch(:ignore_attr_order, true)
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
          require_relative "../xml/pretty_printer"
          formatted1 = Canon::Xml::PrettyPrinter.new(indent: 2).format(content1)
          formatted2 = Canon::Xml::PrettyPrinter.new(indent: 2).format(content2)
          [formatted1, formatted2]
        when :html
          require_relative "../html/pretty_printer"
          formatted1 = Canon::Html::PrettyPrinter.new(indent: 2).format(content1)
          formatted2 = Canon::Html::PrettyPrinter.new(indent: 2).format(content2)
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
