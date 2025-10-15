# frozen_string_literal: true

require_relative "lib/canon/version"

Gem::Specification.new do |spec|
  spec.name = "canon"
  spec.version = Canon::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary       = "Library for canonicalization of serialization formats"
  spec.description   = "Library for canonicalizing and pretty-printing XML, YAML, and JSON with RSpec matchers for equivalence testing"
  spec.homepage      = "https://github.com/metanorma/canon"
  spec.license       = "BSD-2-Clause"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__,
                                             err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor
                          Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency "diff-lcs"
  spec.add_dependency "json"
  spec.add_dependency "moxml"
  spec.add_dependency "nokogiri"
  spec.add_dependency "paint"
  spec.add_dependency "thor"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage
end
