# frozen_string_literal: true

# Simulates "nokogiri not installed" WITHOUT uninstalling it (bundler
# would refuse to boot if a Gemfile gem were missing).
#
# A directory containing a nokogiri.rb that raises LoadError is prepended
# to $LOAD_PATH, so every `require "nokogiri"` resolves here FIRST and
# fails exactly like a missing gem — Canon::NokogiriLoader and all
# `defined?(Nokogiri)` guards see genuine absence.
#
# Enable with CANON_SIMULATE_NO_NOKOGIRI=1. Specs that genuinely need
# nokogiri are excluded via the `:requires_nokogiri` tag, applied
# automatically to known nokogiri-only spec trees (see spec_helper.rb).

blocker_dir = File.expand_path("nokogiri_blocker", __dir__)

unless $LOAD_PATH.include?(blocker_dir)
  $LOAD_PATH.unshift(blocker_dir)
end

# If nokogiri already got loaded (e.g. by another support file), the
# simulation would silently be a lie — fail loudly instead.
if defined?(Nokogiri)
  raise "CANON_SIMULATE_NO_NOKOGIRI=1 but nokogiri is already loaded"
end
