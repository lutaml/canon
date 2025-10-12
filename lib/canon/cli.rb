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
      - c14n (default): Canonical XML 1.1 for XML, canonical form for JSON/YAML
      - pretty: Pretty-printed with indentation

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
                  enum: %w[xml json yaml],
                  desc: "Format type (xml, json, or yaml)"
    method_option :mode,
                  aliases: "-m",
                  type: :string,
                  enum: %w[c14n pretty],
                  default: "c14n",
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

    desc "diff FILE1 FILE2", "Compare two canonicalized files"
    long_desc <<~DESC
      Compare two files after canonicalizing them.

      The format is auto-detected from file extensions, or can be explicitly
      specified with --format (for both files) or --format1 and --format2
      (for different formats).

      Examples:

        $ canon diff file1.xml file2.xml
        $ canon diff data1.json data2.json --color
        $ canon diff file1.txt file2.txt --format xml
        $ canon diff data.xml data.json --format1 xml --format2 json
    DESC
    method_option :format,
                  aliases: "-f",
                  type: :string,
                  enum: %w[xml json yaml],
                  desc: "Format type for both files"
    method_option :format1,
                  type: :string,
                  enum: %w[xml json yaml],
                  desc: "Format type for first file"
    method_option :format2,
                  type: :string,
                  enum: %w[xml json yaml],
                  desc: "Format type for second file"
    method_option :color,
                  type: :boolean,
                  default: true,
                  desc: "Colorize diff output"
    method_option :with_comments,
                  aliases: "-c",
                  type: :boolean,
                  default: false,
                  desc: "Include comments in canonical XML output"
    def diff(file1, file2)
      Commands::DiffCommand.new(options).run(file1, file2)
    end
  end
end
