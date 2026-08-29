# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Xml::WhitespacePolicy do
  def dom_keep?(content, preserve: false, element_parent: true)
    described_class.keep_dom_text?(content, preserve_whitespace: preserve, element_parent: element_parent)
  end

  def sax_keep?(content, preserve: false, element_parent: true)
    described_class.keep_sax_text?(content, preserve_whitespace: preserve, element_parent: element_parent)
  end

  describe "shared shape" do
    it "keeps non-whitespace content" do
      expect(dom_keep?("text")).to be true
      expect(sax_keep?("text")).to be true
    end

    it "keeps anything when preserving" do
      expect(dom_keep?("   ", preserve: true)).to be true
      expect(sax_keep?("   ", preserve: true)).to be true
    end

    it "keeps whitespace-only content at document level" do
      expect(dom_keep?("  ", element_parent: false)).to be true
      expect(sax_keep?("  ", element_parent: false)).to be true
    end

    it "drops pure ASCII whitespace runs under elements" do
      expect(dom_keep?(" \t\n ")).to be false
      expect(sax_keep?(" \t\n ")).to be false
    end

    it "keeps non-ASCII whitespace (NBSP, U+3000) as meaningful content" do
      expect(dom_keep?(" ")).to be true
      expect(dom_keep?("　")).to be true
      expect(sax_keep?(" ")).to be true
      expect(sax_keep?("　")).to be true
    end
  end

  describe "the DOM/SAX delta: CR-bearing content" do
    it "SAX keeps CR-only nodes (&#xD; must survive for C14N)" do
      expect(sax_keep?("\r")).to be true
      expect(sax_keep?("x\ry")).to be true
    end

    it "DOM drops CR-only nodes (pre-existing behavior, now visible here)" do
      expect(dom_keep?("\r")).to be false
    end
  end
end
