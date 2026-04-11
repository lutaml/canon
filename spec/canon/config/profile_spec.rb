# frozen_string_literal: true

require "spec_helper"
require "canon/config"
require "tmpdir"

RSpec.describe Canon::Config do # rubocop:disable RSpec/SpecFilePathFormat
  before do
    ENV.keys.grep(/^CANON_/).each { |key| ENV.delete(key) }
    Canon::Config::ProfileLoader.reset_cache!
    allow(Canon::ColorDetector).to receive(:supports_color?).and_return(true)
  end

  after do
    ENV.keys.grep(/^CANON_/).each { |key| ENV.delete(key) }
    Canon::Config::ProfileLoader.reset_cache!
  end

  describe "#profile=" do
    context "with :metanorma" do
      subject(:config) { described_class.new }

      before { config.profile = :metanorma }

      it "sets the profile name" do
        expect(config.profile).to eq(:metanorma)
      end

      it "sets preprocessing on both xml and html" do
        expect(config.xml.preprocessing).to eq(:format)
        expect(config.html.preprocessing).to eq(:format)
      end

      it "sets match profile" do
        expect(config.xml.match.profile).to eq(:spec_friendly)
        expect(config.html.match.profile).to eq(:spec_friendly)
      end

      it "sets shared diff options" do
        expect(config.xml.diff.show_diffs).to eq(:normative)
        expect(config.xml.diff.verbose_diff).to be(false)
        expect(config.xml.diff.context_lines).to eq(5)
        expect(config.xml.diff.mode).to eq(:pretty_diff)
        expect(config.xml.diff.algorithm).to eq(:dom)
        expect(config.xml.diff.display_format).to eq(:canonical)
        expect(config.xml.diff.display_preprocessing).to eq(:normalize_pretty_print)
        expect(config.xml.diff.compact_semantic_report).to be(true)
        expect(config.xml.diff.pretty_printed_expected).to be(true)
        expect(config.xml.diff.expand_difference).to be(true)
        expect(config.xml.diff.pretty_printer_sort_attributes).to be(true)
      end

      it "sets xml-specific whitespace elements" do
        expect(config.xml.match.collapse_whitespace_elements).to include(
          "p", "title", "fmt-title", "semx"
        )
        expect(config.xml.match.preserve_whitespace_elements).to eq(%w[body passthrough])
      end

      it "sets html-specific overrides" do
        # HTML overrides shared show_raw_inputs: false -> true
        expect(config.html.diff.show_raw_inputs).to be(true)
        expect(config.xml.diff.show_raw_inputs).to be(false)
      end

      it "does not set whitespace elements on html (not specified in profile)" do
        expect(config.html.match.collapse_whitespace_elements).to eq([])
      end

      it "applies same shared diff settings to html" do
        expect(config.html.diff.algorithm).to eq(:dom)
        expect(config.html.diff.display_format).to eq(:canonical)
        expect(config.html.diff.context_lines).to eq(5)
      end
    end

    context "with :metanorma_debug" do
      subject(:config) { described_class.new }

      before { config.profile = :metanorma_debug }

      it "inherits base metanorma settings" do
        expect(config.xml.preprocessing).to eq(:format)
        expect(config.xml.match.profile).to eq(:spec_friendly)
        expect(config.xml.diff.algorithm).to eq(:dom)
        expect(config.xml.match.collapse_whitespace_elements).to include("p", "title")
      end

      it "applies debug overrides" do
        expect(config.xml.diff.show_prettyprint_received).to be(true)
        expect(config.html.diff.show_prettyprint_received).to be(true)
      end

      it "preserves non-overridden values from parent" do
        expect(config.xml.diff.verbose_diff).to be(false)
      end
    end

    context "with a file path" do
      let(:tmpdir) { Dir.mktmpdir }

      after { FileUtils.remove_entry(tmpdir) }

      it "loads profile from file" do
        path = File.join(tmpdir, "custom.yml")
        File.write(path, <<~YAML)
          ---
          name: custom
          shared:
            preprocessing: format
            diff:
              context_lines: 42
              algorithm: semantic
        YAML

        config = described_class.new
        config.profile = path

        expect(config.profile).to eq(path)
        expect(config.xml.preprocessing).to eq(:format)
        expect(config.xml.diff.context_lines).to eq(42)
        expect(config.xml.diff.algorithm).to eq(:semantic)
      end

      it "loads file inheriting from built-in profile" do
        path = File.join(tmpdir, "extended.yml")
        File.write(path, <<~YAML)
          ---
          name: extended
          inherits: metanorma
          shared:
            diff:
              verbose_diff: true
        YAML

        config = described_class.new
        config.profile = path

        # Inherited
        expect(config.xml.diff.algorithm).to eq(:dom)
        expect(config.xml.preprocessing).to eq(:format)
        # Overridden
        expect(config.xml.diff.verbose_diff).to be(true)
      end
    end

    context "clearing profile" do
      it "reverts to defaults when set to nil" do
        config = described_class.new
        config.profile = :metanorma
        expect(config.xml.diff.context_lines).to eq(5)

        config.profile = nil
        expect(config.profile).to be_nil
        expect(config.xml.diff.context_lines).to eq(3) # default
        expect(config.xml.preprocessing).to be_nil
      end

      it "preserves programmatic values when clearing profile" do
        config = described_class.new
        config.xml.diff.algorithm = :semantic
        config.profile = :metanorma
        # ENV > programmatic > profile: programmatic wins over profile
        # But wait — algorithm was set programmatically BEFORE profile,
        # so programmatic = :semantic, profile = :dom → resolve returns :semantic
        expect(config.xml.diff.algorithm).to eq(:semantic)

        config.profile = nil
        # Programmatic still there
        expect(config.xml.diff.algorithm).to eq(:semantic)
      end
    end
  end

  describe "priority chain" do
    it "programmatic overrides profile" do
      config = described_class.new
      config.profile = :metanorma
      config.xml.diff.context_lines = 99

      expect(config.xml.diff.context_lines).to eq(99)
    end

    it "ENV overrides profile" do
      ENV["CANON_XML_DIFF_CONTEXT_LINES"] = "77"
      config = described_class.new
      config.profile = :metanorma

      expect(config.xml.diff.context_lines).to eq(77)
    end

    it "profile overrides defaults" do
      config = described_class.new
      # Default context_lines is 3
      expect(config.xml.diff.context_lines).to eq(3)

      config.profile = :metanorma
      # Profile sets it to 5
      expect(config.xml.diff.context_lines).to eq(5)
    end
  end

  describe "CANON_CONFIG_PROFILE env var" do
    it "auto-applies profile from env on initialization" do
      ENV["CANON_CONFIG_PROFILE"] = "metanorma"
      config = described_class.new

      expect(config.profile).to eq(:metanorma)
      expect(config.xml.diff.algorithm).to eq(:dom)
      expect(config.xml.preprocessing).to eq(:format)
    end

    it "supports file paths in env var" do
      tmpdir = Dir.mktmpdir
      path = File.join(tmpdir, "env_profile.yml")
      File.write(path, <<~YAML)
        ---
        name: env_profile
        shared:
          diff:
            context_lines: 88
      YAML

      ENV["CANON_CONFIG_PROFILE"] = path
      config = described_class.new
      expect(config.xml.diff.context_lines).to eq(88)
    ensure
      FileUtils.remove_entry(tmpdir)
    end
  end

  describe "#reset!" do
    it "clears profile along with everything else" do
      config = described_class.new
      config.profile = :metanorma
      config.reset!

      expect(config.profile).to be_nil
      expect(config.xml.diff.context_lines).to eq(3) # default
      expect(config.xml.preprocessing).to be_nil
    end
  end

  describe "ProfileLoader.available_profiles" do
    it "is accessible and lists built-in profiles" do
      profiles = Canon::Config::ProfileLoader.available_profiles
      expect(profiles).to include(:metanorma, :metanorma_debug)
    end
  end
end
