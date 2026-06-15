# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require "table_tennis"

# Compares performance between the current branch and a base branch (default:
# main) by running the same benchmark suite in two separate Ruby processes —
# one per branch. Each process loads its own Canon implementation from disk,
# fully isolated from the other, and emits a JSON result. The comparator then
# diffs the two JSON payloads and reports regressions.
#
# Running each branch in its own process is required because Canon uses Ruby
# autoload extensively; loading both branches' code into a single process
# causes constant resolution and LOAD_PATH conflicts.
class PerformanceComparator
  REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))
  DEFAULT_RUN_TIME = Integer(ENV.fetch("CANON_PERF_RUN_TIME", "10"))
  DEFAULT_THRESHOLD = 0.10 # 10%
  DEFAULT_BASE = "main"
  TMP_PERF_DIR = File.join(REPO_ROOT, "tmp", "performance")
  REPORT_SCRIPT = File.expand_path("performance_report.rb", __dir__)

  RED    = "\e[31m"
  GREEN  = "\e[32m"
  YELLOW = "\e[33m"
  CYAN   = "\e[36m"
  BOLD   = "\e[1m"
  DIM    = "\e[2m"
  CLEAR  = "\e[0m"

  def run
    clone_base
    current = run_report(REPO_ROOT, "current")
    base = run_report(base_clone_dir, "base (#{DEFAULT_BASE})")
    print_report(current, base)
    exit(1) if regressions?(current, base)
  ensure
    cleanup
  end

  private

  def clone_base
    FileUtils.rm_rf(TMP_PERF_DIR)
    FileUtils.mkdir_p(TMP_PERF_DIR)

    puts "#{DIM}Cloning base #{DEFAULT_BASE}...#{CLEAR}"
    repo_url, = exec("git config --get remote.origin.url")
    out, err, status = exec(
      "git clone --branch #{DEFAULT_BASE} --single-branch #{repo_url.strip} #{base_clone_dir}",
    )
    return if status.success?

    raise "git clone failed: #{err}\n#{out}"
  end

  def run_report(working_dir, label)
    puts "#{DIM}Running benchmarks for #{label}...#{CLEAR}"
    env = {
      "CANON_PERF_RUN_TIME" => DEFAULT_RUN_TIME.to_s,
      "BUNDLE_GEMFILE" => File.join(working_dir, "Gemfile"),
    }

    script_copy = File.join(working_dir, "tmp", "performance_report.rb")
    FileUtils.mkdir_p(File.dirname(script_copy))
    FileUtils.cp(REPORT_SCRIPT, script_copy)

    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby",
                                            script_copy,
                                            chdir: working_dir)
    unless status.success?
      raise "Benchmark failed for #{label}: #{stderr}\n#{stdout}"
    end

    JSON.parse(stdout)
  rescue JSON::ParserError => e
    raise "Invalid JSON from #{label}: #{e.message}"
  end

  def regressions?(current, base)
    threshold = DEFAULT_THRESHOLD
    current.fetch("benchmarks").any? do |label, metrics|
      base_metrics = base.fetch("benchmarks")[label]
      next false unless base_metrics

      change = change_fraction(metrics, base_metrics)
      change && change < -threshold
    end
  end

  def change_fraction(curr, base)
    base_ips = base.fetch("lower").to_f
    curr_ips = curr.fetch("upper").to_f
    return nil if base_ips.zero?

    (curr_ips - base_ips) / base_ips
  end

  def print_report(current, base)
    threshold = DEFAULT_THRESHOLD
    rows = current.fetch("benchmarks").map do |label, metrics|
      base_metrics = base.fetch("benchmarks")[label]
      change = change_fraction(metrics, base_metrics)
      status = if base_metrics.nil?
                 "NEW"
               elsif change < -threshold
                 "REGRESSED"
               else
                 "OK"
               end
      {
        benchmark: label,
        base_ips: base_metrics&.fetch("lower")&.round(1),
        curr_ips: metrics.fetch("upper").round(1),
        change: change ? format("%+0.1f%%", change * 100) : "N/A",
        status: status,
      }
    end

    table = TableTennis.new(rows,
                            title: "Performance Comparison",
                            theme: :dark,
                            headers: {
                              benchmark: "Benchmark",
                              base_ips: "Base IPS",
                              curr_ips: "Curr IPS",
                              change: "Change",
                              status: "Status",
                            })
    table.render
    puts

    print_summary(rows, threshold)
  end

  def print_summary(rows, threshold)
    regressions = rows.select { |r| r[:status] == "REGRESSED" }
    new_benchmarks = rows.select { |r| r[:status] == "NEW" }

    if regressions.empty?
      puts "#{GREEN}#{BOLD}✅ ALL BENCHMARKS PASSED#{CLEAR}"
    else
      puts "#{RED}#{BOLD}❌ PERFORMANCE REGRESSIONS DETECTED#{CLEAR}"
      puts "#{RED}#{regressions.length} benchmark(s) regressed " \
           "beyond #{(threshold * 100).round(0)}% threshold#{CLEAR}"
    end

    return if new_benchmarks.empty?

    puts "#{YELLOW}🆕 New benchmarks (not in base):#{CLEAR}"
    new_benchmarks.each { |r| puts "  • #{r[:benchmark]}" }
  end

  def base_clone_dir
    @base_clone_dir ||= File.join(TMP_PERF_DIR, "base-#{DEFAULT_BASE}")
  end

  def cleanup
    FileUtils.rm_rf(TMP_PERF_DIR)
  end

  def exec(cmd)
    Open3.capture3(cmd)
  end
end
