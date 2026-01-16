#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug sourcecode_spec.rb:124 to understand the false positive pattern
# Usage: ruby scripts/debug_sourcecode_124.rb

require "bundler/setup"
require_relative "../../src/mn/isodoc/spec/spec_helper"

# Run the specific test with verbose output to capture expected/actual
puts "=" * 80
puts "DEBUGGING: sourcecode_spec.rb:124"
puts "=" * 80

# Run test with DOM (should pass)
puts "\n1. Running with DOM algorithm (should PASS):"
puts "-" * 60
ENV["CANON_HTML_DIFF_ALGORITHM"] = "dom"
ENV["CANON_XML_DIFF_ALGORITHM"] = "dom"
ENV["CANON_HTML_DIFF_VERBOSE"] = "true"
ENV["CANON_XML_DIFF_VERBOSE"] = "true"
system("cd /Users/mulgogi/src/mn/isodoc && bundle exec rspec spec/isodoc/sourcecode_spec.rb:124 --format documentation 2>&1")

puts "\n#{'=' * 80}"
# Run test with Semantic (should fail - false positive)
puts "\n2. Running with Semantic algorithm (should FAIL):"
puts "-" * 60
ENV["CANON_HTML_DIFF_ALGORITHM"] = "semantic"
ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
ENV["CANON_HTML_DIFF_VERBOSE"] = "true"
ENV["CANON_XML_DIFF_VERBOSE"] = "true"
system("cd /Users/mulgogi/src/mn/isodoc && bundle exec rspec spec/isodoc/sourcecode_spec.rb:124 --format documentation 2>&1")
