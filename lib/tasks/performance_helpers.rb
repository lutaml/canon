# frozen_string_literal: true

# Performance benchmark output helpers shared between
# +benchmark_runner.rb+ (interactive) and +performance_comparator.rb+.
# Kept as a small module so the rake tasks below can pull in the color
# constants without pulling in the comparator (which would clone main).
module PerformanceHelpers
  CLEAR   = "\e[0m"
  BOLD    = "\e[1m"
  DIM     = "\e[2m"
  CYAN    = "\e[36m"
  GREEN   = "\e[32m"
  YELLOW  = "\e[33m"
  RED     = "\e[31m"
  GRAY    = "\e[90m"
  WHITE   = "\e[37m"
  MAGENTA = "\e[35m"
end
