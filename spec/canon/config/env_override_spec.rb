# frozen_string_literal: true

require "spec_helper"
require "canon/config"

RSpec.describe "ENV override system" do
  before do
    # Clear any existing ENV variables
    ENV.keys.grep(/^CANON_/).each { |key| ENV.delete(key) }
    Canon::Config.reset!

    # Stub color detection to return true (as if in a TTY)
    allow(Canon::ColorDetector).to receive(:supports_color?).and_return(true)
  end

  after do
    # Clean up ENV variables
    ENV.keys.grep(/^CANON_/).each { |key| ENV.delete(key) }
    Canon::Config.reset!
  end

  describe "DiffConfig ENV overrides" do
    context "format-specific ENV variables" do
      it "overrides algorithm with CANON_XML_DIFF_ALGORITHM" do
        ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
        config = Canon::Config.new

        expect(config.xml.diff.algorithm).to eq(:semantic)
        expect(config.html.diff.algorithm).to eq(:dom) # default for other formats
      end

      it "overrides mode with CANON_JSON_DIFF_MODE" do
        ENV["CANON_JSON_DIFF_MODE"] = "by_object"
        config = Canon::Config.new

        expect(config.json.diff.mode).to eq(:by_object)
        expect(config.xml.diff.mode).to eq(:by_line) # default
      end

      it "overrides boolean with CANON_HTML_DIFF_USE_COLOR" do
        ENV["CANON_HTML_DIFF_USE_COLOR"] = "false"
        config = Canon::Config.new

        expect(config.html.diff.use_color).to be false
        expect(config.xml.diff.use_color).to be true # default
      end

      it "overrides integer with CANON_YAML_DIFF_CONTEXT_LINES" do
        ENV["CANON_YAML_DIFF_CONTEXT_LINES"] = "10"
        config = Canon::Config.new

        expect(config.yaml.diff.context_lines).to eq(10)
        expect(config.xml.diff.context_lines).to eq(3) # default
      end
    end

    context "global ENV variables" do
      it "applies CANON_ALGORITHM to all formats" do
        ENV["CANON_ALGORITHM"] = "semantic"
        config = Canon::Config.new

        expect(config.xml.diff.algorithm).to eq(:semantic)
        expect(config.html.diff.algorithm).to eq(:semantic)
        expect(config.json.diff.algorithm).to eq(:semantic)
        expect(config.yaml.diff.algorithm).to eq(:semantic)
      end

      it "applies CANON_USE_COLOR to all formats" do
        ENV["CANON_USE_COLOR"] = "false"
        config = Canon::Config.new

        expect(config.xml.diff.use_color).to be false
        expect(config.html.diff.use_color).to be false
      end
    end

    context "priority chain" do
      it "ENV overrides programmatic values" do
        ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
        config = Canon::Config.new

        config.xml.diff.algorithm = :dom
        expect(config.xml.diff.algorithm).to eq(:semantic) # ENV wins
      end

      it "format-specific ENV overrides global ENV" do
        ENV["CANON_ALGORITHM"] = "dom"
        ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
        config = Canon::Config.new

        expect(config.xml.diff.algorithm).to eq(:semantic)
        expect(config.html.diff.algorithm).to eq(:dom)
      end
    end

    context "all diff attributes" do
      it "supports verbose_diff ENV override" do
        ENV["CANON_VERBOSE_DIFF"] = "true"
        config = Canon::Config.new

        expect(config.xml.diff.verbose_diff).to be true
      end

      it "supports show_diffs ENV override" do
        ENV["CANON_SHOW_DIFFS"] = "informative"
        config = Canon::Config.new

        expect(config.xml.diff.show_diffs).to eq(:informative)
      end

      it "supports grouping_lines ENV override" do
        ENV["CANON_GROUPING_LINES"] = "20"
        config = Canon::Config.new

        expect(config.xml.diff.grouping_lines).to eq(20)
      end
    end
  end

  describe "MatchConfig ENV overrides" do
    it "overrides profile with CANON_XML_MATCH_PROFILE" do
      ENV["CANON_XML_MATCH_PROFILE"] = "ignore_whitespace"
      config = Canon::Config.new

      expect(config.xml.match.profile).to eq(:ignore_whitespace)
    end

    it "applies CANON_PROFILE globally" do
      ENV["CANON_PROFILE"] = "strict"
      config = Canon::Config.new

      expect(config.xml.match.profile).to eq(:strict)
      expect(config.html.match.profile).to eq(:strict)
    end

    it "format-specific profile overrides global" do
      ENV["CANON_PROFILE"] = "strict"
      ENV["CANON_HTML_MATCH_PROFILE"] = "ignore_whitespace"
      config = Canon::Config.new

      expect(config.xml.match.profile).to eq(:strict)
      expect(config.html.match.profile).to eq(:ignore_whitespace)
    end
  end

  describe "backward compatibility" do
    it "maintains backward compatibility methods with ENV overrides" do
      ENV["CANON_XML_DIFF_MODE"] = "by_object"
      config = Canon::Config.new

      expect(config.diff_mode).to eq(:by_object)
    end

    it "xml_match_profile respects ENV overrides" do
      ENV["CANON_XML_MATCH_PROFILE"] = "ignore_whitespace"
      config = Canon::Config.new

      expect(config.xml_match_profile).to eq(:ignore_whitespace)
    end
  end

  describe "reset functionality" do
    it "reloads ENV overrides after reset" do
      ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
      config = Canon::Config.new

      expect(config.xml.diff.algorithm).to eq(:semantic)

      ENV["CANON_XML_DIFF_ALGORITHM"] = "dom"
      config.reset!

      expect(config.xml.diff.algorithm).to eq(:dom)
    end
  end

  describe "type conversion" do
    it "converts boolean strings correctly" do
      ENV["CANON_USE_COLOR"] = "yes"
      config = Canon::Config.new
      expect(config.xml.diff.use_color).to be true

      ENV["CANON_USE_COLOR"] = "0"
      config.reset!
      expect(config.xml.diff.use_color).to be false
    end

    it "converts integer strings correctly" do
      ENV["CANON_CONTEXT_LINES"] = "15"
      config = Canon::Config.new
      expect(config.xml.diff.context_lines).to eq(15)
    end

    it "converts symbol strings correctly" do
      ENV["CANON_MODE"] = "by_object"
      config = Canon::Config.new
      expect(config.xml.diff.mode).to eq(:by_object)
    end
  end

  describe "to_h method" do
    it "includes ENV-overridden values" do
      ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
      ENV["CANON_XML_DIFF_CONTEXT_LINES"] = "10"
      config = Canon::Config.new

      hash = config.xml.diff.to_h
      expect(hash[:diff_algorithm]).to eq(:semantic)
      expect(hash[:context_lines]).to eq(10)
    end
  end
end
