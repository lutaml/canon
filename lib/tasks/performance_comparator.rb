# frozen_string_literal: true

require_relative "performance_helpers"

class PerformanceComparator
  REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))
  DEFAULT_RUN_TIME = 10 # seconds
  DEFAULT_THRESHOLD = 0.10 # 10% (more lenient for complex operations)
  DEFAULT_BASE = "main"
  TMP_PERF_DIR = File.join(REPO_ROOT, "tmp", "performance")
  BENCH_SCRIPT = File.join(TMP_PERF_DIR, "benchmark_runner.rb")

  # Benchmark categories - run specific subsets
  BENCHMARK_CATEGORIES = {
    xml_parsing: %w[xml_parse_dom_simple xml_parse_sax_simple
                    xml_parse_dom_large xml_parse_sax_large],
    html_parsing: %w[html_parse_simple html_parse_complex],
    xml_comparison: %w[xml_compare_identical xml_compare_similar
                       xml_compare_different],
    html_comparison: %w[html_compare_identical html_compare_similar
                        html_compare_different],
    formatting: %w[xml_c14n_format json_format yaml_format],
  }.freeze

  def run
    setup_environment
    run_benchmarks_comparison
  ensure
    cleanup
  end

  private

  def setup_environment
    Dir.chdir(REPO_ROOT)
    FileUtils.mkdir_p(TMP_PERF_DIR)
    FileUtils.cp(File.join(REPO_ROOT, "lib", "tasks", "benchmark_runner.rb"),
                 BENCH_SCRIPT)

    PerformanceHelpers.load_into_namespace(PerformanceHelpers::Current,
                                           BENCH_SCRIPT)
    PerformanceHelpers.clone_base_repo(DEFAULT_BASE, TMP_PERF_DIR, BENCH_SCRIPT)
  end

  def run_benchmarks_comparison
    all_current = {}
    all_base = {}

    puts "\n== Running Canon Performance Benchmarks =="
    puts "Comparing: #{PerformanceHelpers.current_branch} vs #{DEFAULT_BASE}"
    puts "Threshold: #{(DEFAULT_THRESHOLD * 100).round(1)}%"
    puts

    # Run all benchmarks
    base_runner = PerformanceHelpers::Base::BenchmarkRunner.new(
      run_time: DEFAULT_RUN_TIME,
    )
    current_runner = PerformanceHelpers::Current::BenchmarkRunner.new(
      run_time: DEFAULT_RUN_TIME,
    )

    PerformanceHelpers.run_benchmarks(
      base_runner,
      current_runner,
      DEFAULT_THRESHOLD,
      all_base,
      all_current,
    )

    summary = PerformanceHelpers.summary_report(
      all_current,
      all_base,
      DEFAULT_BASE,
      DEFAULT_RUN_TIME,
      DEFAULT_THRESHOLD,
    )

    handle_results(summary)
  end

  def handle_results(summary)
    if summary[:regressions].any?
      warn "\nPerformance regressions detected!"
      exit(1)
    else
      puts "\nAll performance benchmarks passed!"
    end
  end

  def cleanup
    FileUtils.rm_rf(TMP_PERF_DIR)
  end
end
