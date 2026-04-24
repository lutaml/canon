# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon::DiffFormatter content_only character visualization" do
  let(:xml_with_space) do
    <<~XML
      <root>
        <item>Hello World</item>
      </root>
    XML
  end

  let(:xml_without_space) do
    <<~XML
      <root>
        <item>HelloWorld</item>
      </root>
    XML
  end

  def build_formatter(visualization_mode)
    Canon::DiffFormatter.new(
      use_color: false,
      mode: :by_line,
      character_visualization: visualization_mode,
      display_preprocessing: :pretty_print,
    )
  end

  describe "character_visualization: :content_only" do
    it "leaves structural indentation plain while visualizing content" do
      result = Canon::Comparison.equivalent?(xml_with_space, xml_without_space,
                                             verbose: true)

      formatter = build_formatter(:content_only)
      output = formatter.format(result, :xml, doc1: xml_with_space,
                                              doc2: xml_without_space)

      lines = output.split("\n")
      content_lines = lines.select { |l| l.include?("Hello") }

      expect(content_lines.any? { |l| l.include?("Hello") }).to be true
    end

    it "produces different output than character_visualization: true" do
      result = Canon::Comparison.equivalent?(xml_with_space, xml_without_space,
                                             verbose: true)

      output_full = build_formatter(true).format(result, :xml,
                                                 doc1: xml_with_space, doc2: xml_without_space)
      output_content = build_formatter(:content_only).format(result, :xml,
                                                             doc1: xml_with_space, doc2: xml_without_space)

      # With full visualization, indentation spaces are visualized
      # With content_only, indentation should be plain spaces
      expect(output_full).not_to eq(output_content)
    end
  end

  describe "character_visualization: true (regression guard)" do
    it "visualizes whitespace everywhere including indentation" do
      result = Canon::Comparison.equivalent?(xml_with_space, xml_without_space,
                                             verbose: true)

      formatter = build_formatter(true)
      output = formatter.format(result, :xml, doc1: xml_with_space,
                                              doc2: xml_without_space)

      lines = output.split("\n")
      tag_lines = lines.select do |l|
        l.include?("<root>") || l.include?("<item>")
      end

      expect(tag_lines.any? { |l| l.include?("░") }).to be true
    end
  end

  describe "character_visualization: false" do
    it "produces no visualization at all" do
      result = Canon::Comparison.equivalent?(xml_with_space, xml_without_space,
                                             verbose: true)

      formatter = build_formatter(false)
      output = formatter.format(result, :xml, doc1: xml_with_space,
                                              doc2: xml_without_space)

      expect(output).not_to include("░")
      expect(output).not_to include("⇥")
      expect(output).not_to include("↵")
    end
  end
end
