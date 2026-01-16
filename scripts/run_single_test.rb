#!/usr/bin/env ruby
# frozen_string_literal: true

# Run a specific test with both algorithms to see if it's a false positive
# Usage: ruby scripts/run_single_test.rb FILE:LINE

require "bundler/setup"
require_relative "../../mn/isodoc/spec/spec_helper"

# Run tests and capture results
test_file = ARGV[0] || "../../mn/isodoc/spec/isodoc/sourcecode_spec.rb:124"

puts "=" * 80
puts "Running test: #{test_file}"
puts "=" * 80

# First with DOM
puts "\n1. With DOM algorithm:"
puts "-" * 40
ENV["CANON_HTML_DIFF_ALGORITHM"] = "dom"
ENV["CANON_XML_DIFF_ALGORITHM"] = "dom"
system("cd ../../mn/isodoc && bundle exec rspec #{test_file} --format documentation 2>&1 | tail -20")

# Then with Semantic
puts "\n2. With Semantic algorithm:"
puts "-" * 40
ENV["CANON_HTML_DIFF_ALGORITHM"] = "semantic"
ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
system("cd ../../mn/isodoc && bundle exec rspec #{test_file} --format documentation 2>&1 | tail -20")
