#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"

# Sample IsoDoc-style XML with differences
xml1 = <<~XML
  <iso-standard xmlns="http://riboseinc.com/isoxml" type="presentation">
     <preface>
        <clause type="toc" id="_" displayorder="1">
           <fmt-title id="_" depth="1">Table of contents</fmt-title>
        </clause>
        <foreword id="fwd" displayorder="2">
           <title id="_">Foreword</title>
           <fmt-title id="_" depth="1">
              <semx element="title" source="_">Foreword</semx>
           </fmt-title>
           <figure id="F" autonum="1">
              <fmt-name id="_">
                 <span class="fmt-caption-label">
                    <span class="fmt-element-name">Figure</span>
                    <semx element="autonum" source="F">1</semx>
                 </span>
              </fmt-name>
              <note id="FB" autonum="">
                 <fmt-name id="_">
                    <span class="fmt-caption-label">
                       <span class="fmt-element-name">NOTE</span>
                    </span>
                 </fmt-name>
                 <p>XYZ</p>
              </note>
           </figure>
        </foreword>
     </preface>
  </iso-standard>
XML

xml2 = <<~XML
  <iso-standard xmlns="http://riboseinc.com/isoxml" type="presentation">
     <preface>
        <clause type="toc" id="_" displayorder="1">
           <fmt-title id="_" depth="1">Table of contents</fmt-title>
        </clause>
        <foreword id="fwd" displayorder="2">
           <title id="_">Introduction</title>
           <fmt-title id="_" depth="1">
              <semx element="title" source="_">Introduction</semx>
           </fmt-title>
           <figure id="F" autonum="2">
              <fmt-name id="_">
                 <span class="fmt-caption-label">
                    <span class="fmt-element-name">Figure</span>
                    <semx element="autonum" source="F">2</semx>
                 </span>
              </fmt-name>
              <note id="FB" autonum="">
                 <fmt-name id="_">
                    <span class="fmt-caption-label">
                       <span class="fmt-element-name">NOTE</span>
                    </span>
                 </fmt-name>
                 <p>ABC</p>
              </note>
           </figure>
           <p id="new-para">This is a new paragraph.</p>
        </foreword>
     </preface>
  </iso-standard>
XML

puts "=" * 80
puts "DOM DIFF ALGORITHM COMPARISON"
puts "=" * 80
puts

dom_result = Canon::Comparison.equivalent?(
  xml1, xml2,
  diff_algorithm: :dom,
  verbose: true
)

puts "Algorithm: DOM DIFF"
puts "Differences count: #{dom_result.differences.length}"
puts "Operations count: #{dom_result.operations.length}"
puts
puts "Sample differences:"
dom_result.differences.first(5).each_with_index do |diff, i|
  puts "  #{i + 1}. Dimension: #{diff.dimension}"
  puts "     Expected: #{diff.value1.to_s[0..100]}" if diff.respond_to?(:value1) && diff.value1
  puts "     Actual: #{diff.value2.to_s[0..100]}" if diff.respond_to?(:value2) && diff.value2
  puts
end

puts "\n#{'=' * 80}"
puts "TREE (SEMANTIC) DIFF ALGORITHM COMPARISON"
puts "=" * 80
puts

tree_result = Canon::Comparison.equivalent?(
  xml1, xml2,
  diff_algorithm: :semantic,
  verbose: true
)

puts "Algorithm: SEMANTIC TREE DIFF"
puts "Differences count: #{tree_result.differences.length}"
puts "Operations count: #{tree_result.operations.length}"
puts

if tree_result.match_options[:tree_diff_statistics]
  stats = tree_result.match_options[:tree_diff_statistics]
  puts "Tree Statistics:"
  puts "  - Tree1 nodes: #{stats[:tree1_nodes]}"
  puts "  - Tree2 nodes: #{stats[:tree2_nodes]}"
  puts "  - Total matches: #{stats[:total_matches]}"
  puts "  - Match ratio (tree1): #{(stats[:match_ratio_tree1] * 100).round(1)}%"
  puts "  - Match ratio (tree2): #{(stats[:match_ratio_tree2] * 100).round(1)}%"
  puts
end

puts "Sample differences:"
tree_result.differences.first(5).each_with_index do |diff, i|
  puts "  #{i + 1}. Dimension: #{diff.dimension}"
  puts "     Expected: #{diff.value1.to_s[0..100]}" if diff.respond_to?(:value1) && diff.value1
  puts "     Actual: #{diff.value2.to_s[0..100]}" if diff.respond_to?(:value2) && diff.value2
  puts
end

puts "\n#{'=' * 80}"
puts "TREE DIFF OPERATIONS"
puts "=" * 80
puts

tree_result.operations.first(10).each_with_index do |op, i|
  puts "  #{i + 1}. #{op.type.to_s.upcase}"
  puts "     Node: #{op.node.label}" if op.node
  puts "     Details: #{op.inspect[0..150]}"
  puts
end

puts "\n#{'=' * 80}"
puts "COMPARISON SUMMARY"
puts "=" * 80
puts

puts "DOM Diff:"
puts "  - Differences count: #{dom_result.differences.length}"
puts "  - Operations: #{dom_result.operations.length}"
puts "  - Has detailed diff information: #{!dom_result.differences.empty?}"
puts

puts "Tree Diff:"
puts "  - Differences count: #{tree_result.differences.length}"
puts "  - Operations: #{tree_result.operations.length}"
puts "  - Has detailed diff information: #{!tree_result.differences.empty?}"
puts "  - Has tree diff operations: #{!tree_result.operations.empty?}"
puts "  - Has tree statistics: #{!tree_result.match_options[:tree_diff_statistics].nil?}"
