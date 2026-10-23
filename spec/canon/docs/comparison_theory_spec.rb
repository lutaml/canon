# frozen_string_literal: true

require "spec_helper"
require "yaml"

# W6.3 review gate for docs/_references/comparison-theory.adoc
# (TODO.sota/07): the theory document must match SHIPPED behavior —
# every registry dimension and behavior token appears in the
# document, and every profile row equals the resolver's output.
# A dimension or behavior added to the registry without a §2 entry,
# or a profile change without a §3 row, fails here.
DOC_PATH = File.join(__dir__, "../../../docs/_references/comparison-theory.adoc").freeze
PROFILES = %i[strict spec_friendly rendered content_only].freeze
RESOLVERS = {
  xml: Canon::Comparison::MatchOptions::XmlResolver,
  html: Canon::Comparison::MatchOptions::XmlResolver,
  json: Canon::Comparison::MatchOptions::JsonResolver,
  yaml: Canon::Comparison::MatchOptions::YamlResolver,
}.freeze

RSpec.describe "comparison-theory document review" do
  let(:doc) { File.read(DOC_PATH) }

  it "exists" do
    expect(File.exist?(DOC_PATH)).to be(true)
  end

  it "cites every registry dimension with its valid behaviors" do
    missing = []
    %i[xml json yaml].each do |format|
      set = Canon::Comparison::Dimensions::Registry.for(format)
      set.names.each do |name|
        missing << "#{format}: dimension #{name} not cited" unless doc.include?(name.to_s)
        (set[name]&.valid_behaviors || []).each do |behavior|
          unless doc.include?(behavior.to_s)
            missing << "#{format}: behavior #{behavior} (#{name}) not cited"
          end
        end
      end
    end
    expect(missing).to be_empty, missing.join("\n")
  end

  it "cites no dimension the registry does not define" do
    known = %i[xml json yaml].flat_map do |format|
      Canon::Comparison::Dimensions::Registry.for(format).names
    end.uniq
    # every `name` backtick-quoted in the Dimensions section must be
    # a registry dimension
    section = doc.split("== 2. Dimensions")[1].to_s
      .split("== 3. Profiles").first.to_s
    cited = section.scan(/`([a-z_]+)`/).flatten.uniq
    behavior_vocab = %i[xml json yaml].flat_map do |format|
      set = Canon::Comparison::Dimensions::Registry.for(format)
      set.names.flat_map { |n| set[n]&.valid_behaviors || [] }
    end.uniq.map(&:to_s)
    extras = cited - known.map(&:to_s) - behavior_vocab - %w[html html4 html5]
    expect(extras).to be_empty,
                      "dimensions cited but not in the registry: #{extras.join(', ')}"
  end

  it "profile rows equal the resolvers' output" do
    mismatches = []
    RESOLVERS.each do |format, resolver|
      PROFILES.each do |profile|
        resolved = begin
          resolver.get_profile_options(profile)
        rescue Canon::Error
          next # a profile the format does not ship (e.g. :rendered for JSON)
        end
        next unless doc.include?("`:#{profile}`")

        resolved.each do |dimension, behavior|
          token = "#{dimension}=#{behavior}"
          next if doc.include?(token)

          mismatches << "#{format}/#{profile}: #{token} resolved but not documented"
        end
      end
    end
    expect(mismatches).to be_empty, mismatches.join("\n")
  end
end
