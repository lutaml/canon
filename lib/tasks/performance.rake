# frozen_string_literal: true

require_relative "performance_comparator"

desc "Run performance benchmarks"
namespace :performance do
  desc "Compare performance of current branch against base branch (default: main)"
  task :compare do
    PerformanceComparator.new.run
  end

  desc "Run benchmarks on current branch only (for development)"
  task :run do
    runner = BenchmarkRunner.new(run_time: 5)
    runner.run_benchmarks
  end

  desc "Quick benchmark run (faster, less accurate)"
  task :quick do
    runner = BenchmarkRunner.new(run_time: 2, warmup: 1, items: 20)
    runner.run_benchmarks
  end
end
