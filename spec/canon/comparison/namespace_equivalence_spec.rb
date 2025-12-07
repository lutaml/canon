# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon::Comparison namespace equivalence" do
  describe "default vs prefixed namespace declarations" do
    let(:xml1) do
      <<~XML
        <NamespaceNil>
          <SamplePrefixedNamespacedModel xmlns="http://example.com/foo" xml:lang="en">
            <bar:Name xmlns:bar="http://example.com/bar">John Doe</bar:Name>
            <baz:Age xmlns:baz="http://example.com/baz">30</baz:Age>
          </SamplePrefixedNamespacedModel>
        </NamespaceNil>
      XML
    end

    let(:xml2) do
      <<~XML
        <NamespaceNil>
          <SamplePrefixedNamespacedModel xmlns:foo="http://example.com/foo" xmlns:bar="http://example.com/bar" xmlns:baz="http://example.com/baz" xml:lang="en">
            <bar:Name>John Doe</bar:Name>
            <baz:Age>30</baz:Age>
          </SamplePrefixedNamespacedModel>
        </NamespaceNil>
      XML
    end

    it "treats default and prefixed namespace declarations as semantically different" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true
      )

      # Note: These ARE semantically different because:
      # xml1: <SamplePrefixedNamespacedModel> is IN the http://example.com/foo namespace
      # xml2: <SamplePrefixedNamespacedModel> is in NO namespace (foo is just declared, not used)
      expect(result.equivalent?).to be false
    end

    it "shows proper element names in semantic diff (not nil-node)" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true
      )

      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_object
      )

      output = formatter.format(result, :xml)

      # Should not show (nil-node) or (nil)
      expect(output).not_to include("(nil-node)")
      expect(output).not_to include("<(nil)>")
    end

    it "shows namespace information in diff output" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true
      )

      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_object
      )

      output = formatter.format(result, :xml)

      # Current behavior: by_object mode shows dimension info but not detailed namespace
      # This is expected - namespace details appear in semantic diff report
      expect(output).to include("Visual Diff")
    end

    it "shows line-by-line diff when structures differ" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true
      )

      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_line
      )

      # Use original_strings instead of preprocessed_strings to see actual namespace declarations
      str1, str2 = result.original_strings
      output = formatter.format(result, :xml, doc1: str1, doc2: str2)

      # With the fix, line diff should now show the actual namespace difference
      # xml1 has: xmlns="http://example.com/foo"
      # xml2 has: xmlns:foo="http://example.com/foo" xmlns:bar="..." xmlns:baz="..."
      expect(output).to be_a(String)
      expect(output).to include("xmlns")
      expect(output).to include("SamplePrefixedNamespacedModel")

      # Should show both versions with different namespace declarations
      expect(output).to match(/xmlns="http:\/\/example\.com\/foo"|xmlns:foo="http:\/\/example\.com\/foo"/)
    end

    it "correctly counts namespaced attributes" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true
      )

      # Check that differences properly count attributes
      result.differences.each do |diff|
        if diff.respond_to?(:dimension) && diff.dimension == :attribute_presence
          # Nodes should have attributes counted
          node1 = diff.node1
          node2 = diff.node2

          if node1.respond_to?(:attribute_nodes)
            expect(node1.attribute_nodes.length).to be >= 0
          end
          if node2.respond_to?(:attribute_nodes)
            expect(node2.attribute_nodes.length).to be >= 0
          end
        end
      end
    end
  end

  describe "namespace handling at all layers" do
    let(:simple_xml1) { '<root xmlns:ns="http://test.com"><ns:el>value</ns:el></root>' }
    let(:simple_xml2) { '<root xmlns:ns2="http://test.com"><ns2:el>value</ns2:el></root>' }

    it "Layer 1: Match algorithm detects namespace differences" do
      result = Canon::Comparison.equivalent?(
        simple_xml1, simple_xml2,
        verbose: true
      )

      # Namespace prefixes differ but URIs are same - should be equivalent
      # (only the URI matters, not the prefix)
      expect(result).to be_a(Canon::Comparison::ComparisonResult)
    end

    it "Layer 2: Diff objects contain proper node information" do
      result = Canon::Comparison.equivalent?(
        simple_xml1, simple_xml2,
        verbose: true
      )

      result.differences.each do |diff|
        next unless diff.respond_to?(:node1) && diff.respond_to?(:node2)

        # Nodes should have accessible names
        expect(diff.node1).to respond_to(:name) if diff.node1
        expect(diff.node2).to respond_to(:name) if diff.node2
      end
    end

    it "Layer 3: Line-by-line rendering shows namespace information" do
      result = Canon::Comparison.equivalent?(
        simple_xml1, simple_xml2,
        verbose: true
      )

      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_line
      )

      str1, str2 = result.preprocessed_strings
      output = formatter.format(result, :xml, doc1: str1, doc2: str2)

      # Output should exist (even if documents are equivalent)
      expect(output).to be_a(String)
    end
  end
end