# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff"

RSpec.describe Canon::TreeDiff::Matchers::UniversalMatcher do
  let(:matcher) { described_class.new }

  # Helper to build a simple tree
  def build_simple_tree
    root = Canon::TreeDiff::Core::TreeNode.new(label: "root", value: "document")
    child1 = Canon::TreeDiff::Core::TreeNode.new(label: "section",
                                                 value: "Introduction")
    child2 = Canon::TreeDiff::Core::TreeNode.new(label: "section",
                                                 value: "Conclusion")
    root.add_child(child1)
    root.add_child(child2)
    root
  end

  # Helper to build a complex tree
  def build_complex_tree
    root = Canon::TreeDiff::Core::TreeNode.new(label: "root", value: "document")

    section1 = Canon::TreeDiff::Core::TreeNode.new(label: "section")
    title1 = Canon::TreeDiff::Core::TreeNode.new(label: "title",
                                                 value: "Chapter 1")
    para1 = Canon::TreeDiff::Core::TreeNode.new(label: "para",
                                                value: "First paragraph")
    section1.add_child(title1)
    section1.add_child(para1)

    section2 = Canon::TreeDiff::Core::TreeNode.new(label: "section")
    title2 = Canon::TreeDiff::Core::TreeNode.new(label: "title",
                                                 value: "Chapter 2")
    para2 = Canon::TreeDiff::Core::TreeNode.new(label: "para",
                                                value: "Second paragraph")
    section2.add_child(title2)
    section2.add_child(para2)

    root.add_child(section1)
    root.add_child(section2)
    root
  end

  describe "#initialize" do
    it "uses default options when none provided" do
      expect(matcher.options[:similarity_threshold]).to eq(0.95)
      expect(matcher.options[:enable_hash_matching]).to be true
      expect(matcher.options[:enable_similarity_matching]).to be true
      expect(matcher.options[:enable_propagation]).to be true
      expect(matcher.options[:max_propagation_depth]).to be_nil
      expect(matcher.options[:min_propagation_weight]).to eq(2.0)
    end

    it "merges custom options with defaults" do
      custom_matcher = described_class.new(
        similarity_threshold: 0.8,
        enable_propagation: false,
      )

      expect(custom_matcher.options[:similarity_threshold]).to eq(0.8)
      expect(custom_matcher.options[:enable_propagation]).to be false
      expect(custom_matcher.options[:enable_hash_matching]).to be true
    end

    it "initializes empty statistics" do
      expect(matcher.statistics).to eq({})
    end
  end

  describe "#match" do
    context "with identical trees" do
      let(:tree1) { build_simple_tree }
      let(:tree2) { build_simple_tree }

      it "matches all nodes via hash matching" do
        matching = matcher.match(tree1, tree2)

        # Should match root + 2 children = 3 nodes
        expect(matching.size).to eq(3)
      end

      it "records hash matching statistics" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:hash_matches]).to eq(3)
        expect(matcher.statistics[:total_matches]).to eq(3)
        expect(matcher.statistics[:phases_executed]).to include(:hash_matching)
      end

      it "calculates match ratios correctly" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:tree1_nodes]).to eq(3)
        expect(matcher.statistics[:tree2_nodes]).to eq(3)
        expect(matcher.statistics[:match_ratio_tree1]).to eq(1.0)
        expect(matcher.statistics[:match_ratio_tree2]).to eq(1.0)
      end
    end

    context "with similar but not identical trees" do
      let(:tree1) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document")
        child = Canon::TreeDiff::Core::TreeNode.new(
          label: "para",
          value: "The quick brown fox jumps over the lazy dog",
        )
        root.add_child(child)
        root
      end

      let(:tree2) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document")
        child = Canon::TreeDiff::Core::TreeNode.new(
          label: "para",
          value: "The quick brown fox jumps over a lazy dog",
        )
        root.add_child(child)
        root
      end

      it "matches nodes via similarity matching" do
        matching = matcher.match(tree1, tree2)

        # Root matches via hash, para matches via similarity
        expect(matching.size).to eq(2)
        expect(matcher.statistics[:similarity_matches]).to be > 0
      end
    end

    context "with structural changes" do
      let(:tree1) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document")
        parent = Canon::TreeDiff::Core::TreeNode.new(label: "parent")
        child = Canon::TreeDiff::Core::TreeNode.new(label: "child",
                                                    value: "text")
        parent.add_child(child)
        root.add_child(parent)
        root
      end

      let(:tree2) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document")
        parent = Canon::TreeDiff::Core::TreeNode.new(label: "parent")
        child = Canon::TreeDiff::Core::TreeNode.new(label: "child",
                                                    value: "text")
        parent.add_child(child)
        root.add_child(parent)
        root
      end

      it "matches nodes via propagation" do
        matching = matcher.match(tree1, tree2)

        # All nodes should match: root, parent, child
        expect(matching.size).to eq(3)
      end
    end

    context "with completely different trees" do
      let(:tree1) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document1")
        child = Canon::TreeDiff::Core::TreeNode.new(label: "section",
                                                    value: "A")
        root.add_child(child)
        root
      end

      let(:tree2) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document2")
        child = Canon::TreeDiff::Core::TreeNode.new(label: "chapter",
                                                    value: "B")
        root.add_child(child)
        root
      end

      it "has low match ratio" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:match_ratio_tree1]).to be < 1.0
        expect(matcher.statistics[:match_ratio_tree2]).to be < 1.0
      end
    end

    context "with hash matching disabled" do
      let(:matcher) { described_class.new(enable_hash_matching: false) }
      let(:tree1) { build_simple_tree }
      let(:tree2) { build_simple_tree }

      it "skips hash matching phase" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:phases_executed]).not_to include(
          :hash_matching,
        )
        expect(matcher.statistics[:hash_matches]).to eq(0)
      end

      it "still finds matches via other methods" do
        matching = matcher.match(tree1, tree2)

        # Should still match via similarity or propagation
        expect(matching.size).to be > 0
      end
    end

    context "with similarity matching disabled" do
      let(:matcher) { described_class.new(enable_similarity_matching: false) }
      let(:tree1) { build_simple_tree }
      let(:tree2) { build_simple_tree }

      it "skips similarity matching phase" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:phases_executed]).not_to include(
          :similarity_matching,
        )
        expect(matcher.statistics[:similarity_matches]).to eq(0)
      end
    end

    context "with propagation disabled" do
      let(:matcher) { described_class.new(enable_propagation: false) }
      let(:tree1) { build_simple_tree }
      let(:tree2) { build_simple_tree }

      it "skips propagation phase" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:phases_executed]).not_to include(
          :propagation,
        )
        expect(matcher.statistics[:propagation_matches]).to eq(0)
      end
    end

    context "with custom similarity threshold" do
      let(:matcher) { described_class.new(similarity_threshold: 0.7) }

      let(:tree1) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document")
        child = Canon::TreeDiff::Core::TreeNode.new(label: "para",
                                                    value: "abc def ghi")
        root.add_child(child)
        root
      end

      let(:tree2) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root",
                                                   value: "document")
        child = Canon::TreeDiff::Core::TreeNode.new(label: "para",
                                                    value: "abc def xyz")
        root.add_child(child)
        root
      end

      it "uses custom threshold for similarity matching" do
        matching = matcher.match(tree1, tree2)

        # Lower threshold allows more matches
        expect(matching.size).to be >= 1
      end
    end

    context "with complex tree structures" do
      let(:tree1) { build_complex_tree }
      let(:tree2) { build_complex_tree }

      it "matches all nodes correctly" do
        matching = matcher.match(tree1, tree2)

        # root + 2 sections + 2 titles + 2 paras = 7 nodes
        expect(matching.size).to eq(7)
      end

      it "records comprehensive statistics" do
        matcher.match(tree1, tree2)

        expect(matcher.statistics[:tree1_nodes]).to eq(7)
        expect(matcher.statistics[:tree2_nodes]).to eq(7)
        expect(matcher.statistics[:total_matches]).to eq(7)
        expect(matcher.statistics[:match_ratio_tree1]).to eq(1.0)
        expect(matcher.statistics[:match_ratio_tree2]).to eq(1.0)
      end
    end
  end

  describe "statistics tracking" do
    let(:tree1) { build_complex_tree }
    let(:tree2) { build_complex_tree }

    it "tracks all phases executed" do
      matcher.match(tree1, tree2)

      expect(matcher.statistics[:phases_executed]).to include(
        :hash_matching,
        :similarity_matching,
        :propagation,
      )
    end

    it "tracks node counts for both trees" do
      matcher.match(tree1, tree2)

      expect(matcher.statistics[:tree1_nodes]).to be > 0
      expect(matcher.statistics[:tree2_nodes]).to be > 0
    end

    it "tracks matches by phase" do
      matcher.match(tree1, tree2)

      total = matcher.statistics[:hash_matches] +
        matcher.statistics[:similarity_matches] +
        matcher.statistics[:propagation_matches]

      expect(matcher.statistics[:total_matches]).to eq(total)
    end
  end

  describe "integration with matcher components" do
    it "uses HashMatcher for exact matching" do
      hash_matcher = instance_double(
        Canon::TreeDiff::Matchers::HashMatcher,
      )
      temp_matching = Canon::TreeDiff::Core::Matching.new
      allow(Canon::TreeDiff::Matchers::HashMatcher).to receive(:new)
        .and_return(hash_matcher)
      allow(hash_matcher).to receive(:match).and_return(temp_matching)

      tree1 = build_simple_tree
      tree2 = build_simple_tree

      matcher.match(tree1, tree2)

      expect(hash_matcher).to have_received(:match)
    end

    it "uses SimilarityMatcher for content matching" do
      similarity_matcher = instance_double(
        Canon::TreeDiff::Matchers::SimilarityMatcher,
      )
      allow(Canon::TreeDiff::Matchers::SimilarityMatcher).to receive(:new)
        .and_return(similarity_matcher)
      allow(similarity_matcher).to receive(:match)

      tree1 = build_simple_tree
      tree2 = build_simple_tree

      matcher.match(tree1, tree2)

      expect(similarity_matcher).to have_received(:match)
    end

    it "uses StructuralPropagator for propagation" do
      propagator = instance_double(
        Canon::TreeDiff::Matchers::StructuralPropagator,
      )
      allow(Canon::TreeDiff::Matchers::StructuralPropagator).to receive(:new)
        .and_return(propagator)
      allow(propagator).to receive(:propagate)

      tree1 = build_simple_tree
      tree2 = build_simple_tree

      matcher.match(tree1, tree2)

      expect(propagator).to have_received(:propagate)
    end
  end
end
