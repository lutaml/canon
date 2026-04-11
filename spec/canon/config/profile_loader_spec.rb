# frozen_string_literal: true

require "spec_helper"
require "canon/config"
require "tmpdir"

RSpec.describe Canon::Config::ProfileLoader do
  before do
    described_class.reset_cache!
  end

  after do
    described_class.reset_cache!
  end

  describe ".load" do
    context "with a built-in profile name" do
      it "loads metanorma profile" do
        data = described_class.load(:metanorma)
        expect(data["name"]).to eq("metanorma")
        expect(data["shared"]["preprocessing"]).to eq("format")
        expect(data["shared"]["diff"]["algorithm"]).to eq("dom")
      end

      it "loads metanorma_debug profile with inheritance" do
        data = described_class.load(:metanorma_debug)
        expect(data["name"]).to eq("metanorma_debug")
        # Inherited from metanorma
        expect(data["shared"]["preprocessing"]).to eq("format")
        expect(data["shared"]["diff"]["algorithm"]).to eq("dom")
        # Overridden by metanorma_debug
        expect(data["shared"]["diff"]["show_prettyprint_received"]).to be(true)
        # Inherited default not overridden
        expect(data["shared"]["diff"]["verbose_diff"]).to be(false)
      end

      it "inherits format-specific settings" do
        data = described_class.load(:metanorma_debug)
        xml_elements = data.dig("formats", "xml", "match", "collapse_whitespace_elements")
        expect(xml_elements).to include("p", "title", "fmt-title")
      end

      it "raises Canon::Error for unknown profile" do
        expect { described_class.load(:nonexistent) }.to raise_error(
          Canon::Error, /Unknown config profile: nonexistent/
        )
      end
    end

    context "with a file path" do
      let(:tmpdir) { Dir.mktmpdir }

      after { FileUtils.remove_entry(tmpdir) }

      it "loads a YAML file by absolute path" do
        path = File.join(tmpdir, "custom.yml")
        File.write(path, <<~YAML)
          ---
          name: custom
          shared:
            diff:
              context_lines: 10
        YAML

        data = described_class.load(path)
        expect(data["name"]).to eq("custom")
        expect(data["shared"]["diff"]["context_lines"]).to eq(10)
      end

      it "loads a file that inherits from a built-in profile" do
        path = File.join(tmpdir, "my_metanorma.yml")
        File.write(path, <<~YAML)
          ---
          name: my_metanorma
          inherits: metanorma
          shared:
            diff:
              context_lines: 20
              verbose_diff: true
        YAML

        data = described_class.load(path)
        # Inherited from metanorma
        expect(data["shared"]["preprocessing"]).to eq("format")
        expect(data["shared"]["diff"]["algorithm"]).to eq("dom")
        # Overridden
        expect(data["shared"]["diff"]["context_lines"]).to eq(20)
        expect(data["shared"]["diff"]["verbose_diff"]).to be(true)
        # Inherited format-specific
        expect(data.dig("formats", "xml", "match", "preserve_whitespace_elements"))
          .to eq(%w[body passthrough])
      end

      it "expands ~ in file paths" do
        # Use a path that won't exist to test expansion happens
        expect { described_class.load("~/nonexistent_canon_profile.yml") }.to raise_error(
          Canon::Error, %r{Profile file not found:.*nonexistent_canon_profile\.yml}
        )
      end

      it "raises Canon::Error for missing file" do
        expect { described_class.load("/no/such/file.yml") }.to raise_error(
          Canon::Error, /Profile file not found/
        )
      end
    end

    context "inheritance cycle detection" do
      let(:tmpdir) { Dir.mktmpdir }

      after { FileUtils.remove_entry(tmpdir) }

      it "raises Canon::Error on direct cycle" do
        path_a = File.join(tmpdir, "a.yml")
        path_b = File.join(tmpdir, "b.yml")
        File.write(path_a, "---\nname: a\ninherits: #{path_b}\n")
        File.write(path_b, "---\nname: b\ninherits: #{path_a}\n")

        expect { described_class.load(path_a) }.to raise_error(
          Canon::Error, /inheritance cycle detected/
        )
      end
    end
  end

  describe ".available_profiles" do
    it "lists built-in profiles" do
      profiles = described_class.available_profiles
      expect(profiles).to include(:metanorma, :metanorma_debug)
    end

    it "returns sorted symbols" do
      profiles = described_class.available_profiles
      expect(profiles).to eq(profiles.sort)
      expect(profiles).to all(be_a(Symbol))
    end
  end

  describe ".reset_cache!" do
    it "clears the memoized cache" do
      described_class.load(:metanorma)
      described_class.reset_cache!
      # Should not raise — just re-loads
      expect { described_class.load(:metanorma) }.not_to raise_error
    end
  end

  describe "deep merge behavior" do
    let(:tmpdir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmpdir) }

    it "replaces arrays entirely rather than concatenating" do
      path = File.join(tmpdir, "override.yml")
      File.write(path, <<~YAML)
        ---
        name: override
        inherits: metanorma
        formats:
          xml:
            diff:
              preserve_whitespace_elements:
                - pre
                - code
      YAML

      data = described_class.load(path)
      elements = data.dig("formats", "xml", "diff", "preserve_whitespace_elements")
      expect(elements).to eq(%w[pre code])
    end

    it "merges hashes recursively" do
      path = File.join(tmpdir, "partial.yml")
      File.write(path, <<~YAML)
        ---
        name: partial
        inherits: metanorma
        shared:
          diff:
            context_lines: 99
      YAML

      data = described_class.load(path)
      # Overridden
      expect(data["shared"]["diff"]["context_lines"]).to eq(99)
      # Preserved from parent
      expect(data["shared"]["diff"]["algorithm"]).to eq("dom")
    end
  end
end
