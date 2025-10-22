# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Debug informative diffs issues" do
  context "Issue 1: Attribute order showing as normative diff" do
    it "extracts and compares actual HTML from isodoc sourcecode test" do
      # From isodoc sourcecode_spec.rb line 78-93
      expected_html = <<~HTML
        <br><div class="TOC" id="_"><h1 class="IntroTitle">Table of contents</h1></div>
        <br><div id="fwd">
        <h1 class="ForewordTitle">Foreword</h1>
        <pre id="samplecode" class="sourcecode">puts x</pre>
        <p class="SourceTitle" style="text-align:center;">Figure 1 — Ruby<i>code</i></p>
        <pre id="_" class="sourcecode">
           Hey
           <br/>
           Que?
           <br/>
        </pre>
        </div>
      HTML

      # The actual output has attribute order changed: id first, then class
      actual_html = <<~HTML
        <br><div id="_" class="TOC"><h1 class="IntroTitle">Table of contents</h1></div>
        <br><div id="fwd">
        <h1 class="ForewordTitle">Foreword</h1>
        <pre id="samplecode" class="sourcecode">puts x</pre>
        <p class="SourceTitle" style="text-align:center;">Figure 1 — Ruby<i>code</i></p>
        <pre id="_" class="sourcecode">Hey<br>Que?<br></pre>
        </div>
      HTML

      # With spec_friendly/html4 profile, attribute order should be INFORMATIVE
      # But it's showing as NORMATIVE (red/green instead of cyan)

      result = Canon::Comparison.equivalent?(
        expected_html,
        actual_html,
        format: :html4,
        match_profile: :spec_friendly,
        verbose: true,
      )

      puts "\n=== DEBUG OUTPUT ==="
      puts "Equivalent? #{result.equivalent?}"
      puts "Has normative diffs? #{result.has_normative_diffs?}"
      puts "Has informative diffs? #{result.has_informative_diffs?}"
      puts "Differences count: #{result.differences.length}"

      result.differences.each_with_index do |diff, i|
        puts "\nDiff #{i + 1}:"
        puts "  Class: #{diff.class}"
        if diff.respond_to?(:dimension)
          puts "  Dimension: #{diff.dimension}"
          puts "  Active?: #{diff.normative?}"
          puts "  Reason: #{diff.reason}"
          if diff.respond_to?(:node1) && diff.node1
            puts "  Node1 path: #{diff.node1.respond_to?(:path) ? diff.node1.path : 'N/A'}"
            puts "  Node2 path: #{diff.node2.respond_to?(:path) ? diff.node2.path : 'N/A'}"
          end
        else
          puts "  Hash: #{diff.inspect}"
        end
      end

      # Try with just the divs that have attribute order differences
      div1 = '<div class="TOC" id="_">Test</div>'
      div2 = '<div id="_" class="TOC">Test</div>'

      puts "\n\n=== ATTRIBUTE ORDER TEST ==="
      attr_result = Canon::Comparison.equivalent?(
        div1,
        div2,
        format: :html4,
        match_profile: :spec_friendly,
        verbose: true,
      )

      puts "Equivalent? #{attr_result.equivalent?}"
      puts "Differences: #{attr_result.differences.length}"
      attr_result.differences.each do |diff|
        if diff.respond_to?(:dimension)
          puts "  Dimension: #{diff.dimension}, Normative: #{diff.normative?}"
        end
      end
    end
  end

  context "Issue 2: Empty diffs when only informative diffs" do
    it "tests scenario with only informative diffs" do
      # Simplified HTML with only attribute order difference
      html1 = '<div class="foo" id="bar">Content</div>'
      html2 = '<div id="bar" class="foo">Content</div>'

      result = Canon::Comparison.equivalent?(
        html1,
        html2,
        format: :html4,
        match_profile: :spec_friendly,
        verbose: true,
      )

      puts "\n=== ISSUE 2 DEBUG ==="
      puts "Equivalent? #{result.equivalent?}"
      puts "Has normative? #{result.has_normative_diffs?}"
      puts "Has informative? #{result.has_informative_diffs?}"
      puts "Differences: #{result.differences.length}"

      # With spec_friendly, attribute order is :strict, but :rendered preprocessing
      # should normalize it away
      expect(result.equivalent?).to be true
    end

    it "tests with HTML fragments (no body wrapper)" do
      # Minimal test case
      html1 = '<div class="foo" id="x">Test</div>'
      html2 = '<div id="x" class="foo">Test</div>'

      result = Canon::Comparison.equivalent?(
        html1,
        html2,
        format: :html4,
        verbose: true,
      )

      puts "\n=== MINIMAL HTML4 TEST ==="
      puts "Equivalent? #{result.equivalent?}"
      puts "Has normative? #{result.has_normative_diffs?}"
      puts "Differences: #{result.differences.length}"

      result.differences.each do |diff|
        if diff.respond_to?(:dimension)
          puts "  Dim: #{diff.dimension}, Normative: #{diff.normative?}, Reason: #{diff.reason}"
        end
      end

      # html4 profile has attribute_whitespace: :normalize
      expect(result.equivalent?).to be true
    end
  end
end
