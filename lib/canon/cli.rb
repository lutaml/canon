# frozen_string_literal: true

require "thor"
require_relative "commands/format_command"
require_relative "commands/diff_command"

module Canon
  # Command-line interface for Canon
  class Cli < Thor
    def self.exit_on_failure?
      true
    end

    desc "format FILE",
         "Canonicalize or pretty-print a file (XML, JSON, or YAML)"
    long_desc <<~DESC
      Canonicalize or pretty-print a file in XML, JSON, or YAML format.

      The format is auto-detected from the file extension (.xml, .json, .yaml, .yml),
      or can be explicitly specified with --format.

      Mode options:
      - pretty (default): Pretty-printed with indentation
      - c14n: Canonical XML 1.1 for XML, canonical form for JSON/YAML/HTML

      Examples:

        $ canon format input.xml
        $ canon format input.xml --mode pretty --indent 4
        $ canon format input.json --output output.json
        $ canon format data.xml --with-comments
        $ canon format file.txt --format xml
    DESC
    method_option :format,
                  aliases: "-f",
                  type: :string,
                  enum: %w[xml json yaml html],
                  desc: "Format type (xml, json, yaml, or html)"
    method_option :mode,
                  aliases: "-m",
                  type: :string,
                  enum: %w[c14n pretty],
                  default: "pretty",
                  desc: "Output mode: c14n (canonical) or pretty (indented)"
    method_option :indent,
                  aliases: "-i",
                  type: :numeric,
                  default: 2,
                  desc: "Indentation amount for pretty mode (default: 2)"
    method_option :indent_type,
                  type: :string,
                  enum: %w[space tab],
                  default: "space",
                  desc: "Indentation type: space or tab (default: space)"
    method_option :output,
                  aliases: "-o",
                  type: :string,
                  desc: "Output file (default: stdout)"
    method_option :with_comments,
                  aliases: "-c",
                  type: :boolean,
                  default: false,
                  desc: "Include comments in canonical XML output"
    def format(file)
      Commands::FormatCommand.new(options).run(file)
    end

    desc "diff FILE1 FILE2", "Compare two files semantically"
    long_desc <<~DESC
      Compare two files using semantic comparison (not text-based line diffs).

      Supports XML, HTML, JSON, and YAML formats with intelligent structural
      comparison. The format is auto-detected from file extensions, or can be
      explicitly specified with --format (for both files) or --format1 and
      --format2 (for different formats).

      Match Profiles:
      - strict: Exact matching (all whitespace significant)
      - rendered: Mimics browser/CSS rendering (HTML default)
      - spec_friendly: Ignores formatting differences (test-friendly)
      - content_only: Ignores all structural differences

      Preprocessing Options:
      - none: No preprocessing (default)
      - c14n: Canonicalize before comparison
      - normalize: Normalize whitespace before comparison
      - format: Pretty-print before comparison

      Legacy Comparison Options:
      - Whitespace handling (--collapse-whitespace / --no-collapse-whitespace)
      - Attribute/key ordering (--ignore-attr-order / --no-ignore-attr-order)
      - Comments (--with-comments / --no-with-comments, --ignore-comments)
      - Text nodes (--ignore-text-nodes)
      - Verbose mode (--verbose) for detailed diff output

      Examples:

        # Basic semantic comparison (uses format defaults)
        $ canon diff file1.xml file2.xml

        # Use match profile for test-friendly comparison
        $ canon diff file1.xml file2.xml --match-profile spec_friendly

        # Preprocess with normalization, then compare
        $ canon diff file1.xml file2.xml --preprocessing normalize

        # Match text content flexibly but keep structural whitespace strict
        $ canon diff file1.xml file2.xml --text-content normalize --structural-whitespace strict

        # Verbose mode with detailed differences
        $ canon diff file1.json file2.json --verbose

        # Legacy options still work (converted to match options)
        $ canon diff file1.xml file2.xml --with-comments

        # Compare different formats (same structure)
        $ canon diff config.json config.yaml --format1 json --format2 yaml

        # Disable color output
        $ canon diff file1.xml file2.xml --no-color
    DESC
    method_option :format,
                  aliases: "-f",
                  type: :string,
                  enum: %w[xml html json yaml],
                  desc: "Format type for both files"
    method_option :format1,
                  type: :string,
                  enum: %w[xml html json yaml],
                  desc: "Format type for first file"
    method_option :format2,
                  type: :string,
                  enum: %w[xml html json yaml],
                  desc: "Format type for second file"
    method_option :color,
                  type: :boolean,
                  default: true,
                  desc: "Colorize diff output"
    method_option :verbose,
                  aliases: "-v",
                  type: :boolean,
                  default: false,
                  desc: "Show detailed differences"
    method_option :by_line,
                  type: :boolean,
                  default: false,
                  desc: "Use line-by-line diff for XML (default: by-object)"
    # New MECE match options
    method_option :match_profile,
                  aliases: "-p",
                  type: :string,
                  enum: %w[strict rendered spec_friendly content_only],
                  desc: "Match profile: strict, rendered, spec_friendly, or content_only"
    method_option :preprocessing,
                  type: :string,
                  enum: %w[none c14n normalize format],
                  desc: "Preprocessing: none, c14n, normalize, or format"
    method_option :text_content,
                  type: :string,
                  enum: %w[strict normalize ignore],
                  desc: "Text content matching: strict, normalize, or ignore"
    method_option :structural_whitespace,
                  type: :string,
                  enum: %w[strict normalize ignore],
                  desc: "Structural whitespace matching: strict, normalize, or ignore"
    method_option :attribute_whitespace,
                  type: :string,
                  enum: %w[strict normalize ignore],
                  desc: "Attribute whitespace matching: strict, normalize, or ignore"
    method_option :comments,
                  type: :string,
                  enum: %w[strict normalize ignore],
                  desc: "Comment matching: strict, normalize, or ignore"
    # Legacy options (converted to match options)
    method_option :collapse_whitespace,
                  type: :boolean,
                  desc: "DEPRECATED: Use --text-content normalize instead"
    method_option :ignore_attr_order,
                  type: :boolean,
                  default: true,
                  desc: "Ignore attribute/key ordering"
    method_option :ignore_comments,
                  type: :boolean,
                  desc: "DEPRECATED: Use --comments ignore instead"
    method_option :ignore_text_nodes,
                  type: :boolean,
                  desc: "DEPRECATED: Use --text-content ignore instead"
    method_option :with_comments,
                  aliases: "-c",
                  type: :boolean,
                  desc: "DEPRECATED: Use --comments strict instead"
    method_option :context_lines,
                  type: :numeric,
                  default: 3,
                  desc: "Number of context lines around changes (default: 3)"
    method_option :diff_grouping_lines,
                  type: :numeric,
                  desc: "Group diffs within N lines into context blocks (default: no grouping)"
    def diff(file1, file2)
      Commands::DiffCommand.new(options).run(file1, file2)
    end
  end
end
