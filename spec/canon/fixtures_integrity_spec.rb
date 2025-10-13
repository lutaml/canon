# frozen_string_literal: true

require "spec_helper"
require "canon/xml/pretty_printer"
require "canon/json/pretty_printer"
require "canon/html/pretty_printer"

RSpec.describe "Fixture Files Integrity" do
  def xhtml?(content)
    content.match?(/<!DOCTYPE\s+html\s+PUBLIC.*XHTML/i) ||
      content.include?('xmlns="http://www.w3.org/1999/xhtml"')
  end

  describe "XML fixtures" do
    context "with c14n mode" do
      Dir.glob("spec/fixtures/xml/*.xml").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)
          original_doc = Nokogiri::XML(original_content)

          # Format with c14n mode
          formatted_content = Canon.format(original_content, :xml)
          formatted_doc = Nokogiri::XML(formatted_content)

          # Use CompareXML directly (don't trust our own matchers)
          result = CompareXML.equivalent?(
            original_doc,
            formatted_doc,
            {
              collapse_whitespace: true,
              ignore_attr_order: true,
              verbose: true,
            },
          )
          expect(result).to be_empty, "XML structures differ: #{result.inspect}"
        end
      end
    end

    context "with pretty mode" do
      Dir.glob("spec/fixtures/xml/*.xml").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)
          original_doc = Nokogiri::XML(original_content)

          # Format with pretty mode
          pretty_printer = Canon::Xml::PrettyPrinter.new(indent: 2)
          formatted_content = pretty_printer.format(original_content)
          formatted_doc = Nokogiri::XML(formatted_content)

          # Use CompareXML directly (don't trust our own matchers)
          result = CompareXML.equivalent?(
            original_doc,
            formatted_doc,
            {
              collapse_whitespace: true,
              ignore_attr_order: true,
              verbose: true,
            },
          )
          expect(result).to be_empty, "XML structures differ: #{result.inspect}"
        end
      end
    end
  end

  describe "HTML fixtures" do
    context "with c14n mode" do
      Dir.glob("spec/fixtures/html/*.html").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)

          # Format with c14n mode
          formatted_content = Canon.format(original_content, :html)

          # Parse both with Nokogiri directly (not Canon.parse)
          if xhtml?(original_content)
            original_doc = Nokogiri::XML(original_content)
            formatted_doc = Nokogiri::XML(formatted_content)
          else
            original_doc = Nokogiri::HTML5(original_content)
            formatted_doc = Nokogiri::HTML5(formatted_content)
          end

          # Compare text content (main verification)
          expect(formatted_doc.text.gsub(/\s+/, " ").strip)
            .to eq(original_doc.text.gsub(/\s+/, " ").strip)

          # Verify structure is maintained by checking element counts
          expect(formatted_doc.css("*").length)
            .to eq(original_doc.css("*").length)
        end
      end
    end

    context "with pretty mode" do
      Dir.glob("spec/fixtures/html/*.html").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)

          # Format with pretty mode
          pretty_printer = Canon::Html::PrettyPrinter.new(indent: 2)
          formatted_content = pretty_printer.format(original_content)

          # Parse both with Nokogiri directly (not Canon.parse)
          if xhtml?(original_content)
            original_doc = Nokogiri::XML(original_content)
            formatted_doc = Nokogiri::XML(formatted_content)
          else
            original_doc = Nokogiri::HTML5(original_content)
            formatted_doc = Nokogiri::HTML5(formatted_content)
          end

          # Compare text content (main verification)
          expect(formatted_doc.text.gsub(/\s+/, " ").strip)
            .to eq(original_doc.text.gsub(/\s+/, " ").strip)

          # Verify structure is maintained by checking element counts
          expect(formatted_doc.css("*").length)
            .to eq(original_doc.css("*").length)
        end
      end
    end
  end

  describe "JSON fixtures" do
    context "with c14n mode" do
      Dir.glob("spec/fixtures/json/*.json").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)
          original_obj = JSON.parse(original_content)

          # Format with c14n mode
          formatted_content = Canon.format(original_content, :json)
          formatted_obj = JSON.parse(formatted_content)

          # Deep comparison of objects (using Ruby's JSON parser, not Canon)
          expect(formatted_obj).to eq(original_obj)
        end
      end
    end

    context "with pretty mode" do
      Dir.glob("spec/fixtures/json/*.json").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)
          original_obj = JSON.parse(original_content)

          # Format with pretty mode
          pretty_printer = Canon::Json::PrettyPrinter.new(indent: 2)
          formatted_content = pretty_printer.format(original_content)
          formatted_obj = JSON.parse(formatted_content)

          # Deep comparison of objects (using Ruby's JSON parser, not Canon)
          expect(formatted_obj).to eq(original_obj)
        end
      end
    end
  end

  describe "YAML fixtures" do
    context "with c14n mode" do
      Dir.glob("spec/fixtures/yaml/*.yaml").each do |fixture_file|
        it "preserves all information in #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)
          original_obj = YAML.safe_load(original_content)

          # Format with c14n mode
          formatted_content = Canon.format(original_content, :yaml)
          formatted_obj = YAML.safe_load(formatted_content)

          # Deep comparison of objects (using Ruby's YAML parser, not Canon)
          expect(formatted_obj).to eq(original_obj)
        end
      end
    end
  end

  describe "Round-trip idempotency" do
    context "XML files" do
      Dir.glob("spec/fixtures/xml/*.xml").take(3).each do |fixture_file|
        it "produces identical output on second format for #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)

          # First format
          first_formatted = Canon.format(original_content, :xml)

          # Second format
          second_formatted = Canon.format(first_formatted, :xml)

          # Should be identical
          expect(second_formatted).to eq(first_formatted)
        end
      end
    end

    context "HTML files" do
      Dir.glob("spec/fixtures/html/*.html").take(2).each do |fixture_file|
        it "produces stable output on second format for #{File.basename(fixture_file)}" do
          original_content = File.read(fixture_file)

          # First format
          first_formatted = Canon.format(original_content, :html)

          # Second format
          second_formatted = Canon.format(first_formatted, :html)

          # Parse both with Nokogiri directly (not Canon.parse)
          if xhtml?(original_content)
            first_doc = Nokogiri::XML(first_formatted)
            second_doc = Nokogiri::XML(second_formatted)
          else
            first_doc = Nokogiri::HTML5(first_formatted)
            second_doc = Nokogiri::HTML5(second_formatted)
          end

          # Text content should be identical
          expect(second_doc.text.strip).to eq(first_doc.text.strip)
        end
      end
    end
  end
end
