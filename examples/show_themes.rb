#!/usr/bin/env ruby
# frozen_string_literal: true

# Example script demonstrating all available diff display themes.
# Run with: bundle exec ruby examples/show_themes.rb
#
# This script shows how the same XML diff renders under each theme:
#   - :light     - Light terminal backgrounds
#   - :dark      - Dark terminal backgrounds (default)
#   - :retro     - Amber CRT phosphor look
#   - :claude    - Claude Code diff style (red/green backgrounds)
#   - :cyberpunk - Neon on black, high contrast, futuristic

require "bundler/setup"
require "canon"
require "canon/diff_formatter"

# Sample XML documents with meaningful differences
# These documents have:
# - A deleted element (the <old-item>)
# - An added element (the <new-item>)
# - A changed attribute (version="1.0" -> version="2.0")
# - A changed text content ("Old Text" -> "New Text")
# - Whitespace-only change (formatting)
# - An informative comment difference

XML1 = <<~XML.freeze
  <?xml version="1.0" encoding="UTF-8"?>
  <document version="1.0">
    <header>
      <!-- Original comment -->
      <title>Document Title</title>
    </header>
    <content>
      <old-item name="thing1">Old Text</old-item>
      <common-item>Shared content</common-item>
      <common-item>More shared content</common-item>
    </content>
    <footer>
      <note>Footer note</note>
    </footer>
  </document>
XML

XML2 = <<~XML.freeze
  <?xml version="1.0" encoding="UTF-8"?>
  <document version="2.0">
    <header>
      <!-- Updated comment -->
      <title>Document Title</title>
    </header>
    <content>
      <new-item name="thing2">New Text</new-item>
      <common-item>Shared content</common-item>
      <common-item>More shared content</common-item>
      <extra-item>Additional item</extra-item>
    </content>
    <footer>
      <note>Footer note</note>
    </footer>
  </document>
XML

# Helper to run diff with a specific theme and display mode
def run_diff_with_theme(theme_name, xml1, xml2, display_mode: :separate)
  Canon::Config.reset!
  Canon::Config.configure do |config|
    config.xml.diff.theme = theme_name
  end

  # Use semantic diff to get all differences reported, even when documents
  # are not equivalent. DOM diff stops at the first difference.
  result = Canon::Comparison.equivalent?(xml1, xml2, diff_algorithm: :semantic, verbose: true)

  formatter = Canon::DiffFormatter.new(
    use_color: true,
    mode: :by_line,
    show_diffs: :all,
    diff_mode: display_mode,
  )

  formatter.format(result, :xml, doc1: xml1, doc2: xml2)
end

# Helper to print section header
def print_header(title)
  puts
  puts "=" * 70
  puts title
  puts "=" * 70
end

# Helper to strip ANSI codes for plain text display
def strip_ansi(text)
  text.gsub(/\e\[[0-9;]*m/, "")
end

# Main demonstration
puts
puts "DIFF DISPLAY THEME DEMONSTRATION"
puts "=" * 70
puts
puts "This script demonstrates how the same XML diff renders under"
puts "each of the 5 available themes. Each theme has different:"
puts "  - Color schemes (light vs dark backgrounds)"
puts "  - Marker styles ([, ], <, >, -, +)"
puts "  - Visual emphasis (backgrounds vs foreground colors)"
puts
puts "Sample documents have these differences:"
puts "  - Attribute change: version=\"1.0\" -> version=\"2.0\""
puts "  - Text change: <old-item> -> <new-item>"
puts "  - Content change: \"Old Text\" -> \"New Text\""
puts "  - Addition: <extra-item> added"
puts "  - Comment change: informative difference"
puts

# Demonstrate each theme in both display modes
themes = {
  light: "Light Theme (light backgrounds, red/green markers with light bg)",
  dark: "Dark Theme (dark backgrounds, saturated red/green foregrounds)",
  retro: "Retro Theme (amber CRT phosphor, monochrome amber with inverse video)",
  claude: "Claude Theme (red/green backgrounds + white text, maximum visual pop)",
  cyberpunk: "Cyberpunk Theme (neon magenta/cyan on black, electric, futuristic)",
}

display_modes = {
  separate: "Separate lines (- / + on separate lines)",
  inline: "Inline mode (* on same line, old→new)",
}

themes.each do |theme_name, description|
  print_header("#{theme_name.upcase} THEME: #{description}")

  puts
  puts "Theme configuration:"
  puts "  Canon::Config.xml.diff.theme = :#{theme_name}"

  display_modes.each do |mode, mode_description|
    puts
    puts "-" * 70
    puts "DISPLAY MODE: #{mode.upcase} - #{mode_description}"
    puts "-" * 70
    puts "COLOR OUTPUT (with ANSI escape sequences):"

    output = run_diff_with_theme(theme_name, XML1, XML2, display_mode: mode)
    puts output

    puts
    puts "-" * 70
    puts "PLAIN TEXT OUTPUT (without ANSI codes):"
    puts strip_ansi(output)
  end
end

# Summary table
print_header("THEME SUMMARY")
puts
puts "| Theme      | Best For                      | Key Characteristics            |"
puts "|------------|-------------------------------|--------------------------------|"
puts "| :light     | Light terminal backgrounds    | Light marker backgrounds       |"
puts "| :dark      | Dark terminals (default)      | Saturated foreground colors    |"
puts "| :retro     | Low blue light / accessibility| Amber monochrome + inverse     |"
puts "| :claude    | Maximum visual pop            | Red/green backgrounds          |"
puts "| :cyberpunk | Neon / futuristic terminals   | Magenta/cyan neon on black     |"
puts

# How to use programmatically
print_header("HOW TO USE IN CODE")
puts
puts "# Set theme via configuration:"
puts "Canon::Config.configure do |config|"
puts "  config.xml.diff.theme = :claude"
puts "end"
puts
puts "# Or via ENV variable:"
puts "ENV['CANON_DIFF_THEME'] = 'claude'"
puts
puts "# Or for a single diff, pass theme to formatter:"
puts "formatter = Canon::DiffFormatter.new("
puts "  use_color: true,"
puts "  mode: :by_line,"
puts "  show_diffs: :all,"
puts "  theme: :retro  # if supported by the formatter"
puts ")"
puts

# Theme inheritance example
print_header("THEME INHERITANCE (advanced)")
puts
puts "# Create custom theme inheriting from :dark with overrides:"
puts "Canon::Config.configure do |config|"
puts "  config.xml.diff.theme_inheritance = {"
puts "    base: :dark,"
puts "    overrides: {"
puts "      diff: {"
puts "        removed: { content: { bg: :light_red } }"
puts "      }"
puts "    }"
puts "  }"
puts "end"
puts

# Note about Rainbow gem limitations
print_header("NOTE: RAINBOW GEM LIMITATIONS")
puts
puts "The Rainbow gem (used for terminal colors) doesn't support"
puts ":bright_black or :bright_white in standard 16-color mode."
puts "Themes substitute compatible colors:"
puts "  - DARK theme uses :white instead of :bright_white"
puts "  - LIGHT theme uses :black instead of :bright_black"
puts "  - Comments use :cyan or :magenta instead of :bright_black"
puts

puts "=" * 70
puts "END OF THEME DEMONSTRATION"
puts "=" * 70
