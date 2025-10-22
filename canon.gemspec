# frozen_string_literal: true

require_relative "lib/canon/version"

Gem::Specification.new do |spec|
  spec.name = "canon"
  spec.version = Canon::VERSION
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary       = "Canonicalization, formatting and comparison library for serialization formats (XML, HTML, JSON, YAML)"
  spec.description   = "Canon provides canonicalization and pretty-printing for various serialization
formats (XML, HTML, JSON, YAML), producing standardized forms suitable for
comparison, testing, digital signatures, and human-readable output."
  spec.homepage      = "https://github.com/lutaml/canon"
  spec.license       = "BSD-2-Clause"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__,
                                             err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github
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
  spec.add_dependency "table_tennis"
  spec.add_dependency "thor"
  spec.add_dependency "unicode-name"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage
end
