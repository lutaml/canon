# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Encoding normalization" do
  describe "Canon::Comparison.equivalent? with encoding handling" do
    it "compares XML strings with same UTF-8 encoding correctly" do
      xml = "<root>日本語</root>"
      expect(Canon::Comparison.equivalent?(xml, xml)).to be true
    end

    it "compares XML in different string encodings as equivalent" do
      xml1 = "<root>日本語</root>" # UTF-8
      xml2 = "<root>日本語</root>".encode("Shift_JIS")

      # Should transcode both to UTF-8 before comparison
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "compares ISO-8859-1 encoded XML with UTF-8 as equivalent" do
      xml1 = "<root>café</root>" # UTF-8 by default
      xml2 = "<root>café</root>".encode("ISO-8859-1")

      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "handles XML with encoding declaration mismatching actual bytes" do
      # String is labeled UTF-8 but XML declares Shift_JIS
      # This is a common scenario when a file's encoding is misdetected
      xml1 = (+%(<?xml version="1.0" encoding="Shift_JIS"?><root>日本語</root>)).force_encoding("UTF-8")
      xml2 = %(<?xml version="1.0" encoding="UTF-8"?><root>日本語</root>)

      # Should normalize by detecting the declared encoding and transcoding
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "handles XML with no encoding declaration" do
      xml1 = "<root>日本語</root>"
      xml2 = "<root>日本語</root>".encode("Shift_JIS")

      # When no declaration, should still normalize
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "replaces invalid characters during transcoding" do
      # Binary garbage in a Shift_JIS string
      binary_xml = "<root>\xFF\xFE</root>".b

      # Should not raise, should transcode with replacement
      expect do
        Canon::Comparison.equivalent?(binary_xml, binary_xml)
      end.not_to raise_error
    end

    it "compares ASCII-only XML across encodings" do
      xml1 = "<root>hello</root>"
      xml2 = "<root>hello</root>".encode("ISO-8859-1")

      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "reports difference when content differs but encodings match" do
      xml1 = "<root>hello</root>"
      xml2 = "<root>world</root>"

      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be false
    end

    context "with normalize_encoding option" do
      it "transcodes to specified encoding" do
        xml1 = "<root>日本語</root>"
        xml2 = "<root>日本語</root>".encode("Shift_JIS")

        # Explicit normalize_encoding option
        expect(Canon::Comparison.equivalent?(xml1, xml2,
                                             normalize_encoding: "UTF-8")).to be true
      end
    end
  end

  describe "encoding normalization edge cases" do
    it "handles empty XML" do
      xml1 = "<root/>"
      xml2 = "<root/>".encode("UTF-16")

      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "handles XML with namespaces" do
      xml1 = %(<?xml version="1.0" encoding="UTF-8"?><root xmlns:ns="http://example.com">日本語</root>)
      xml2 = %(<?xml version="1.0" encoding="Shift_JIS"?><root xmlns:ns="http://example.com">日本語</root>)

      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "handles attributes with non-ASCII characters" do
      xml1 = %(<root title="タイトル">content</root>)
      xml2 = %(<root title="タイトル">content</root>).encode("Shift_JIS")

      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end
  end
end
