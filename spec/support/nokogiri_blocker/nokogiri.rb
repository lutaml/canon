# frozen_string_literal: true

# Load-path blocker for CANON_SIMULATE_NO_NOKOGIRI=1 (see
# spec/support/nokogiri_less.rb). This file must resolve BEFORE the real
# nokogiri and raise exactly like a missing gem would.
raise LoadError, "cannot load such file -- nokogiri (simulated absent)"
