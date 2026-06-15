# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::Pipeline do
  describe ".detect_formats" do
    it "returns the hint for both sides when a hint is provided" do
      formats = described_class.detect_formats("<a/>", "<b/>", :xml)
      expect(formats).to eq(%i[xml xml])
    end

    it "auto-detects each side when no hint is provided" do
      formats = described_class.detect_formats("<root/>", "{ \"a\": 1 }", nil)
      expect(formats).to eq(%i[xml json])
    end

    it "returns the same format twice when hint matches content" do
      formats = described_class.detect_formats("{ \"a\": 1 }", "[1, 2]", :json)
      expect(formats).to eq(%i[json json])
    end
  end

  describe ".formats_compatible?" do
    it "is true when formats match exactly" do
      expect(described_class.formats_compatible?(:xml, :xml)).to be(true)
      expect(described_class.formats_compatible?(:xml, :xml,
                                                 strict: true)).to be(true)
    end

    it "accepts json <-> ruby_object in non-strict mode" do
      expect(described_class.formats_compatible?(:json,
                                                 :ruby_object)).to be(true)
      expect(described_class.formats_compatible?(:ruby_object,
                                                 :json)).to be(true)
    end

    it "accepts yaml <-> ruby_object in non-strict mode" do
      expect(described_class.formats_compatible?(:yaml,
                                                 :ruby_object)).to be(true)
    end

    it "rejects json <-> yaml even in non-strict mode" do
      expect(described_class.formats_compatible?(:json, :yaml)).to be(false)
    end

    it "rejects ruby_object cross-format pairings in strict mode" do
      expect(described_class.formats_compatible?(:json, :ruby_object,
                                                 strict: true)).to be(false)
    end

    it "rejects xml vs html in any mode" do
      expect(described_class.formats_compatible?(:xml, :html)).to be(false)
      expect(described_class.formats_compatible?(:xml, :html,
                                                 strict: true)).to be(false)
    end
  end

  describe ".validate_compatible!" do
    it "does not raise when formats match" do
      expect do
        described_class.validate_compatible!(:xml, :xml)
      end.not_to raise_error
    end

    it "raises CompareFormatMismatchError for incompatible formats" do
      expect do
        described_class.validate_compatible!(:xml, :html)
      end.to raise_error(Canon::CompareFormatMismatchError)
    end

    it "raises in strict mode for ruby_object pairings" do
      expect do
        described_class.validate_compatible!(:json, :ruby_object, strict: true)
      end.to raise_error(Canon::CompareFormatMismatchError)
    end
  end

  describe ".resolve_config", :config do
    after { Canon::Config.reset! }

    it "returns opts unchanged for non-config-backed formats" do
      opts = { format: :ruby_object }
      expect(described_class.resolve_config(:ruby_object, opts)).to eq(opts)
    end

    it "returns opts unchanged (same object) for non-config-backed formats" do
      opts = { format: :ruby_object }
      expect(described_class.resolve_config(:ruby_object, opts)
              .equal?(opts)).to be(true)
    end

    it "merges config-sourced global_profile into a copy" do
      Canon::Config.configure { |c| c.xml.match.profile = :spec_friendly }
      opts = { format: :xml }
      resolved = described_class.resolve_config(:xml, opts)
      expect(resolved[:global_profile]).to eq(:spec_friendly)
      expect(opts).not_to have_key(:global_profile)
    end

    it "preserves caller-supplied global_profile over config" do
      Canon::Config.configure { |c| c.xml.match.profile = :spec_friendly }
      opts = { format: :xml, global_profile: :strict }
      resolved = described_class.resolve_config(:xml, opts)
      expect(resolved[:global_profile]).to eq(:strict)
    end

    it "merges config-sourced profile_options under global_options" do
      Canon::Config.configure do |c|
        c.xml.match.profile = :spec_friendly
        c.xml.match.apply_profile_data(
          "preserve_whitespace_elements" => %w[pre code],
        )
      end
      opts = { format: :xml }
      resolved = described_class.resolve_config(:xml, opts)
      expect(resolved[:global_options]).to include(
        preserve_whitespace_elements: %w[pre code],
      )
    end

    it "lets caller-supplied global_options override config profile_options" do
      Canon::Config.configure do |c|
        c.xml.match.profile = :spec_friendly
        c.xml.match.apply_profile_data(
          "preserve_whitespace_elements" => %w[pre code],
        )
      end
      opts = {
        format: :xml,
        global_options: { preserve_whitespace_elements: %w[pre] },
      }
      resolved = described_class.resolve_config(:xml, opts)
      expect(resolved[:global_options][:preserve_whitespace_elements]).to eq(%w[pre])
    end

    it "does not mutate the caller's opts hash" do
      Canon::Config.configure { |c| c.xml.match.profile = :spec_friendly }
      opts = { format: :xml }
      described_class.resolve_config(:xml, opts)
      expect(opts).not_to have_key(:global_profile)
      expect(opts).not_to have_key(:global_options)
    end
  end

  describe ".capture_originals" do
    it "returns strings unchanged" do
      s1, s2 = described_class.capture_originals("<a/>", "<b/>")
      expect(s1).to eq("<a/>")
      expect(s2).to eq("<b/>")
    end

    it "serializes Canon::Xml::Node via NodeSerializer" do
      node = Canon.parse("<root><child/></root>", :xml)
      s1, _s2 = described_class.capture_originals(node, "<root/>")
      expect(s1).to include("root")
    end

    it "serializes Nokogiri::XML::Document via to_html" do
      skip "requires Nokogiri backend" unless Canon::XmlBackend.nokogiri?

      doc = Nokogiri::XML("<root/>")
      s1, _s2 = described_class.capture_originals(doc, "<root/>")
      expect(s1).to include("root")
    end

    it "falls back to to_s for unknown types" do
      obj = Struct.new(:value) do
        def to_s
          value
        end
      end.new("hello")
      s1, _s2 = described_class.capture_originals(obj, "hello")
      expect(s1).to eq("hello")
    end
  end

  describe ".parse_pair" do
    it "parses both XML strings through XmlComparator" do
      match_opts = { preprocessing: :none }
      doc1, doc2 = described_class.parse_pair("<root/>", "<root/>", :xml,
                                              match_opts)
      expect(doc1).to be_a(Canon::Xml::Node)
      expect(doc2).to be_a(Canon::Xml::Node)
    end

    it "parses both JSON strings through JsonComparator" do
      doc1, doc2 = described_class.parse_pair('{"a":1}', '{"a":2}', :json, {})
      expect(doc1).to eq("a" => 1)
      expect(doc2).to eq("a" => 2)
    end

    it "parses both YAML strings through YamlComparator" do
      doc1, doc2 = described_class.parse_pair("a: 1\n", "a: 2\n", :yaml, {})
      expect(doc1).to eq("a" => 1)
      expect(doc2).to eq("a" => 2)
    end

    it "passes through already-parsed objects" do
      node = Canon.parse("<root/>", :xml)
      doc1, _doc2 = described_class.parse_pair(node, "<root/>", :xml,
                                               { preprocessing: :none })
      expect(doc1).to be(node)
    end

    it "returns inputs unchanged for unknown formats" do
      doc1, doc2 = described_class.parse_pair(:foo, :bar, :unknown, {})
      expect(doc1).to be(:foo)
      expect(doc2).to be(:bar)
    end
  end

  describe ".preparse_html_pair" do
    it "parses HTML strings through HtmlParser with :html5" do
      obj1, obj2 = described_class.preparse_html_pair("<p>a</p>", "<p>b</p>")
      expect(obj1).not_to eq("<p>a</p>")
      expect(obj2).not_to eq("<p>b</p>")
    end

    it "passes through non-string inputs unchanged" do
      node = Canon.parse("<root/>", :xml)
      obj1, obj2 = described_class.preparse_html_pair(node, :symbol)
      expect(obj1).to be(node)
      expect(obj2).to be(:symbol)
    end
  end

  describe ".html_string?" do
    it "is true for String inputs" do
      expect(described_class.html_string?("<p/>")).to be(true)
    end

    it "is false for non-String inputs" do
      expect(described_class.html_string?(Canon.parse("<x/>",
                                                      :xml))).to be(false)
      expect(described_class.html_string?(nil)).to be(false)
      expect(described_class.html_string?(%w[a b])).to be(false)
    end
  end

  describe "constants" do
    it "CONFIG_BACKED_FORMATS includes the canonical serialization formats" do
      expect(described_class::CONFIG_BACKED_FORMATS)
        .to contain_exactly(:xml, :html, :json, :yaml, :string)
    end

    it "COMPATIBLE_FORMAT_GROUPS lists json<->ruby_object and yaml<->ruby_object" do
      expect(described_class::COMPATIBLE_FORMAT_GROUPS)
        .to include(%i[json ruby_object], %i[yaml ruby_object])
    end
  end
end
