#!/usr/bin/env ruby
# frozen_string_literal: true

# Test semantic tree diff UX improvements
# Verifies that:
# 1. XPath includes position numbers
# 2. Element content previews are shown
# 3. Specific error categories match DOM clarity

require_relative "../lib/canon"

# Test case: HTML with multiple paragraphs to verify position numbers
html1 = <<~HTML
  <html>
    <body>
      <div>
        <p>First paragraph</p>
        <p>Second paragraph</p>
        <p>Third paragraph</p>
      </div>
    </body>
  </html>
HTML

html2 = <<~HTML
  <html>
    <body>
      <div>
        <p>First paragraph</p>
        <p id="modified">Second paragraph with changes</p>
        <p>Third paragraph</p>
        <p>Fourth paragraph added</p>
      </div>
    </body>
  </html>
HTML

puts "=" * 80
puts "Testing Semantic Tree Diff UX Improvements"
puts "=" * 80
puts

# Test with semantic algorithm
result = Canon::Comparison.equivalent?(
  html1,
  html2,
  diff_algorithm: :semantic,
  format: :html,
  verbose: true,
)

puts "Equivalent: #{result.equivalent?}"
puts
puts "Differences found: #{result.differences.length}"
puts

# Check each difference for UX improvements
result.differences.each_with_index do |diff, i|
  puts "─" * 80
  puts "Difference ##{i + 1}:"
  puts "  Dimension: #{diff.dimension}"
  puts "  Reason: #{diff.reason}"

  # Check XPath has position numbers
  node = diff.node1 || diff.node2
  if node
    xpath = if node.respond_to?(:path)
              node.path
            else
              "(no xpath)"
            end
    puts "  XPath: #{xpath}"

    # Verify position numbers are included
    if xpath.include?("[") && xpath.include?("]")
      puts "  ✓ XPath includes position numbers"
    else
      puts "  ✗ WARNING: XPath missing position numbers"
    end
  end

  # Check if reason is specific and actionable
  if diff.reason
    if diff.reason.include?("Missing") || diff.reason.include?("Extra") ||
        diff.reason.include?("changed:") || diff.reason.include?("→")
      puts "  ✓ Reason is specific and actionable"
    else
      puts "  ⚠ Reason could be more specific: #{diff.reason}"
    end
  end

  puts
end

puts "=" * 80
puts "Formatted output:"
puts "=" * 80
puts result

# Test attribute differences
puts "\n\n"
puts "=" * 80
puts "Testing Attribute Difference Details"
puts "=" * 80

attr_html1 = '<div class="old" id="test" data-value="1">Content</div>'
attr_html2 = '<div class="new" id="test" data-value="2" data-extra="added">Content</div>'

attr_result = Canon::Comparison.equivalent?(
  attr_html1,
  attr_html2,
  diff_algorithm: :semantic,
  format: :html,
  verbose: true,
)

puts "Differences:"
attr_result.differences.each do |diff|
  puts "  Dimension: #{diff.dimension}"
  puts "  Reason: #{diff.reason}"

  # Check for specific attribute details
  if diff.reason.include?("Missing:") || diff.reason.include?("Extra:") || diff.reason.include?("Changed:")
    puts "  ✓ Shows specific attribute changes"
  end
  puts
end

puts "Formatted output:"
puts attr_result

puts "\n"
puts "=" * 80
puts "Test complete!"
puts "=" * 80
