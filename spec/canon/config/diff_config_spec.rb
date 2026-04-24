# frozen_string_literal: true

require "spec_helper"
require "canon/config"

RSpec.describe Canon::Config::DiffConfig do
  subject(:config) { described_class.new(:xml) }

  before do
    ENV.keys.grep(/^CANON_/).each { |key| ENV.delete(key) }
    allow(Canon::ColorDetector).to receive(:supports_color?).and_return(true)
  end

  after do
    ENV.keys.grep(/^CANON_/).each { |key| ENV.delete(key) }
  end

  # ── display_preprocessing ──────────────────────────────────────────────────

  describe "#display_preprocessing" do
    it "defaults to :none" do
      expect(config.display_preprocessing).to eq(:none)
    end

    it "can be set to :pretty_print" do
      config.display_preprocessing = :pretty_print
      expect(config.display_preprocessing).to eq(:pretty_print)
    end

    it "can be set to :c14n" do
      config.display_preprocessing = :c14n
      expect(config.display_preprocessing).to eq(:c14n)
    end

    it "is reset to :none after reset!" do
      config.display_preprocessing = :pretty_print
      config.reset!
      expect(config.display_preprocessing).to eq(:none)
    end

    it "is overridden by CANON_XML_DIFF_DISPLAY_PREPROCESSING" do
      ENV["CANON_XML_DIFF_DISPLAY_PREPROCESSING"] = "pretty_print"
      cfg = described_class.new(:xml)
      expect(cfg.display_preprocessing).to eq(:pretty_print)
    end

    it "is overridden by the global CANON_DISPLAY_PREPROCESSING" do
      ENV["CANON_DISPLAY_PREPROCESSING"] = "c14n"
      cfg = described_class.new(:xml)
      expect(cfg.display_preprocessing).to eq(:c14n)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_DISPLAY_PREPROCESSING"] = "c14n"
      ENV["CANON_XML_DIFF_DISPLAY_PREPROCESSING"] = "pretty_print"
      cfg = described_class.new(:xml)
      expect(cfg.display_preprocessing).to eq(:pretty_print)
    end
  end

  # ── PrettyPrinterConfig ────────────────────────────────────────────────────

  describe "#pretty_printer" do
    it "returns a PrettyPrinterConfig" do
      expect(config.pretty_printer).to be_a(Canon::Config::PrettyPrinterConfig)
    end

    describe "#indent" do
      it "defaults to 2" do
        expect(config.pretty_printer.indent).to eq(2)
      end

      it "can be set" do
        config.pretty_printer.indent = 4
        expect(config.pretty_printer.indent).to eq(4)
      end

      it "is reset to 2 after reset!" do
        config.pretty_printer.indent = 4
        config.reset!
        expect(config.pretty_printer.indent).to eq(2)
      end

      it "is overridden by CANON_XML_DIFF_PRETTY_PRINTER_INDENT" do
        ENV["CANON_XML_DIFF_PRETTY_PRINTER_INDENT"] = "4"
        cfg = described_class.new(:xml)
        expect(cfg.pretty_printer.indent).to eq(4)
      end

      it "is overridden by global CANON_PRETTY_PRINTER_INDENT" do
        ENV["CANON_PRETTY_PRINTER_INDENT"] = "4"
        cfg = described_class.new(:xml)
        expect(cfg.pretty_printer.indent).to eq(4)
      end
    end

    describe "#indent_type" do
      it "defaults to :space" do
        expect(config.pretty_printer.indent_type).to eq(:space)
      end

      it "can be set to :tab" do
        config.pretty_printer.indent_type = :tab
        expect(config.pretty_printer.indent_type).to eq(:tab)
      end

      it "is reset to :space after reset!" do
        config.pretty_printer.indent_type = :tab
        config.reset!
        expect(config.pretty_printer.indent_type).to eq(:space)
      end

      it "is overridden by CANON_XML_DIFF_PRETTY_PRINTER_INDENT_TYPE" do
        ENV["CANON_XML_DIFF_PRETTY_PRINTER_INDENT_TYPE"] = "tab"
        cfg = described_class.new(:xml)
        expect(cfg.pretty_printer.indent_type).to eq(:tab)
      end
    end

    it "pretty_printer object is replaced after reset!" do
      old_pp = config.pretty_printer
      config.reset!
      expect(config.pretty_printer).not_to be(old_pp)
    end
  end

  # ── character_visualization ───────────────────────────────────────────────

  describe "#character_visualization" do
    it "defaults to true" do
      expect(config.character_visualization).to be(true)
    end

    it "can be set to false" do
      config.character_visualization = false
      expect(config.character_visualization).to be(false)
    end

    it "can be set to :content_only" do
      config.character_visualization = :content_only
      expect(config.character_visualization).to eq(:content_only)
    end

    it "is reset to true after reset!" do
      config.character_visualization = false
      config.reset!
      expect(config.character_visualization).to be(true)
    end

    it "is overridden by CANON_XML_DIFF_CHARACTER_VISUALIZATION=false" do
      ENV["CANON_XML_DIFF_CHARACTER_VISUALIZATION"] = "false"
      cfg = described_class.new(:xml)
      expect(cfg.character_visualization).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_CHARACTER_VISUALIZATION=content_only" do
      ENV["CANON_XML_DIFF_CHARACTER_VISUALIZATION"] = "content_only"
      cfg = described_class.new(:xml)
      expect(cfg.character_visualization).to eq(:content_only)
    end
  end

  # ── to_h ──────────────────────────────────────────────────────────────────

  describe "#to_h" do
    it "includes display_preprocessing" do
      expect(config.to_h).to include(display_preprocessing: :none)
    end

    it "includes pretty_printer_indent" do
      expect(config.to_h).to include(pretty_printer_indent: 2)
    end

    it "includes pretty_printer_indent_type" do
      expect(config.to_h).to include(pretty_printer_indent_type: :space)
    end

    it "includes character_visualization" do
      expect(config.to_h).to include(character_visualization: true)
    end

    it "reflects programmatic changes" do
      config.display_preprocessing = :pretty_print
      config.pretty_printer.indent = 4
      config.pretty_printer.indent_type = :tab
      config.character_visualization = false

      hash = config.to_h
      expect(hash[:display_preprocessing]).to eq(:pretty_print)
      expect(hash[:pretty_printer_indent]).to eq(4)
      expect(hash[:pretty_printer_indent_type]).to eq(:tab)
      expect(hash[:character_visualization]).to be(false)
    end
  end

  # ── integration with Canon::Config ────────────────────────────────────────

  describe "via Canon::Config.instance" do
    after { Canon::Config.reset! }

    it "is accessible on xml format config" do
      Canon::Config.instance.xml.diff.display_preprocessing = :pretty_print
      expect(Canon::Config.instance.xml.diff.display_preprocessing).to eq(:pretty_print)
    end

    it "does not leak between formats" do
      Canon::Config.instance.xml.diff.display_preprocessing = :pretty_print
      expect(Canon::Config.instance.html.diff.display_preprocessing).to eq(:none)
    end

    it "is reset by Canon::Config.reset!" do
      Canon::Config.instance.xml.diff.display_preprocessing = :pretty_print
      Canon::Config.reset!
      expect(Canon::Config.instance.xml.diff.display_preprocessing).to eq(:none)
    end

    it "html.diff.display_preprocessing is independently settable" do
      Canon::Config.instance.html.diff.display_preprocessing = :pretty_print
      expect(Canon::Config.instance.html.diff.display_preprocessing).to eq(:pretty_print)
    end

    it "html.diff.character_visualization is independently settable" do
      Canon::Config.instance.html.diff.character_visualization = false
      expect(Canon::Config.instance.html.diff.character_visualization).to be(false)
    end

    it "html.diff settings do not leak to xml.diff" do
      Canon::Config.instance.html.diff.display_preprocessing = :c14n
      Canon::Config.instance.html.diff.character_visualization = false
      expect(Canon::Config.instance.xml.diff.display_preprocessing).to eq(:none)
      expect(Canon::Config.instance.xml.diff.character_visualization).to be(true)
    end

    it "xml.diff settings do not leak to html.diff" do
      Canon::Config.instance.xml.diff.display_preprocessing = :pretty_print
      Canon::Config.instance.xml.diff.character_visualization = false
      expect(Canon::Config.instance.html.diff.display_preprocessing).to eq(:none)
      expect(Canon::Config.instance.html.diff.character_visualization).to be(true)
    end

    it "html.diff is reset by Canon::Config.reset!" do
      Canon::Config.instance.html.diff.display_preprocessing = :pretty_print
      Canon::Config.instance.html.diff.character_visualization = false
      Canon::Config.reset!
      expect(Canon::Config.instance.html.diff.display_preprocessing).to eq(:none)
      expect(Canon::Config.instance.html.diff.character_visualization).to be(true)
    end
  end

  # ── HTML format ENV overrides ──────────────────────────────────────────────

  context "for :html format" do
    subject(:html_config) { described_class.new(:html) }

    # ── display_preprocessing (HTML) ─────────────────────────────────────────

    describe "#display_preprocessing" do
      it "defaults to :none for HTML" do
        expect(html_config.display_preprocessing).to eq(:none)
      end

      it "is overridden by CANON_HTML_DIFF_DISPLAY_PREPROCESSING" do
        ENV["CANON_HTML_DIFF_DISPLAY_PREPROCESSING"] = "pretty_print"
        cfg = described_class.new(:html)
        expect(cfg.display_preprocessing).to eq(:pretty_print)
      end

      it "is overridden by CANON_HTML_DIFF_DISPLAY_PREPROCESSING=c14n" do
        ENV["CANON_HTML_DIFF_DISPLAY_PREPROCESSING"] = "c14n"
        cfg = described_class.new(:html)
        expect(cfg.display_preprocessing).to eq(:c14n)
      end

      it "HTML-specific ENV takes priority over global ENV" do
        ENV["CANON_DISPLAY_PREPROCESSING"] = "c14n"
        ENV["CANON_HTML_DIFF_DISPLAY_PREPROCESSING"] = "pretty_print"
        cfg = described_class.new(:html)
        expect(cfg.display_preprocessing).to eq(:pretty_print)
      end

      it "falls back to global ENV when no HTML-specific ENV is set" do
        ENV["CANON_DISPLAY_PREPROCESSING"] = "c14n"
        cfg = described_class.new(:html)
        expect(cfg.display_preprocessing).to eq(:c14n)
      end

      it "HTML ENV does not affect XML config" do
        ENV["CANON_HTML_DIFF_DISPLAY_PREPROCESSING"] = "pretty_print"
        xml_cfg = described_class.new(:xml)
        expect(xml_cfg.display_preprocessing).to eq(:none)
      end
    end

    # ── character_visualization (HTML) ───────────────────────────────────────

    describe "#character_visualization" do
      it "defaults to true for HTML" do
        expect(html_config.character_visualization).to be(true)
      end

      it "is overridden by CANON_HTML_DIFF_CHARACTER_VISUALIZATION=false" do
        ENV["CANON_HTML_DIFF_CHARACTER_VISUALIZATION"] = "false"
        cfg = described_class.new(:html)
        expect(cfg.character_visualization).to be(false)
      end

      it "is overridden by CANON_HTML_DIFF_CHARACTER_VISUALIZATION=content_only" do
        ENV["CANON_HTML_DIFF_CHARACTER_VISUALIZATION"] = "content_only"
        cfg = described_class.new(:html)
        expect(cfg.character_visualization).to eq(:content_only)
      end

      it "HTML-specific ENV takes priority over global ENV" do
        ENV["CANON_CHARACTER_VISUALIZATION"] = "false"
        ENV["CANON_HTML_DIFF_CHARACTER_VISUALIZATION"] = "content_only"
        cfg = described_class.new(:html)
        expect(cfg.character_visualization).to eq(:content_only)
      end

      it "HTML ENV does not affect XML config" do
        ENV["CANON_HTML_DIFF_CHARACTER_VISUALIZATION"] = "false"
        xml_cfg = described_class.new(:xml)
        expect(xml_cfg.character_visualization).to be(true)
      end
    end

    # ── pretty_printer (HTML) ─────────────────────────────────────────────────

    describe "#pretty_printer" do
      it "returns a PrettyPrinterConfig for HTML" do
        expect(html_config.pretty_printer).to be_a(Canon::Config::PrettyPrinterConfig)
      end

      describe "#indent" do
        it "defaults to 2 for HTML" do
          expect(html_config.pretty_printer.indent).to eq(2)
        end

        it "is overridden by CANON_HTML_DIFF_PRETTY_PRINTER_INDENT" do
          ENV["CANON_HTML_DIFF_PRETTY_PRINTER_INDENT"] = "4"
          cfg = described_class.new(:html)
          expect(cfg.pretty_printer.indent).to eq(4)
        end

        it "HTML ENV does not affect XML config indent" do
          ENV["CANON_HTML_DIFF_PRETTY_PRINTER_INDENT"] = "4"
          xml_cfg = described_class.new(:xml)
          expect(xml_cfg.pretty_printer.indent).to eq(2)
        end
      end

      describe "#indent_type" do
        it "defaults to :space for HTML" do
          expect(html_config.pretty_printer.indent_type).to eq(:space)
        end

        it "is overridden by CANON_HTML_DIFF_PRETTY_PRINTER_INDENT_TYPE" do
          ENV["CANON_HTML_DIFF_PRETTY_PRINTER_INDENT_TYPE"] = "tab"
          cfg = described_class.new(:html)
          expect(cfg.pretty_printer.indent_type).to eq(:tab)
        end

        it "HTML ENV does not affect XML config indent_type" do
          ENV["CANON_HTML_DIFF_PRETTY_PRINTER_INDENT_TYPE"] = "tab"
          xml_cfg = described_class.new(:xml)
          expect(xml_cfg.pretty_printer.indent_type).to eq(:space)
        end
      end
    end

    # ── to_h (HTML) ───────────────────────────────────────────────────────────

    describe "#to_h" do
      it "includes all new keys for HTML config" do
        expect(html_config.to_h).to include(
          display_preprocessing: :none,
          character_visualization: true,
          pretty_printer_indent: 2,
          pretty_printer_indent_type: :space,
        )
      end
    end
  end

  # ── compact_semantic_report ────────────────────────────────────────────────

  describe "#compact_semantic_report" do
    it "defaults to false" do
      expect(config.compact_semantic_report).to be(false)
    end

    it "can be set to true programmatically" do
      config.compact_semantic_report = true
      expect(config.compact_semantic_report).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(compact_semantic_report: false)
    end

    it "is reset to false after reset!" do
      config.compact_semantic_report = true
      config.reset!
      expect(config.compact_semantic_report).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_COMPACT_SEMANTIC_REPORT" do
      ENV["CANON_XML_DIFF_COMPACT_SEMANTIC_REPORT"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.compact_semantic_report).to be(true)
    end

    it "is overridden by the global CANON_COMPACT_SEMANTIC_REPORT" do
      ENV["CANON_COMPACT_SEMANTIC_REPORT"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.compact_semantic_report).to be(true)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_COMPACT_SEMANTIC_REPORT"] = "false"
      ENV["CANON_XML_DIFF_COMPACT_SEMANTIC_REPORT"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.compact_semantic_report).to be(true)
    end
  end

  # ── expand_difference ─────────────────────────────────────────────────────

  describe "#expand_difference" do
    it "defaults to false" do
      expect(config.expand_difference).to be(false)
    end

    it "can be set to true programmatically" do
      config.expand_difference = true
      expect(config.expand_difference).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(expand_difference: false)
    end

    it "is reset to false after reset!" do
      config.expand_difference = true
      config.reset!
      expect(config.expand_difference).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_EXPAND_DIFFERENCE" do
      ENV["CANON_XML_DIFF_EXPAND_DIFFERENCE"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.expand_difference).to be(true)
    end

    it "is overridden by the global CANON_EXPAND_DIFFERENCE" do
      ENV["CANON_EXPAND_DIFFERENCE"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.expand_difference).to be(true)
    end
  end

  # ── show_preprocessed_expected ────────────────────────────────────────────

  describe "#show_preprocessed_expected" do
    it "defaults to false" do
      expect(config.show_preprocessed_expected).to be(false)
    end

    it "can be set to true programmatically" do
      config.show_preprocessed_expected = true
      expect(config.show_preprocessed_expected).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(show_preprocessed_expected: false)
    end

    it "is reset to false after reset!" do
      config.show_preprocessed_expected = true
      config.reset!
      expect(config.show_preprocessed_expected).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_SHOW_PREPROCESSED_EXPECTED" do
      ENV["CANON_XML_DIFF_SHOW_PREPROCESSED_EXPECTED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_preprocessed_expected).to be(true)
    end

    it "is overridden by the global CANON_SHOW_PREPROCESSED_EXPECTED" do
      ENV["CANON_SHOW_PREPROCESSED_EXPECTED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_preprocessed_expected).to be(true)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_SHOW_PREPROCESSED_EXPECTED"] = "false"
      ENV["CANON_XML_DIFF_SHOW_PREPROCESSED_EXPECTED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_preprocessed_expected).to be(true)
    end
  end

  # ── show_preprocessed_received ────────────────────────────────────────────

  describe "#show_preprocessed_received" do
    it "defaults to false" do
      expect(config.show_preprocessed_received).to be(false)
    end

    it "can be set to true programmatically" do
      config.show_preprocessed_received = true
      expect(config.show_preprocessed_received).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(show_preprocessed_received: false)
    end

    it "is reset to false after reset!" do
      config.show_preprocessed_received = true
      config.reset!
      expect(config.show_preprocessed_received).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_SHOW_PREPROCESSED_RECEIVED" do
      ENV["CANON_XML_DIFF_SHOW_PREPROCESSED_RECEIVED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_preprocessed_received).to be(true)
    end

    it "is overridden by the global CANON_SHOW_PREPROCESSED_RECEIVED" do
      ENV["CANON_SHOW_PREPROCESSED_RECEIVED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_preprocessed_received).to be(true)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_SHOW_PREPROCESSED_RECEIVED"] = "false"
      ENV["CANON_XML_DIFF_SHOW_PREPROCESSED_RECEIVED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_preprocessed_received).to be(true)
    end
  end

  # ── show_prettyprint_inputs ───────────────────────────────────────────────

  describe "#show_prettyprint_inputs" do
    it "defaults to false" do
      expect(config.show_prettyprint_inputs).to be(false)
    end

    it "can be set to true programmatically" do
      config.show_prettyprint_inputs = true
      expect(config.show_prettyprint_inputs).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(show_prettyprint_inputs: false)
    end

    it "is reset to false after reset!" do
      config.show_prettyprint_inputs = true
      config.reset!
      expect(config.show_prettyprint_inputs).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_SHOW_PRETTYPRINT_INPUTS" do
      ENV["CANON_XML_DIFF_SHOW_PRETTYPRINT_INPUTS"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_inputs).to be(true)
    end

    it "is overridden by the global CANON_SHOW_PRETTYPRINT_INPUTS" do
      ENV["CANON_SHOW_PRETTYPRINT_INPUTS"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_inputs).to be(true)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_SHOW_PRETTYPRINT_INPUTS"] = "false"
      ENV["CANON_XML_DIFF_SHOW_PRETTYPRINT_INPUTS"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_inputs).to be(true)
    end
  end

  # ── show_prettyprint_expected ─────────────────────────────────────────────

  describe "#show_prettyprint_expected" do
    it "defaults to false" do
      expect(config.show_prettyprint_expected).to be(false)
    end

    it "can be set to true programmatically" do
      config.show_prettyprint_expected = true
      expect(config.show_prettyprint_expected).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(show_prettyprint_expected: false)
    end

    it "is reset to false after reset!" do
      config.show_prettyprint_expected = true
      config.reset!
      expect(config.show_prettyprint_expected).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_SHOW_PRETTYPRINT_EXPECTED" do
      ENV["CANON_XML_DIFF_SHOW_PRETTYPRINT_EXPECTED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_expected).to be(true)
    end

    it "is overridden by the global CANON_SHOW_PRETTYPRINT_EXPECTED" do
      ENV["CANON_SHOW_PRETTYPRINT_EXPECTED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_expected).to be(true)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_SHOW_PRETTYPRINT_EXPECTED"] = "false"
      ENV["CANON_XML_DIFF_SHOW_PRETTYPRINT_EXPECTED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_expected).to be(true)
    end
  end

  # ── show_prettyprint_received ─────────────────────────────────────────────

  describe "#show_prettyprint_received" do
    it "defaults to false" do
      expect(config.show_prettyprint_received).to be(false)
    end

    it "can be set to true programmatically" do
      config.show_prettyprint_received = true
      expect(config.show_prettyprint_received).to be(true)
    end

    it "is included in to_h" do
      expect(config.to_h).to include(show_prettyprint_received: false)
    end

    it "is reset to false after reset!" do
      config.show_prettyprint_received = true
      config.reset!
      expect(config.show_prettyprint_received).to be(false)
    end

    it "is overridden by CANON_XML_DIFF_SHOW_PRETTYPRINT_RECEIVED" do
      ENV["CANON_XML_DIFF_SHOW_PRETTYPRINT_RECEIVED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_received).to be(true)
    end

    it "is overridden by the global CANON_SHOW_PRETTYPRINT_RECEIVED" do
      ENV["CANON_SHOW_PRETTYPRINT_RECEIVED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_received).to be(true)
    end

    it "format-specific ENV takes priority over global ENV" do
      ENV["CANON_SHOW_PRETTYPRINT_RECEIVED"] = "false"
      ENV["CANON_XML_DIFF_SHOW_PRETTYPRINT_RECEIVED"] = "true"
      cfg = described_class.new(:xml)
      expect(cfg.show_prettyprint_received).to be(true)
    end
  end

  # ── Enum validation ─────────────────────────────────────────────────────────

  describe "enum validation" do
    describe ".validate_config_value!" do
      it "accepts valid mode values" do
        expect do
          described_class.validate_config_value!(:mode, :by_line)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:mode, :by_object)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:mode,
                                                 :pretty_diff)
        end.not_to raise_error
      end

      it "rejects invalid mode values" do
        expect { described_class.validate_config_value!(:mode, :foo) }
          .to raise_error(ArgumentError, /Invalid value :foo for mode/)
      end

      it "accepts valid show_diffs values" do
        expect do
          described_class.validate_config_value!(:show_diffs, :all)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:show_diffs,
                                                 :normative)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:show_diffs,
                                                 :informative)
        end.not_to raise_error
      end

      it "rejects invalid show_diffs values" do
        expect { described_class.validate_config_value!(:show_diffs, :foo) }
          .to raise_error(ArgumentError, /Invalid value :foo for show_diffs/)
      end

      it "accepts valid algorithm values" do
        expect do
          described_class.validate_config_value!(:algorithm, :dom)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:algorithm,
                                                 :semantic)
        end.not_to raise_error
      end

      it "rejects invalid algorithm values" do
        expect { described_class.validate_config_value!(:algorithm, :foo) }
          .to raise_error(ArgumentError, /Invalid value :foo for algorithm/)
      end

      it "accepts valid theme values" do
        %i[light dark retro claude cyberpunk].each do |val|
          expect do
            described_class.validate_config_value!(:theme, val)
          end.not_to raise_error
        end
      end

      it "rejects invalid theme values" do
        expect { described_class.validate_config_value!(:theme, :foo) }
          .to raise_error(ArgumentError, /Invalid value :foo for theme/)
      end

      it "accepts valid indent_type values" do
        expect do
          described_class.validate_config_value!(:pretty_printer_indent_type,
                                                 :space)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:pretty_printer_indent_type,
                                                 :tab)
        end.not_to raise_error
      end

      it "rejects invalid indent_type values" do
        expect do
          described_class.validate_config_value!(:pretty_printer_indent_type,
                                                 :foo)
        end
          .to raise_error(ArgumentError,
                          /Invalid value :foo for pretty_printer_indent_type/)
      end

      it "accepts valid character_visualization values" do
        expect do
          described_class.validate_config_value!(:character_visualization,
                                                 true)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:character_visualization,
                                                 false)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:character_visualization,
                                                 :content_only)
        end.not_to raise_error
      end

      it "rejects invalid character_visualization values" do
        expect do
          described_class.validate_config_value!(:character_visualization, :foo)
        end
          .to raise_error(ArgumentError,
                          /Invalid value :foo for character_visualization/)
      end

      it "accepts valid display_preprocessing values" do
        expect do
          described_class.validate_config_value!(:display_preprocessing,
                                                 :none)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:display_preprocessing,
                                                 :pretty_print)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:display_preprocessing,
                                                 :normalize_pretty_print)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:display_preprocessing,
                                                 :c14n)
        end.not_to raise_error
      end

      it "accepts valid display_format values" do
        expect do
          described_class.validate_config_value!(:display_format,
                                                 :raw)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:display_format,
                                                 :canonical)
        end.not_to raise_error
      end

      it "rejects keys with no defined enum (no-op)" do
        expect do
          described_class.validate_config_value!(:max_file_size, 99)
        end.not_to raise_error
        expect do
          described_class.validate_config_value!(:context_lines, 5)
        end.not_to raise_error
      end
    end

    describe "setter validation" do
      it "mode= raises on invalid value" do
        expect { config.mode = :foo }
          .to raise_error(ArgumentError, /Invalid value :foo for mode/)
      end

      it "show_diffs= raises on invalid value" do
        expect { config.show_diffs = :foo }
          .to raise_error(ArgumentError, /Invalid value :foo for show_diffs/)
      end

      it "algorithm= raises on invalid value" do
        expect { config.algorithm = :foo }
          .to raise_error(ArgumentError, /Invalid value :foo for algorithm/)
      end

      it "theme= raises on invalid value" do
        expect { config.theme = :foo }
          .to raise_error(ArgumentError, /Invalid value :foo for theme/)
      end

      it "pretty_printer.indent_type= raises on invalid value" do
        expect { config.pretty_printer.indent_type = :foo }
          .to raise_error(ArgumentError,
                          /Invalid value :foo for pretty_printer_indent_type/)
      end

      it "display_preprocessing= raises on invalid value" do
        expect { config.display_preprocessing = :foo }
          .to raise_error(ArgumentError,
                          /Invalid value :foo for display_preprocessing/)
      end

      it "display_format= raises on invalid value" do
        expect { config.display_format = :foo }
          .to raise_error(ArgumentError,
                          /Invalid value :foo for display_format/)
      end

      it "character_visualization= raises on invalid value" do
        expect { config.character_visualization = :foo }
          .to raise_error(ArgumentError,
                          /Invalid value :foo for character_visualization/)
      end

      it "apply_profile_data raises on invalid value" do
        expect { config.apply_profile_data({ mode: :foo }) }
          .to raise_error(ArgumentError, /Invalid value :foo for mode/)
      end

      it "setters accept valid values without raising" do
        expect { config.mode = :by_object }.not_to raise_error
        expect { config.show_diffs = :normative }.not_to raise_error
        expect { config.algorithm = :semantic }.not_to raise_error
        expect { config.theme = :dark }.not_to raise_error
        expect { config.pretty_printer.indent_type = :tab }.not_to raise_error
        expect do
          config.display_preprocessing = :pretty_print
        end.not_to raise_error
        expect { config.display_format = :canonical }.not_to raise_error
        expect do
          config.character_visualization = :content_only
        end.not_to raise_error
      end
    end
  end
end
