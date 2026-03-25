# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffNodeMapper do
  describe "comment handling" do
    context "single-line comments" do
      it "maps added single-line comments to informative DiffLines" do
        xml1 = "<root>\n  <item>text</item>\n</root>"
        xml2 = "<root>\n  <!-- a comment -->\n  <item>text</item>\n</root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        comment_lines = informative_lines.select do |l|
          l.content.include?("<!--")
        end
        expect(comment_lines).not_to be_empty
        expect(diff_lines.select(&:normative?)).to be_empty
      end

      it "maps removed single-line comments to informative DiffLines" do
        xml1 = "<root>\n  <!-- a comment -->\n  <item>text</item>\n</root>"
        xml2 = "<root>\n  <item>text</item>\n</root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        comment_lines = informative_lines.select do |l|
          l.content.include?("comment")
        end
        expect(comment_lines).not_to be_empty
      end

      it "maps changed single-line comments to informative DiffLines" do
        xml1 = "<root>\n  <!-- old comment -->\n  <item>text</item>\n</root>"
        xml2 = "<root>\n  <!-- new comment -->\n  <item>text</item>\n</root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        expect(informative_lines).not_to be_empty
        expect(diff_lines.select(&:normative?)).to be_empty
      end

      it "maps inline comments to informative DiffLines" do
        xml1 = "<root><item>text<!-- inline --></item></root>"
        xml2 = "<root><item>text</item></root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        expect(informative_lines).not_to be_empty
      end
    end

    context "multi-line comments" do
      it "links ALL lines of a multi-line comment to the same DiffNode" do
        xml1 = <<~XML
          <root>
            <!--
              This is a multi-line
              comment spanning
              several lines
            -->
            <item>text</item>
          </root>
        XML
        xml2 = "<root>\n  <item>text</item>\n</root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        # All comment lines (<!--, content, --!>) should be informative
        comment_content_lines = informative_lines.select do |l|
          l.content.include?("<!--") ||
            %w[multi-line comment spanning several].any? { |w| l.content.include?(w) } ||
            (l.content.include?("--") && l.content.include?(">"))
        end
        expect(comment_content_lines.length).to eq(5)

        # All informative lines should link to the same DiffNode
        diff_nodes = comment_content_lines.map(&:diff_node).uniq
        expect(diff_nodes.length).to eq(1)
      end

      it "handles multi-line comment addition" do
        xml1 = "<root>\n  <item>text</item>\n</root>"
        xml2 = <<~XML
          <root>
            <!--
              added comment
              with multiple lines
            -->
            <item>text</item>
          </root>
        XML

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        # Should have multiple informative lines for the multi-line comment
        expect(informative_lines.length).to be >= 3
        # None should be normative
        expect(diff_lines.select(&:normative?)).to be_empty
      end
    end

    context "inline comments (start/end mid-line)" do
      it "handles comment that starts and ends on the same line with content" do
        xml1 = "<root><item>before<!-- mid -->after</item></root>"
        xml2 = "<root><item>beforeafter</item></root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        expect(informative_lines).not_to be_empty
      end

      it "handles comment that starts mid-line and continues to next line" do
        xml1 = "<root><item>text<!-- start\ncontinues\nend --></item></root>"
        xml2 = "<root><item>text</item></root>"

        result = Canon::Comparison::XmlComparator.equivalent?(
          xml1, xml2, verbose: true, match: { comments: :ignore }
        )

        diff_lines = described_class.map(
          result.differences,
          result.preprocessed_strings[0],
          result.preprocessed_strings[1],
        )

        informative_lines = diff_lines.select(&:informative?)
        # All lines of the multi-line inline comment should be informative
        expect(informative_lines.length).to be >= 2
      end
    end
  end

  describe "#build_comment_lines" do
    let(:mapper) do
      described_class.new([], "", "")
    end

    it "identifies single-line comments" do
      text = "<root>\n<!-- comment -->\n</root>"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to include(1)
      expect(lines).not_to include(0)
      expect(lines).not_to include(2)
    end

    it "identifies multi-line comment ranges" do
      text = "<root>\n<!-- line1\nline2\nline3 -->\n</root>"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to include(1, 2, 3)
      expect(lines).not_to include(0, 4)
    end

    it "handles inline comment (comment on same line as other content)" do
      text = "<item>text<!-- inline --></item>"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to include(0)
    end

    it "handles comment starting mid-line and ending on another line" do
      text = "<item>text<!-- start\ncontinues\nend --></item>"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to include(0, 1, 2)
    end

    it "handles multiple separate comments" do
      text = "<!-- first -->\n<item/>\n<!-- second -->"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to include(0, 2)
      expect(lines).not_to include(1)
    end

    it "does not mark lines after comment closes" do
      text = "<!-- comment -->\n<item>text</item>"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to include(0)
      expect(lines).not_to include(1)
    end

    it "handles empty text" do
      lines = mapper.send(:build_comment_lines, "")
      expect(lines).to be_empty
    end

    it "handles text with no comments" do
      text = "<root>\n<item>text</item>\n</root>"
      lines = mapper.send(:build_comment_lines, text)
      expect(lines).to be_empty
    end
  end
end
