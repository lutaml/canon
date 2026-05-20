# frozen_string_literal: true

require_relative "atomic_writer"

module Canon
  module Rebaseliner
    # Replace a heredoc's body in a spec file with new content, preserving
    # the heredoc's opening style (`<<~` re-indented, `<<-`/`<<` verbatim).
    module HeredocRewriter
      module_function

      # @param spec [HeredocSpec] description of the heredoc to rewrite
      # @param new_body [String] new heredoc body (pretty-printed actual);
      #   may or may not have a trailing newline; the rewriter normalises.
      # @return [void]
      def rewrite!(spec, new_body)
        body = format_body(new_body, spec.style, spec.terminator_indent)
        new_source = spec.source.byteslice(0, spec.content_start_offset) +
                     body +
                     spec.source.byteslice(spec.content_end_offset..-1)
        AtomicWriter.write(spec.spec_path, new_source)
      end

      # Format the new body to fit the heredoc style.
      # - `:squiggly` (`<<~`): re-indent each line to the terminator column.
      # - `:dash` / `:strict`: write verbatim (the original code is
      #   indentation-sensitive, leave it alone).
      # Always ensures a single trailing newline before the terminator line.
      def format_body(new_body, style, terminator_indent)
        normalised = new_body.dup
        normalised << "\n" unless normalised.end_with?("\n")

        case style
        when :squiggly
          indent = " " * (terminator_indent || 0)
          stripped = strip_common_leading_whitespace(normalised)
          stripped.lines.map { |line| line == "\n" ? line : "#{indent}#{line}" }.join
        else
          normalised
        end
      end

      # Remove the largest common leading-whitespace prefix from a multi-line
      # string, mirroring `<<~`'s own behaviour. Blank lines don't constrain
      # the prefix.
      def strip_common_leading_whitespace(text)
        lines = text.lines
        leading = lines
          .reject { |l| l.chomp.empty? }
          .map { |l| l[/\A[ \t]*/].length }
          .min || 0
        return text if leading.zero?

        lines.map { |l| l.chomp.empty? ? l : l[leading..] }.join
      end
    end
  end
end
