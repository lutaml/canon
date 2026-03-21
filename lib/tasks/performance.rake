# frozen_string_literal: true

require_relative "performance_comparator"
require_relative "benchmark_runner"

desc "Run performance benchmarks"
namespace :performance do
  desc "Compare performance of current branch against base branch (default: main)"
  task :compare do
    PerformanceComparator.new.run
  end

  desc "Run benchmarks on current branch only (for development)"
  task :run do
    runner = BenchmarkRunner.new(run_time: 5)
    results = runner.run_benchmarks

    puts "\n=== Benchmark Results ===\n"
    results.each do |label, metrics|
      ips = (metrics[:lower] + metrics[:upper]) / 2.0
      puts format("%<label>30s: %<ips>.2f IPS", label: label, ips: ips)
    end
  end

  desc "Run specific benchmark category (xml_parsing, html_parsing, xml_comparison, html_comparison, formatting)"
  task :category, [:name] do |_t, args|
    category = args[:name]
    unless PerformanceComparator::BENCHMARK_CATEGORIES.key?(category.to_sym)
      puts "Unknown category: #{category}"
      puts "Available: #{PerformanceComparator::BENCHMARK_CATEGORIES.keys.join(', ')}"
      exit(1)
    end

    puts "Running category: #{category}"
    runner = BenchmarkRunner.new(run_time: 10)
    results = runner.run_benchmarks

    # Filter to category
    labels = PerformanceComparator::BENCHMARK_CATEGORIES[category.to_sym]
    filtered = results.slice(*labels)

    puts "\n=== #{category.capitalize} Results ===\n"
    filtered.each do |label, metrics|
      ips = (metrics[:lower] + metrics[:upper]) / 2.0
      puts format("%<label>30s: %<ips>.2f IPS", label: label, ips: ips)
    end
  end

  desc "Quick benchmark run (faster, less accurate)"
  task :quick do
    runner = BenchmarkRunner.new(run_time: 2, warmup: 1, items: 20)
    results = runner.run_benchmarks

    puts "\n=== Quick Benchmark Results ===\n"
    results.each do |label, metrics|
      ips = (metrics[:lower] + metrics[:upper]) / 2.0
      puts format("%<label>30s: %<ips>.2f IPS", label: label, ips: ips)
    end
  end
end
