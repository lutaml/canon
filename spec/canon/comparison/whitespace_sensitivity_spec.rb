# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/canon/comparison/whitespace_sensitivity"

RSpec.describe Canon::Comparison::WhitespaceSensitivity do
  describe ".element_sensitive?" do
    let(:opts) do
      {
        match_opts: {
          format: :xml,
          structural_whitespace: :strict,
          whitespace_sensitive_elements: nil,
          whitespace_insensitive_elements: nil,
          respect_xml_space: true,
        },
      }
    end

    context "with xml:space attribute" do
      it "returns true when xml:space='preserve' is set" do
        xml = <<~XML
          <root><code xml:space="preserve">  text  </code></root>
        XML

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        expect(described_class.element_sensitive?(text_node, opts)).to be true
      end

      it "returns false when xml:space='default' is set" do
        xml = <<~XML
          <root><code xml:space="default">  text  </code></root>
        XML

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        expect(described_class.element_sensitive?(text_node, opts)).to be false
      end

      it "returns false when no xml:space attribute is present" do
        xml = <<~XML
          <root><code>  text  </code></root>
        XML

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        expect(described_class.element_sensitive?(text_node, opts)).to be false
      end
    end

    context "with whitelist" do
      it "returns true for elements in whitelist" do
        xml = <<~XML
          <root><code>  text  </code></root>
        XML

        whitelist_opts = opts.dup
        whitelist_opts[:match_opts] = opts[:match_opts].merge(
          whitespace_sensitive_elements: [:code],
        )

        doc = Canon::Xml::DataModel.from_xml(xml)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  whitelist_opts)).to be true
      end

      it "returns false for elements not in whitelist" do
        xml = <<~XML
          <root><p>  text  </p></root>
        XML

        whitelist_opts = opts.dup
        whitelist_opts[:match_opts] = opts[:match_opts].merge(
          whitespace_sensitive_elements: [:code],
        )

        doc = Canon::Xml::DataModel.from_xml(xml)
        p_element = doc.children.first.children.first
        text_node = p_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  whitelist_opts)).to be false
      end
    end

    context "with blacklist" do
      it "returns false for elements in blacklist (overrides defaults)" do
        xml = <<~XML
          <root><pre>  text  </pre></root>
        XML

        blacklist_opts = opts.dup
        blacklist_opts[:match_opts] = opts[:match_opts].merge(
          format: :html,
          whitespace_insensitive_elements: [:pre],
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        pre_element = doc.children.first.children.first
        text_node = pre_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  blacklist_opts)).to be false
      end
    end

    context "with HTML format defaults" do
      it "returns true for <pre> elements" do
        xml = <<~HTML
          <root><pre>  text  </pre></root>
        HTML

        html_opts = opts.dup
        html_opts[:match_opts] = opts[:match_opts].merge(
          format: :html,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        pre_element = doc.children.first.children.first
        text_node = pre_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  html_opts)).to be true
      end

      it "returns true for <textarea> elements" do
        xml = <<~HTML
          <root><textarea>  text  </textarea></root>
        HTML

        html_opts = opts.dup
        html_opts[:match_opts] = opts[:match_opts].merge(
          format: :html,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        textarea_element = doc.children.first.children.first
        text_node = textarea_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  html_opts)).to be true
      end

      it "returns true for <script> elements" do
        xml = <<~HTML
          <root><script>  text  </script></root>
        HTML

        html_opts = opts.dup
        html_opts[:match_opts] = opts[:match_opts].merge(
          format: :html,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        script_element = doc.children.first.children.first
        text_node = script_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  html_opts)).to be true
      end

      it "returns true for <style> elements" do
        xml = <<~HTML
          <root><style>  text  </style></root>
        HTML

        html_opts = opts.dup
        html_opts[:match_opts] = opts[:match_opts].merge(
          format: :html,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        style_element = doc.children.first.children.first
        text_node = style_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  html_opts)).to be true
      end

      it "returns false for non-sensitive HTML elements" do
        xml = <<~HTML
          <root><div>  text  </div></root>
        HTML

        html_opts = opts.dup
        html_opts[:match_opts] = opts[:match_opts].merge(
          format: :html,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        div_element = doc.children.first.children.first
        text_node = div_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  html_opts)).to be false
      end
    end

    context "with XML format defaults" do
      it "returns false for all elements (no defaults)" do
        xml = <<~XML
          <root><code>  text  </code></root>
        XML

        xml_opts = opts.dup
        xml_opts[:match_opts] = opts[:match_opts].merge(
          format: :xml,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        expect(described_class.element_sensitive?(text_node,
                                                  xml_opts)).to be false
      end
    end

    context "with respect_xml_space option" do
      it "ignores xml:space when respect_xml_space is false" do
        xml = <<~XML
          <root><code xml:space="preserve">  text  </code></root>
        XML

        override_opts = opts.dup
        override_opts[:match_opts] = opts[:match_opts].merge(
          respect_xml_space: false,
        )

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        # xml:space="preserve" is ignored, no whitelist, no defaults → not sensitive
        expect(described_class.element_sensitive?(text_node,
                                                  override_opts)).to be false
      end

      it "respects xml:space when respect_xml_space is true (default)" do
        xml = <<~XML
          <root><code xml:space="preserve">  text  </code></root>
        XML

        doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
        code_element = doc.children.first.children.first
        text_node = code_element.children.first

        expect(described_class.element_sensitive?(text_node, opts)).to be true
      end
    end
  end

  describe ".preserve_whitespace_node?" do
    let(:opts) do
      {
        match_opts: {
          format: :xml,
          structural_whitespace: :strict,
          whitespace_sensitive_elements: nil,
          whitespace_insensitive_elements: nil,
          respect_xml_space: true,
        },
      }
    end

    it "returns true for whitespace-only text nodes in sensitive elements" do
      xml = <<~XML
        <root><pre>  </pre></root>
      XML

      whitelist_opts = opts.dup
      whitelist_opts[:match_opts] = opts[:match_opts].merge(
        whitespace_sensitive_elements: [:pre],
      )

      doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
      pre_element = doc.children.first.children.first
      text_node = pre_element.children.first

      expect(described_class.preserve_whitespace_node?(text_node,
                                                       whitelist_opts)).to be true
    end

    it "returns false for whitespace-only text nodes in non-sensitive elements" do
      xml = <<~XML
        <root><div>  </div></root>
      XML

      doc = Canon::Xml::DataModel.from_xml(xml, preserve_whitespace: true)
      div_element = doc.children.first.children.first
      text_node = div_element.children.first

      expect(described_class.preserve_whitespace_node?(text_node,
                                                       opts)).to be false
    end

    it "returns false for nodes without a parent" do
      node = double("Node", parent: nil)

      expect(described_class.preserve_whitespace_node?(node, opts)).to be false
    end
  end
end
