# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in xml-c14n.gemspec
gemspec

gem "benchmark-ips"
gem "leptris" # dev-only here: optional accelerator; moxml picks it up when installed
gem "openssl", "~> 3.0"
gem "rake"
gem "rspec"
gem "rubocop"
gem "rubocop-performance"
gem "rubocop-rake"
gem "rubocop-rspec"

# Optional YAML engine (CANON_YAML_BACKEND=yeptris). Requires a
# loadable libyeptris (YEPTRIS_LIB_PATH or the vendored platform gem);
# canon degrades to Psych when it is absent.
group :yeptris do
  gem "yeptris"
end

group :opal do
  gem "opal", "~> 1.8"
  gem "opal-rspec", "~> 1.0"
  gem "opal-sprockets"
  gem "rexml"
end
