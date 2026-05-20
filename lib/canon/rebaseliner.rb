# frozen_string_literal: true

require_relative "rebaseliner/atomic_writer"
require_relative "rebaseliner/logger"
require_relative "rebaseliner/heredoc_spec"
require_relative "rebaseliner/heredoc_rewriter"
require_relative "rebaseliner/heredoc_locator"
require_relative "rebaseliner/call_site_resolver"

module Canon
  # In-place rebaselining of `be_*_equivalent_to` heredoc expectations.
  #
  # Opt-in via `CANON_REGENERATE_EXPECTED=true`. When set, a failing
  # matcher assertion has its expected heredoc body replaced with the
  # prettyprinted received value, and the assertion is reported as
  # passing for the run. Default OFF; passing assertions are never
  # touched.
  #
  # See docs/features/regenerate-expected.adoc for the supported
  # expected-argument forms and the recommended workflow.
  module Rebaseliner
    ENV_VAR = "CANON_REGENERATE_EXPECTED"

    # @return [Boolean] true when the env var is set to a truthy value.
    #   Memoised per process.
    def self.enabled?
      return @enabled if defined?(@enabled)

      @enabled = case ENV.fetch(ENV_VAR, "").to_s.downcase
                 when "1", "true", "yes", "on" then true
                 else false
                 end
    end

    # Reset memoisation; used by tests.
    def self.reset!
      remove_instance_variable(:@enabled) if defined?(@enabled)
      @line_shifts = nil
    end

    # Per-file cumulative line-shift tracking. After a rewrite, the file
    # on disk has different line numbering, but Ruby's caller_locations
    # still reports the ORIGINAL line numbers (the in-memory source).
    # For each spec_path we accumulate (threshold_line, delta) tuples,
    # and use them to translate an original line number to its current
    # post-rewrite line.
    def self.line_shifts
      @line_shifts ||= Hash.new { |h, k| h[k] = [] }
    end

    # Translate an original caller line to the current line in the file,
    # given accumulated shifts.
    def self.shifted_line(spec_path, original_line)
      shifts = line_shifts[spec_path]
      shifts.inject(original_line) do |line, (threshold, delta)|
        original_line > threshold ? line + delta : line
      end
    end

    # Record a line shift caused by a rewrite. `threshold` is the original
    # source line where the rewrite began; any subsequent line in the
    # original source after that threshold is offset by `delta`.
    def self.record_shift(spec_path, threshold, delta)
      line_shifts[spec_path] << [threshold, delta]
    end

    # Attempt to rewrite the heredoc that backs a failing assertion.
    #
    # @param spec_path [String] absolute path of the spec file containing
    #   the matcher invocation
    # @param line [Integer] 1-indexed line of the matcher invocation
    # @param prettyprinted_actual [String] new body content
    # @return [Symbol] :rewritten, :skipped_inline_string,
    #   :skipped_interpolation, :skipped_method_call,
    #   :skipped_cross_file, :skipped_unresolved, or :error
    def self.rewrite!(spec_path:, line:, prettyprinted_actual:)
      # Translate the caller-reported original line to its current
      # position in the on-disk file, accounting for any previous
      # rewrites that shifted subsequent lines.
      effective_line = shifted_line(spec_path, line)
      call_site = CallSiteResolver.resolve(spec_path: spec_path,
                                           line: effective_line)
      unless call_site
        Logger.log(:skipped_unresolved, spec_path: spec_path, line: line,
                                        detail: "no matcher call at line")
        return :skipped_unresolved
      end

      locator = HeredocLocator.new(
        spec_path: spec_path,
        source: call_site.source,
        enclosing_block: call_site.enclosing_block,
        expected_node: call_site.expected_node,
        matcher_line: call_site.matcher_line,
      )
      result = locator.resolve
      unless result.rewritable?
        Logger.log(result.status, spec_path: spec_path, line: line)
        return result.status
      end

      old_line_count = line_count_in_range(call_site.source,
                                           result.heredoc_spec)
      HeredocRewriter.rewrite!(result.heredoc_spec, prettyprinted_actual)
      new_line_count = count_newlines(File.read(spec_path)
        .byteslice(result.heredoc_spec.content_start_offset,
                   File.size(spec_path) -
                   result.heredoc_spec.content_start_offset))
      # Compute shift simply by re-reading the file size delta in lines.
      record_shift_from_disk(spec_path, call_site, result.heredoc_spec,
                             old_line_count)
      Logger.log(:rewritten, spec_path: spec_path, line: line)
      :rewritten
    rescue StandardError => e
      Logger.log(:error, spec_path: spec_path, line: line,
                         detail: "#{e.class}: #{e.message}")
      :error
    end

    # Count newlines in the original heredoc body (between content_start
    # and content_end byte offsets) and in the rewritten file's same
    # logical range; the difference is the line shift to record. We
    # threshold the shift on the line where the heredoc opened, so that
    # only lines AFTER the rewrite point are adjusted.
    def self.line_count_in_range(source, heredoc_spec)
      body = source.byteslice(heredoc_spec.content_start_offset,
                              heredoc_spec.content_end_offset -
                              heredoc_spec.content_start_offset)
      count_newlines(body.to_s)
    end

    def self.count_newlines(str)
      str.count("\n")
    end

    def self.record_shift_from_disk(spec_path, call_site, heredoc_spec,
                                    old_line_count)
      new_source = File.read(spec_path)
      # The new body lives at the same content_start_offset (since the
      # offset is computed pre-rewrite from the pre-rewrite source). We
      # need to find where the heredoc body ends in the new source. The
      # closing terminator is unchanged textually, so we can search for
      # the next occurrence of the closing line from the start offset.
      pre = new_source.byteslice(0, heredoc_spec.content_start_offset)
      remainder = new_source.byteslice(heredoc_spec.content_start_offset..-1)
      # Find the closing terminator: same text as in the original source.
      original_close = call_site.source.byteslice(
        heredoc_spec.content_end_offset,
        call_site.source.bytesize - heredoc_spec.content_end_offset,
      ).lines.first.to_s
      close_idx = remainder.index(original_close)
      return unless close_idx

      new_body = remainder.byteslice(0, close_idx)
      new_line_count = count_newlines(new_body)
      delta = new_line_count - old_line_count
      return if delta.zero?

      threshold = pre.count("\n")
      record_shift(spec_path, threshold, delta)
    end
  end
end
