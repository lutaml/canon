# frozen_string_literal: true

require "paint"
require "diff/lcs"
require "diff/lcs/hunk"
require "strscan"
require "set"
require_relative "diff/diff_block"
require_relative "diff/diff_context"
require_relative "diff/diff_report"

module Canon
  # Formatter for displaying semantic differences with color support
  class DiffFormatter
    # Default character visualization map (CJK-safe)
    DEFAULT_VISUALIZATION_MAP = {
      # Common whitespace characters
      " " => "░", # U+2591 Light Shade (regular space)
      "\t" => "⇥", # U+21E5 Rightwards Arrow to Bar (tab)
      "\u00A0" => "␣", # U+2423 Open Box (non-breaking space)

      # Line endings
      "\n" => "↵",   # U+21B5 Downwards Arrow with Corner Leftwards (LF)
      "\r" => "⏎",   # U+23CE Return Symbol (CR)
      "\r\n" => "↵", # Windows line ending (CRLF)
      "\u0085" => "⏎",   # U+0085 Next Line (NEL)
      "\u2028" => "⤓",   # U+2913 Downwards Arrow to Bar (line separator)
      "\u2029" => "⤓",   # U+2913 Downwards Arrow to Bar (paragraph separator)

      # Unicode spaces (using box characters for CJK safety)
      "\u2002" => "▭",   # U+25AD White Rectangle (en space)
      "\u2003" => "▬",   # U+25AC Black Rectangle (em space)
      "\u2005" => "⏓",   # U+23D3 Metrical Short Over Long (four-per-em space)
      "\u2005" => "⏕",   # U+23D5 Metrical Two Shorts Over Long (six-per-em space)
      "\u2009" => "▯",   # U+25AF White Vertical Rectangle (thin space)
      "\u200A" => "▮",   # U+25AE Black Vertical Rectangle (hair space)
      "\u2007" => "□",   # U+25A1 White Square (figure space)
      "\u202F" => "▫",   # U+25AB White Small Square (narrow no-break space)
      "\u205F" => "▭",   # U+25AD White Rectangle (medium mathematical space)
      "\u3000" => "⎵",   # U+23B5 Bottom Square Bracket (ideographic space)
      "\u303F" => "⏑",   # U+23D1 Metrical Breve (ideographic half space)

      # Zero-width characters (using arrows)
      "\u200B" => "→",   # U+2192 Rightwards Arrow (zero-width space)
      "\u200C" => "↛",   # U+219B Rightwards Arrow with Stroke (zero-width non-joiner)
      "\u200D" => "⇢",   # U+21E2 Rightwards Dashed Arrow (zero-width joiner)
      "\uFEFF" => "⇨",   # U+21E8 Rightwards White Arrow (zero-width no-break space/BOM)

      # Directional markers
      "\u200E" => "⟹",   # U+27F9 Long Rightwards Double Arrow (LTR mark)
      "\u200F" => "⟸",   # U+27F8 Long Leftwards Double Arrow (RTL mark)
      "\u202A" => "⇒",   # U+21D2 Rightwards Double Arrow (LTR embedding)
      "\u202B" => "⇐",   # U+21D0 Leftwards Double Arrow (RTL embedding)
      "\u202C" => "↔",   # U+2194 Left Right Arrow (pop directional formatting)
      "\u202D" => "⇉",   # U+21C9 Rightwards Paired Arrows (LTR override)
      "\u202E" => "⇇",   # U+21C7 Leftwards Paired Arrows (RTL override)

      # Control characters
      "\u0000" => "␀", # U+2400 Symbol for Null
      "\u00AD" => "­‐", # U+2010 Hyphen (soft hyphen)
      "\u0008" => "␈",   # U+2408 Symbol for Backspace
      "\u007F" => "␡",   # U+2421 Symbol for Delete
    }.freeze

    # Map difference codes to human-readable descriptions
    DIFF_DESCRIPTIONS = {
      Comparison::EQUIVALENT => "Equivalent",
      Comparison::MISSING_ATTRIBUTE => "Missing attribute",
      Comparison::MISSING_NODE => "Missing node",
      Comparison::UNEQUAL_ATTRIBUTES => "Unequal attributes",
      Comparison::UNEQUAL_COMMENTS => "Unequal comments",
      Comparison::UNEQUAL_DOCUMENTS => "Unequal documents",
      Comparison::UNEQUAL_ELEMENTS => "Unequal elements",
      Comparison::UNEQUAL_NODES_TYPES => "Unequal node types",
      Comparison::UNEQUAL_TEXT_CONTENTS => "Unequal text contents",
      Comparison::MISSING_HASH_KEY => "Missing hash key",
      Comparison::UNEQUAL_HASH_VALUES => "Unequal hash values",
      Comparison::UNEQUAL_ARRAY_LENGTHS => "Unequal array lengths",
      Comparison::UNEQUAL_ARRAY_ELEMENTS => "Unequal array elements",
      Comparison::UNEQUAL_TYPES => "Unequal types",
      Comparison::UNEQUAL_PRIMITIVES => "Unequal primitive values",
    }.freeze

    def initialize(use_color: true, mode: :by_object, context_lines: 3,
diff_grouping_lines: nil, visualization_map: nil)
      @use_color = use_color
      @mode = mode
      @context_lines = context_lines
      @diff_grouping_lines = diff_grouping_lines
      @visualization_map = visualization_map || DEFAULT_VISUALIZATION_MAP
    end

    # Merge custom character visualization map with defaults
    #
    # @param custom_map [Hash, nil] Custom character mappings
    # @return [Hash] Merged character visualization map
    def self.merge_visualization_map(custom_map)
      DEFAULT_VISUALIZATION_MAP.merge(custom_map || {})
    end

    # Format differences array for display
    #
    # @param differences [Array] Array of difference hashes
    # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
    # @param doc1 [String, nil] First document content (for by-line mode)
    # @param doc2 [String, nil] Second document content (for by-line mode)
    # @return [String] Formatted output
    def format(differences, format, doc1: nil, doc2: nil)
      # In by-line mode with doc1/doc2, always perform diff regardless of differences array
      if @mode == :by_line && doc1 && doc2
        return by_line_diff(doc1, doc2, format: format)
      end

      if differences.empty?
        return success_message
      end

      case @mode
      when :by_line
        by_line_diff(doc1, doc2, format: format)
      else
        by_object_diff(differences, format)
      end
    end

    private

    # Generate success message based on mode
    def success_message
      emoji = @use_color ? "✅ " : ""
      message = case @mode
                when :by_line
                  "Files are identical"
                else
                  "Files are semantically equivalent"
                end

      colorize("#{emoji}#{message}\n", :green, :bold)
    end

    # Generate by-object diff with tree visualization
    def by_object_diff(differences, _format)
      output = []
      output << colorize("Visual Diff:", :cyan, :bold)

      # Group differences by path for tree building
      tree = build_diff_tree(differences)

      # Render tree
      output << render_tree(tree)

      output.join("\n")
    end

    # Generate by-line diff for XML/HTML/JSON/YAML using semantic LCS algorithm
    def by_line_diff(doc1, doc2, format: :xml)
      output = []
      output << colorize("Line-by-line diff:", :cyan, :bold)

      return output.join("\n") if doc1.nil? || doc2.nil?

      output << case format
                when :xml
                  dom_guided_xml_diff(doc1, doc2)
                when :json
                  semantic_json_diff(doc1, doc2)
                when :yaml
                  semantic_yaml_diff(doc1, doc2)
                else
                  # Fall back to simple line-based diff for HTML
                  simple_line_diff(doc1, doc2)
                end

      output.join("\n")
    end

    # Semantic JSON diff with token-level highlighting
    def semantic_json_diff(json1, json2)
      output = []

      begin
        # Pretty print both JSON files
        require "canon/json/pretty_printer"
        formatter = Canon::Json::PrettyPrinter.new(indent: 2)
        pretty1 = formatter.format(json1)
        pretty2 = formatter.format(json2)

        lines1 = pretty1.split("\n")
        lines2 = pretty2.split("\n")

        # Get LCS diff
        diffs = ::Diff::LCS.sdiff(lines1, lines2)

        # Format with semantic token highlighting
        output << format_semantic_diff(diffs, lines1, lines2, :json)
      rescue StandardError
        output << colorize("Warning: JSON parsing failed, using simple diff",
                           :yellow)
        output << simple_line_diff(json1, json2)
      end

      output.join("\n")
    end

    # Semantic YAML diff with token-level highlighting
    def semantic_yaml_diff(yaml1, yaml2)
      output = []

      begin
        # Pretty print both YAML files (canonicalized)
        require "canon"
        pretty1 = Canon.format(yaml1, :yaml)
        pretty2 = Canon.format(yaml2, :yaml)

        lines1 = pretty1.split("\n")
        lines2 = pretty2.split("\n")

        # Get LCS diff
        diffs = ::Diff::LCS.sdiff(lines1, lines2)

        # Format with semantic token highlighting
        output << format_semantic_diff(diffs, lines1, lines2, :yaml)
      rescue StandardError
        output << colorize("Warning: YAML parsing failed, using simple diff",
                           :yellow)
        output << simple_line_diff(yaml1, yaml2)
      end

      output.join("\n")
    end

    # Format semantic diff with token-level highlighting
    def format_semantic_diff(diffs, lines1, lines2, format)
      output = []

      # Detect non-ASCII characters in the diff
      all_text = (lines1 + lines2).join
      non_ascii = detect_non_ascii(all_text)

      # Add non-ASCII warning if any detected
      unless non_ascii.empty?
        warning = "(WARNING: non-ASCII characters detected in diff: [#{non_ascii.join(', ')}])"
        output << colorize(warning, :yellow)
        output << ""
      end

      diffs.each_with_index do |change, _idx|
        old_line = change.old_position ? change.old_position + 1 : nil
        new_line = change.new_position ? change.new_position + 1 : nil

        case change.action
        when "="
          # Unchanged line
          output << format_unified_line(old_line, new_line, " ",
                                        change.old_element)
        when "-"
          # Deletion
          output << format_unified_line(old_line, nil, "-", change.old_element,
                                        :red)
        when "+"
          # Addition
          output << format_unified_line(nil, new_line, "+", change.new_element,
                                        :green)
        when "!"
          # Change - show with semantic token highlighting
          old_text = change.old_element
          new_text = change.new_element

          # Tokenize based on format
          old_tokens = tokenize_semantic(old_text, format)
          new_tokens = tokenize_semantic(new_text, format)

          # Get token-level diff
          token_diffs = ::Diff::LCS.sdiff(old_tokens, new_tokens)

          # Build highlighted versions
          old_highlighted = build_token_highlighted_text(token_diffs, :old)
          new_highlighted = build_token_highlighted_text(token_diffs, :new)

          # Format both lines with yellow line numbers and pipes
          if @use_color
            yellow_old = Paint["%4d" % old_line, :yellow]
            yellow_pipe1 = Paint["|", :yellow]
            yellow_new = Paint["%4d" % new_line, :yellow]
            yellow_pipe2 = Paint["|", :yellow]
            red_marker = Paint["-", :red]
            green_marker = Paint["+", :green]

            output << "#{yellow_old}#{yellow_pipe1}    #{red_marker} #{yellow_pipe2} #{old_highlighted}"
            output << "    #{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
          else
            output << "#{'%4d' % old_line}|    - | #{old_highlighted}"
            output << "    |#{'%4d' % new_line}+ | #{new_highlighted}"
          end
        end
      end

      output.join("\n")
    end

    # Tokenize based on format (JSON or YAML)
    def tokenize_semantic(line, format)
      case format
      when :json
        tokenize_json(line)
      when :yaml
        tokenize_yaml(line)
      else
        # Fallback to simple space-based tokenization
        line.split(/(\s+)/)
      end
    end

    # Tokenize JSON line into meaningful tokens
    def tokenize_json(line)
      tokens = []
      scanner = StringScanner.new(line)

      until scanner.eos?
        # Skip whitespace
        tokens << if scanner.scan(/\s+/)
                    scanner.matched
                  # String values (with quotes)
                  elsif scanner.scan(/"(?:[^"\\]|\\.)*"/)
                    scanner.matched
                  # Numbers
                  elsif scanner.scan(/-?\d+\.?\d*(?:[eE][+-]?\d+)?/)
                    scanner.matched
                  # Booleans and null
                  elsif scanner.scan(/\b(?:true|false|null)\b/)
                    scanner.matched
                  # Structural characters
                  elsif scanner.scan(/[{}\[\]:,]/)
                    scanner.matched
                  # Any other character
                  else
                    scanner.getch
                  end
      end

      tokens
    end

    # Tokenize YAML line into meaningful tokens
    def tokenize_yaml(line)
      tokens = []
      scanner = StringScanner.new(line)

      until scanner.eos?
        # Skip whitespace (preserve for indentation)
        tokens << if scanner.scan(/\s+/)
                    scanner.matched
                  # YAML key with colon
                  elsif scanner.scan(/[\w-]+:/)
                    scanner.matched
                  # Quoted strings
                  elsif scanner.scan(/"(?:[^"\\]|\\.)*"/)
                    scanner.matched
                  elsif scanner.scan(/'(?:[^'\\]|\\.)*'/)
                    scanner.matched
                  # Numbers
                  elsif scanner.scan(/-?\d+\.?\d*/)
                    scanner.matched
                  # Booleans
                  elsif scanner.scan(/\b(?:true|false|yes|no)\b/)
                    scanner.matched
                  # List markers
                  elsif scanner.scan(/-\s/)
                    scanner.matched
                  # Bare words (unquoted values)
                  elsif scanner.scan(/[^\s:]+/)
                    scanner.matched
                  # Any other character
                  else
                    scanner.getch
                  end
      end

      tokens
    end

    # DOM-guided XML diff
    def dom_guided_xml_diff(xml1, xml2)
      require_relative "xml/data_model"
      require_relative "xml/element_matcher"
      require_relative "xml/line_range_mapper"

      output = []

      begin
        # Parse to DOM
        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        # Match elements semantically
        matcher = Canon::Xml::ElementMatcher.new
        matches = matcher.match_trees(root1, root2)

        # Build line range maps
        mapper1 = Canon::Xml::LineRangeMapper.new(indent: 2)
        mapper2 = Canon::Xml::LineRangeMapper.new(indent: 2)
        map1 = mapper1.build_map(root1, xml1)
        map2 = mapper2.build_map(root2, xml2)

        # Get pretty-printed lines
        lines1 = Canon::Xml::PrettyPrinter.new(indent: 2).format(xml1).split("\n")
        lines2 = Canon::Xml::PrettyPrinter.new(indent: 2).format(xml2).split("\n")

        # Display diffs based on element matches
        output << format_element_matches(matches, map1, map2, lines1, lines2)
      rescue StandardError => e
        # Fall back to simple diff on error, but provide detailed error information
        output << colorize("Warning: DOM parsing failed, using simple diff",
                           :yellow)
        output << colorize("Error: #{e.class}: #{e.message}", :red)

        # Include relevant backtrace lines (first 3 lines from canon library)
        relevant_trace = e.backtrace.select do |line|
          line.include?("canon")
        end.take(3)
        unless relevant_trace.empty?
          output << colorize("Backtrace:", :yellow)
          relevant_trace.each do |line|
            output << colorize("  #{line}", :yellow)
          end
        end

        output << ""
        output << simple_line_diff(xml1, xml2)
      end

      output.join("\n")
    end

    # Simple line-based diff (fallback)
    def simple_line_diff(doc1, doc2)
      output = []
      lines1 = doc1.split("\n")
      lines2 = doc2.split("\n")

      # Get LCS diff
      diffs = ::Diff::LCS.sdiff(lines1, lines2)

      # Group into hunks with context
      hunks = build_hunks(diffs, lines1, lines2, context_lines: @context_lines)

      # Format each hunk
      hunks.each do |hunk|
        output << format_hunk(hunk)
      end

      output.join("\n")
    end

    # Build hunks from diff with context lines
    def build_hunks(diffs, _lines1, _lines2, context_lines: 3)
      hunks = []
      current_hunk = []
      last_change_index = -context_lines - 1

      diffs.each_with_index do |change, index|
        # Check if we should start a new hunk
        if !current_hunk.empty? && index - last_change_index > context_lines * 2
          hunks << current_hunk
          current_hunk = []
        end

        # Add context before first change or after gap
        if current_hunk.empty? && change.action != "="
          start_context = [index - context_lines, 0].max
          (start_context...index).each do |i|
            current_hunk << diffs[i] if i < diffs.length
          end
        end

        current_hunk << change

        # Track last change for hunk grouping
        last_change_index = index if change.action != "="
      end

      # Add final hunk if any
      hunks << current_hunk unless current_hunk.empty?

      hunks
    end

    # Format a hunk of changes
    def format_hunk(hunk)
      output = []
      old_line = hunk.first.old_position + 1
      new_line = hunk.first.new_position + 1

      hunk.each do |change|
        case change.action
        when "="
          # Unchanged line (context)
          output << format_unified_line(old_line, new_line, " ",
                                        change.old_element)
          old_line += 1
          new_line += 1
        when "-"
          # Deletion
          output << format_unified_line(old_line, nil, "-", change.old_element,
                                        :red)
          old_line += 1
        when "+"
          # Addition
          output << format_unified_line(nil, new_line, "+", change.new_element,
                                        :green)
          new_line += 1
        when "!"
          # Change - show both with inline diff highlighting
          old_text = change.old_element
          new_text = change.new_element

          # Format with inline highlighting
          output << format_changed_line(old_line, old_text, new_text)
          old_line += 1
          new_line += 1
        end
      end

      output.join("\n")
    end

    # Format a unified diff line
    def format_unified_line(old_num, new_num, marker, content, color = nil)
      old_str = old_num ? "%4d" % old_num : "    "
      new_str = new_num ? "%4d" % new_num : "    "
      marker_part = "#{marker} "

      # Only apply visualization to diff lines (when color is provided), not context lines
      visualized_content = color ? apply_visualization(content, color) : content

      if @use_color
        # Yellow for line numbers and pipes
        yellow_old = Paint[old_str, :yellow]
        yellow_pipe1 = Paint["|", :yellow]
        yellow_new = Paint[new_str, :yellow]
        yellow_pipe2 = Paint["|", :yellow]

        if color
          # Colored marker for additions/deletions
          colored_marker = Paint[marker, color]
          "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{colored_marker} #{yellow_pipe2} #{visualized_content}"
        else
          # Context line - apply visualization but no color
          "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{marker} #{yellow_pipe2} #{visualized_content}"
        end
      else
        # No color mode
        "#{old_str}|#{new_str}#{marker_part}| #{visualized_content}"
      end
    end

    # Format changed lines with XML-aware token-level diff
    def format_changed_line(line_num, old_text, new_text)
      output = []

      # Tokenize XML lines
      old_tokens = tokenize_xml(old_text)
      new_tokens = tokenize_xml(new_text)

      # Get token-level diff
      token_diffs = ::Diff::LCS.sdiff(old_tokens, new_tokens)

      # Build highlighted versions
      old_highlighted = build_token_highlighted_text(token_diffs, :old)
      new_highlighted = build_token_highlighted_text(token_diffs, :new)

      # Format both lines with yellow line numbers and pipes
      if @use_color
        yellow_old = Paint["%4d" % line_num, :yellow]
        yellow_pipe1 = Paint["|", :yellow]
        yellow_new = Paint["%4d" % line_num, :yellow]
        yellow_pipe2 = Paint["|", :yellow]
        red_marker = Paint["-", :red]
        green_marker = Paint["+", :green]

        output << "#{yellow_old}#{yellow_pipe1}    #{red_marker} #{yellow_pipe2} #{old_highlighted}"
        output << "    #{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
      else
        old_str = "%4d" % line_num
        new_str = "%4d" % line_num
        output << "#{old_str}|    - | #{old_highlighted}"
        output << "    |#{new_str}+ | #{new_highlighted}"
      end

      output.join("\n")
    end

    # Tokenize XML line into meaningful tokens
    def tokenize_xml(line)
      tokens = []
      scanner = StringScanner.new(line)

      until scanner.eos?
        # Skip whitespace (preserve it as tokens to maintain spacing)
        tokens << if scanner.scan(/\s+/)
                    scanner.matched
                  # Element opening/closing tags
                  elsif scanner.scan(/<\/?[\w:-]+/)
                    scanner.matched
                  # Attributes (name="value" or name='value')
                  elsif scanner.scan(/[\w:-]+="[^"]*"/)
                    scanner.matched
                  elsif scanner.scan(/[\w:-]+='[^']*'/)
                    scanner.matched
                  # Attribute name without value
                  elsif scanner.scan(/[\w:-]+=/)
                    scanner.matched
                  # Self-closing tag end or tag end
                  elsif scanner.scan(/\/?>/)
                    scanner.matched
                  # Text content
                  elsif scanner.scan(/[^<>\s]+/)
                    scanner.matched
                  # Any other character
                  else
                    scanner.getch
                  end
      end

      tokens
    end

    # Build highlighted text from token diff
    def build_token_highlighted_text(token_diffs, side)
      parts = []

      token_diffs.each do |change|
        case change.action
        when "="
          # Unchanged token - apply visualization with explicit reset to default color
          visual = change.old_element.chars.map do |char|
            @visualization_map.fetch(char, char)
          end.join

          # Explicitly reset color for unchanged tokens in colored context
          parts << if @use_color
                     Paint[visual, :default]
                   else
                     visual
                   end
        when "-"
          # Deleted token (only show on old side)
          if side == :old
            token = change.old_element
            parts << apply_visualization(token, :red)
          end
        when "+"
          # Added token (only show on new side)
          if side == :new
            token = change.new_element
            parts << apply_visualization(token, :green)
          end
        when "!"
          # Changed token
          if side == :old
            token = change.old_element
            parts << apply_visualization(token, :red)
          else
            token = change.new_element
            parts << apply_visualization(token, :green)
          end
        end
      end

      parts.join
    end

    # Format element matches for display
    def format_element_matches(matches, map1, map2, lines1, lines2)
      # Build a set of elements that should be skipped because an ancestor will show the diff
      # Strategy: Find all elements with diffs, then mark all their ancestors for skipping
      elements_to_skip = Set.new

      # First pass: identify all elements that have line differences
      elements_with_diffs = Set.new
      matches.each do |match|
        next unless match.status == :matched

        range1 = map1[match.elem1]
        range2 = map2[match.elem2]
        next unless range1 && range2

        elem_lines1 = lines1[range1.start_line..range1.end_line]
        elem_lines2 = lines2[range2.start_line..range2.end_line]

        if elem_lines1 != elem_lines2
          elements_with_diffs.add(match.elem1)
        end
      end

      # Second pass: skip elements that are children of other elements with diffs
      # This shows only the outermost elements with changes, not their descendants
      elements_with_diffs.each do |elem|
        # Check if this element has a parent that also has diffs
        has_parent_with_diff = false
        if elem.respond_to?(:parent)
          current = elem.parent
          while current
            if current.respond_to?(:name) && elements_with_diffs.include?(current)
              has_parent_with_diff = true
              break
            end
            current = current.respond_to?(:parent) ? current.parent : nil
          end
        end

        # If this element has a parent with diffs, skip it (show the parent instead)
        if has_parent_with_diff
          elements_to_skip.add(elem)
        end
      end

      # Now replace the old variable name with the new one in the rest of the method
      children_with_matched_parents_showing_diff = elements_to_skip

      # Build a set of all elements that are children of matched parents
      # These deleted/inserted children will be shown within their parent's diff
      children_of_matched_parents = Set.new
      matches.each do |match|
        next unless match.status == :matched

        # Get all children of this matched element
        elem = match.elem1 || match.elem2
        next unless elem.respond_to?(:children)

        elem.children.each do |child|
          children_of_matched_parents.add(child) if child.respond_to?(:name)
        end

        # Also check the other side
        other_elem = match.elem1 ? match.elem2 : match.elem1
        next unless other_elem&.respond_to?(:children)

        other_elem.children.each do |child|
          children_of_matched_parents.add(child) if child.respond_to?(:name)
        end
      end

      # Collect diff sections with metadata
      diff_sections = []
      matches.each do |match|
        case match.status
        when :matched
          # Skip if this element is a child of a parent that will show the diff
          next if children_with_matched_parents_showing_diff.include?(match.elem1)

          # Format and collect diff section
          section = format_matched_element_with_metadata(match, map1, map2,
                                                         lines1, lines2)
          diff_sections << section if section
        when :deleted
          # Skip if this is a child of a matched parent (will be shown in parent's diff)
          next if children_of_matched_parents.include?(match.elem1)

          section = format_deleted_element_with_metadata(match, map1, lines1)
          diff_sections << section if section
        when :inserted
          # Skip if this is a child of a matched parent (will be shown in parent's diff)
          next if children_of_matched_parents.include?(match.elem2)

          section = format_inserted_element_with_metadata(match, map2, lines2)
          diff_sections << section if section
        end
      end

      # Sort diff_sections by line number to ensure proper ordering
      diff_sections.sort_by! do |section|
        # Use whichever line number is available, preferring file 1
        section[:start_line1] || section[:start_line2] || 0
      end

      # Group diffs by proximity if diff_grouping_lines is set
      if @diff_grouping_lines
        groups = group_diff_sections(diff_sections, @diff_grouping_lines)
        format_diff_groups(groups, lines1, lines2)
      else
        # No grouping - just join sections
        diff_sections.map { |s| s[:formatted] }.compact.join("\n\n")
      end
    end

    # Format matched element with metadata for grouping
    def format_matched_element_with_metadata(match, map1, map2, lines1, lines2)
      range1 = map1[match.elem1]
      range2 = map2[match.elem2]
      return nil unless range1 && range2

      formatted = format_matched_element(match, map1, map2, lines1, lines2)
      return nil unless formatted

      {
        formatted: formatted,
        start_line1: range1.start_line,
        end_line1: range1.end_line,
        start_line2: range2.start_line,
        end_line2: range2.end_line,
        path: match.path.join("/"),
      }
    end

    # Format deleted element with metadata for grouping
    def format_deleted_element_with_metadata(match, map1, lines1)
      range1 = map1[match.elem1]
      return nil unless range1

      formatted = format_deleted_element(match, map1, lines1)
      return nil unless formatted

      {
        formatted: formatted,
        start_line1: range1.start_line,
        end_line1: range1.end_line,
        start_line2: nil,
        end_line2: nil,
        path: match.path.join("/"),
      }
    end

    # Format inserted element with metadata for grouping
    def format_inserted_element_with_metadata(match, map2, lines2)
      range2 = map2[match.elem2]
      return nil unless range2

      formatted = format_inserted_element(match, map2, lines2)
      return nil unless formatted

      {
        formatted: formatted,
        start_line1: nil,
        end_line1: nil,
        start_line2: range2.start_line,
        end_line2: range2.end_line,
        path: match.path.join("/"),
      }
    end

    # Group diff sections by proximity
    def group_diff_sections(sections, grouping_lines)
      return [] if sections.empty?

      groups = []
      current_group = [sections[0]]

      sections[1..].each do |section|
        last_section = current_group.last

        # Calculate gap within each file separately
        # For file 1
        gap1 = if last_section[:end_line1] && section[:start_line1]
                 section[:start_line1] - last_section[:end_line1] - 1
               else
                 Float::INFINITY # If either file doesn't have this section, treat as infinite gap
               end

        # For file 2
        gap2 = if last_section[:end_line2] && section[:start_line2]
                 section[:start_line2] - last_section[:end_line2] - 1
               else
                 Float::INFINITY # If either file doesn't have this section, treat as infinite gap
               end

        # Use the maximum gap between the two files
        max_gap = [gap1, gap2].max

        if max_gap <= grouping_lines
          # Within grouping distance - add to current group
          current_group << section
        else
          # Too far - start new group
          groups << current_group
          current_group = [section]
        end
      end

      # Add final group
      groups << current_group unless current_group.empty?

      groups
    end

    # Format groups of diffs
    def format_diff_groups(groups, lines1, lines2)
      output = []

      groups.each_with_index do |group, group_idx|
        # Add spacing between groups (but not before the first group)
        output << "" if group_idx.positive?

        if group.length > 1
          # Multiple diffs - show as contiguous code block
          output << colorize("Context block has #{group.length} diffs",
                             :yellow, :bold)
          output << ""
          # Show each diff's pre-formatted output
          group.each do |section|
            output << section[:formatted] if section[:formatted]
          end
        else
          # Single diff - use the pre-formatted output with token highlighting
          output << group[0][:formatted] if group[0][:formatted]
        end
      end

      output.join("\n")
    end

    # Format a contiguous code block showing all lines in range with diffs highlighted
      def format_contiguous_context_block(group, lines1, lines2)
        # Find the min/max line range across all diffs in the group
        # These ranges come directly from the DOM matcher which has already
        # identified the correct elements that differ
        min_line1 = group.map { |s| s[:start_line1] }.compact.min
        max_line1 = group.map { |s| s[:end_line1] }.compact.max
        min_line2 = group.map { |s| s[:start_line2] }.compact.min
        max_line2 = group.map { |s| s[:end_line2] }.compact.max

        return "" unless min_line1 || min_line2

        # Expand to include complete parent elements
        # The DOM matcher provides leaf-level differences, but we need to show
        # complete parent context for readability
        if min_line1 && max_line1
          min_line1, max_line1 = expand_to_parent_elements(lines1, min_line1, max_line1)
        end
        if min_line2 && max_line2
          min_line2, max_line2 = expand_to_parent_elements(lines2, min_line2, max_line2)
        end

      # Use the DOM-identified ranges directly without expansion
      # The DOM matcher has already found the correct elements to compare
      # Extract the line ranges (handle cases where one side might be nil)
      range1_lines = min_line1 && max_line1 ? lines1[min_line1..max_line1] : []
      range2_lines = min_line2 && max_line2 ? lines2[min_line2..max_line2] : []

      # Detect non-ASCII characters in the diff range
      all_text = (range1_lines + range2_lines).join
      non_ascii = detect_non_ascii(all_text)

      output = []

      # Add non-ASCII warning if any detected
      unless non_ascii.empty?
        warning = "(WARNING: non-ASCII characters detected in diff: [#{non_ascii.join(', ')}])"
        output << colorize(warning, :yellow)
        output << ""
      end

      # Use DOM-based diff information from the group sections
      # Build a map of which lines belong to which sections
      line1_to_section = {}
      line2_to_section = {}

      group.each do |section|
        if section[:start_line1] && section[:end_line1]
          (section[:start_line1]..section[:end_line1]).each do |line_num|
            line1_to_section[line_num] = section
          end
        end
        if section[:start_line2] && section[:end_line2]
          (section[:start_line2]..section[:end_line2]).each do |line_num|
            line2_to_section[line_num] = section
          end
        end
      end

      # Process lines based on DOM diff information
      # When elements are grouped together, we show ALL lines in the range
      # The grouping logic already determined these lines should be shown together

      # Show all lines from file1 in the range as deletions
      # This ensures multi-line elements that get compressed are fully shown
      if min_line1 && max_line1
        (min_line1..max_line1).each do |i|
          line_content = lines1[i]
          output << format_unified_line(i + 1, nil, "-", line_content, :red)
        end
      end

      # Show all lines from file2 in the range as additions
      # This ensures single-line elements that expand are fully shown
      if min_line2 && max_line2
        (min_line2..max_line2).each do |i|
          line_content = lines2[i]
          output << format_unified_line(nil, i + 1, "+", line_content, :green)
        end
      end

      output.join("\n")
    end

    # Expand line range to include the immediate parent element that contains changes
    # Only includes lines from parent opening tag to the last changed line's closing tag
    def expand_to_parent_elements(lines, min_line, max_line)
      return [min_line, max_line] if lines.empty?

      expanded_min = min_line
      expanded_max = max_line

      # Track tag stack as we scan backwards to find the immediate parent
      tag_stack = []

      # Scan backwards from min_line - 1 to find the immediate parent opening tag
      i = min_line - 1
      scan_limit = [min_line - 10, 0].max  # Limit backward scan to 10 lines

      while i >= scan_limit
        line = lines[i]

        # Process this line to update tag stack
        # We scan the line in reverse to properly handle tag nesting
        # Find all tags in this line (both opening and closing)
        tags_in_line = []

        # Find closing tags (these would have been opened before this line)
        line.scan(/<\/([\w:-]+)>/) do |match|
          tags_in_line << { type: :closing, name: match[0], pos: Regexp.last_match.begin(0) }
        end

        # Find opening tags (but skip self-closing ones)
        line.scan(/<([\w:-]+)(?:\s[^>]*)?>/) do |match|
          tag_name = match[0]
          match_start = Regexp.last_match.begin(0)
          match_full = Regexp.last_match[0]

          # Skip self-closing tags
          next if match_full.end_with?("/>")

          # Check if closing tag exists on same line after this opening tag
          closing_match = line[match_start..].match(/<\/#{Regexp.escape(tag_name)}>/)
          next if closing_match

          tags_in_line << { type: :opening, name: tag_name, pos: match_start }
        end

        # Sort tags by position (in reverse order for this line)
        tags_in_line.sort_by! { |t| -t[:pos] }

        # Process tags in reverse order (right to left on the line)
        tags_in_line.each do |tag_info|
          if tag_info[:type] == :closing
            # Add to stack - we're moving backwards so closing tags mean we need to find their opening
            tag_stack << tag_info[:name]
          elsif tag_info[:type] == :opening
            # This is an opening tag
            if tag_stack.empty?
              # No matching closing tag in our range - this is a parent element!
              # Expand to include this line
              expanded_min = i
            elsif tag_stack.last == tag_info[:name]
              # This opening tag matches the last closing tag we saw
              tag_stack.pop
            else
              # Mismatched - still a parent element
              expanded_min = i
            end
          end
        end

        # If we found parent elements and the stack is now empty, we can stop
        # (but only if we've expanded)
        break if tag_stack.empty? && expanded_min < min_line

        i -= 1
      end

      # Now scan forwards from max_line + 1 to find closing tags
      # We need to find closing tags for any elements opened in our expanded range
      tag_stack = []

      # First, build the tag stack from our expanded range
      (expanded_min..max_line).each do |line_idx|
        line = lines[line_idx]

        # Find all tags in this line
        tags_in_line = []

        # Find opening tags (but skip self-closing ones)
        line.scan(/<([\w:-]+)(?:\s[^>]*)?>/) do |match|
          tag_name = match[0]
          match_start = Regexp.last_match.begin(0)
          match_full = Regexp.last_match[0]

          # Skip self-closing tags
          next if match_full.end_with?("/>")

          # Check if closing tag exists on same line after this opening tag
          closing_match = line[match_start..].match(/<\/#{Regexp.escape(tag_name)}>/)
          next if closing_match

          tags_in_line << { type: :opening, name: tag_name, pos: match_start }
        end

        # Find closing tags
        line.scan(/<\/([\w:-]+)>/) do |match|
          tags_in_line << { type: :closing, name: match[0], pos: Regexp.last_match.begin(0) }
        end

        # Sort tags by position (left to right)
        tags_in_line.sort_by! { |t| t[:pos] }

        # Process tags in order
        tags_in_line.each do |tag_info|
          if tag_info[:type] == :opening
            tag_stack << tag_info[:name]
          elsif tag_info[:type] == :closing
            # Remove from stack if present
            if tag_stack.include?(tag_info[:name])
              # Remove the last occurrence
              idx = tag_stack.rindex(tag_info[:name])
              tag_stack.delete_at(idx) if idx
            end
          end
        end
      end

      # Now scan forward to find closing tags for remaining open tags
      j = max_line + 1
      scan_limit = [max_line + 50, lines.length - 1].min

      while j <= scan_limit && !tag_stack.empty?
        line = lines[j]

        # Check for closing tags
        line.scan(/<\/([\w:-]+)>/) do |match|
          tag_name = match[0]
          if tag_stack.include?(tag_name)
            # Found a closing tag we need
            expanded_max = j
            # Remove from stack
            idx = tag_stack.rindex(tag_name)
            tag_stack.delete_at(idx) if idx
          end
        end

        j += 1
      end

      [expanded_min, expanded_max]
    end

    # Check if elements only differ in their children (not in attributes or direct content)
    def elements_only_differ_in_children?(match, map1, map2, lines1, lines2,
_all_matched_elements)
      range1 = map1[match.elem1]
      range2 = map2[match.elem2]
      return false unless range1 && range2

      # Get the opening tag lines
      opening1 = lines1[range1.start_line]
      opening2 = lines2[range2.start_line]

      # If opening tags differ, this element has direct changes
      return false if opening1 != opening2

      # Otherwise, only children differ
      true
    end

    # Format a matched element showing differences
    # Uses object-oriented approach: identify diff blocks, group by proximity, expand with context
    def format_matched_element(match, map1, map2, lines1, lines2)
      range1 = map1[match.elem1]
      range2 = map2[match.elem2]

      return nil unless range1 && range2

      # Extract line ranges for both elements
      elem_lines1 = lines1[range1.start_line..range1.end_line]
      elem_lines2 = lines2[range2.start_line..range2.end_line]

      # Skip if identical
      return nil if elem_lines1 == elem_lines2

      # Run line diff on the element's lines
      diffs = ::Diff::LCS.sdiff(elem_lines1, elem_lines2)

      # Step 1: Identify diff blocks (contiguous runs of changes)
      diff_blocks = identify_diff_blocks(diffs)

      # If no diff blocks found, skip this element
      return nil if diff_blocks.empty?

      # Step 2: Group diff blocks into contexts based on diff_grouping_lines
      contexts = group_diff_blocks_into_contexts(diff_blocks, @diff_grouping_lines || 0)

      # Step 3: Expand each context with context_lines
      expanded_contexts = expand_contexts_with_context_lines(contexts, @context_lines, diffs.length)

      # Step 4: Format each context separately
      output = []
      path_str = match.path.join("/")

      # Only show element header if there are multiple contexts or if explicitly needed
      if expanded_contexts.length > 1
        output << colorize("Element: #{path_str}", :cyan, :bold)
        output << colorize("Context block has #{expanded_contexts.length} diffs", :yellow, :bold)
        output << ""
      end

      expanded_contexts.each_with_index do |context, idx|
        # Add spacing between contexts (but not before the first)
        output << "" if idx > 0

        # Format the context
        output << format_context(context, diffs, range1.start_line, range2.start_line)
      end

      output.join("\n")
    end

    # Identify contiguous diff blocks in a diff array
    # A diff block is a contiguous run of changes (-, +, !)
    # Returns array of DiffBlock objects
    def identify_diff_blocks(diffs)
      blocks = []
      current_start = nil
      current_types = []

      diffs.each_with_index do |change, idx|
        if change.action != "="
          # This is a change
          if current_start.nil?
            # Start new block
            current_start = idx
            current_types = [change.action]
          else
            # Extend current block
            current_types << change.action unless current_types.include?(change.action)
          end
        else
          # This is context (unchanged)
          if current_start
            # End current block
            blocks << Canon::Diff::DiffBlock.new(
              start_idx: current_start,
              end_idx: idx - 1,
              types: current_types
            )
            current_start = nil
            current_types = []
          end
        end
      end

      # Don't forget the last block if it extends to the end
      if current_start
        blocks << Canon::Diff::DiffBlock.new(
          start_idx: current_start,
          end_idx: diffs.length - 1,
          types: current_types
        )
      end

      blocks
    end

    # Group diff blocks into contexts based on proximity (diff_grouping_lines)
    # Returns array of arrays: [[block1, block2], [block3], ...]
    def group_diff_blocks_into_contexts(blocks, grouping_lines)
      return [] if blocks.empty?

      contexts = []
      current_context = [blocks[0]]

      blocks[1..].each do |block|
        last_block = current_context.last
        gap = block.start_idx - last_block.end_idx - 1

        if gap <= grouping_lines
          # Within grouping distance - add to current context
          current_context << block
        else
          # Too far - start new context
          contexts << current_context
          current_context = [block]
        end
      end

      # Add final context
      contexts << current_context unless current_context.empty?

      contexts
    end

    # Expand each context with context_lines before/after
    # Returns array of DiffContext objects
    def expand_contexts_with_context_lines(contexts, context_lines, total_lines)
      contexts.map do |context|
        first_block = context.first
        last_block = context.last

        # Expand with context_lines, but don't go out of bounds
        start_idx = [first_block.start_idx - context_lines, 0].max
        end_idx = [last_block.end_idx + context_lines, total_lines - 1].min

        Canon::Diff::DiffContext.new(
          start_idx: start_idx,
          end_idx: end_idx,
          blocks: context
        )
      end
    end

    # Format a context (a group of diff blocks with surrounding context lines)
    def format_context(context, diffs, base_line1, base_line2)
      output = []

      # Process each diff item in the context range
      (context.start_idx..context.end_idx).each do |idx|
        change = diffs[idx]

        # Get absolute line numbers from the diff positions
        line1 = change.old_position ? base_line1 + change.old_position + 1 : nil
        line2 = change.new_position ? base_line2 + change.new_position + 1 : nil

        case change.action
        when "="
          # Unchanged line (context)
          output << format_unified_line(line1, line2, " ", change.old_element)
        when "-"
          # Deletion
          output << format_unified_line(line1, nil, "-", change.old_element, :red)
        when "+"
          # Addition
          output << format_unified_line(nil, line2, "+", change.new_element, :green)
        when "!"
          # Change - show with token-level highlighting
          old_tokens = tokenize_xml(change.old_element)
          new_tokens = tokenize_xml(change.new_element)
          token_diffs = ::Diff::LCS.sdiff(old_tokens, new_tokens)

          old_highlighted = build_token_highlighted_text(token_diffs, :old)
          new_highlighted = build_token_highlighted_text(token_diffs, :new)

          if @use_color
            yellow_old = Paint["%4d" % line1, :yellow]
            yellow_pipe1 = Paint["|", :yellow]
            yellow_new = Paint["%4d" % line2, :yellow]
            yellow_pipe2 = Paint["|", :yellow]
            red_marker = Paint["-", :red]
            green_marker = Paint["+", :green]

            output << "#{yellow_old}#{yellow_pipe1}    #{red_marker} #{yellow_pipe2} #{old_highlighted}"
            output << "    #{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
          else
            output << "#{'%4d' % line1}|    - | #{old_highlighted}"
            output << "    |#{'%4d' % line2}+ | #{new_highlighted}"
          end
        end
      end

      output.join("\n")
    end

    # Build hunks from diffs with context and grouping
    def build_hunks_from_diffs(diffs, context_lines, diff_grouping_lines)
      return [] if diffs.empty?

      hunks = []
      current_hunk = []
      last_change_index = -context_lines - 1

      # Use diff_grouping_lines if set, otherwise use context_lines * 2 for grouping
      grouping_distance = diff_grouping_lines || (context_lines * 2)

      diffs.each_with_index do |change, index|
        # Check if we should start a new hunk based on grouping distance
        if !current_hunk.empty? && index - last_change_index > grouping_distance + 1
          hunks << current_hunk
          current_hunk = []
        end

        # Add context before first change in hunk
        if current_hunk.empty? && change.action != "="
          start_context = [index - context_lines, 0].max
          (start_context...index).each do |i|
            current_hunk << diffs[i] if i < diffs.length
          end
        end

        current_hunk << change

        # Track last change for hunk grouping
        last_change_index = index if change.action != "="
      end

      # Add context after last change in final hunk
      unless current_hunk.empty?
        # Find the last change index in current hunk
        last_change_idx = current_hunk.rindex { |c| c.action != "=" }
        if last_change_idx
          # Add context lines after the last change
          context_start = last_change_idx + 1
          context_end = [last_change_idx + context_lines, current_hunk.length - 1].min
          # Context lines are already in the hunk, we just need to make sure
          # we don't add more than needed
        end
        hunks << current_hunk
      end

      hunks
    end

    # Format a hunk within an element
    def format_element_hunk(hunk, base_line1, base_line2)
      output = []

      # Find the first change to determine starting line numbers
      first_change = hunk.first
      line1 = base_line1 + (first_change.old_position || 0)
      line2 = base_line2 + (first_change.new_position || 0)

      i = 0
      while i < hunk.length
        change = hunk[i]

        case change.action
        when "="
          # Unchanged line (context)
          output << format_unified_line(line1 + 1, line2 + 1, " ",
                                        change.old_element)
          line1 += 1
          line2 += 1
          i += 1
        when "-"
          # Collect consecutive deletions
          del_lines = []
          while i < hunk.length && hunk[i].action == "-"
            del_lines << { line_num: line1 + 1, text: hunk[i].old_element }
            line1 += 1
            i += 1
          end

          # Output all deletions as a block
          del_lines.each do |del|
            output << format_unified_line(del[:line_num], nil, "-",
                                          del[:text], :red)
          end
        when "+"
          # Collect consecutive additions
          add_lines = []
          while i < hunk.length && hunk[i].action == "+"
            add_lines << { line_num: line2 + 1, text: hunk[i].new_element }
            line2 += 1
            i += 1
          end

          # Output all additions as a block
          add_lines.each do |add|
            output << format_unified_line(nil, add[:line_num], "+",
                                          add[:text], :green)
          end
        when "!"
          # Collect consecutive changes
          change_pairs = []
          while i < hunk.length && hunk[i].action == "!"
            change_pairs << {
              old_line: line1 + 1,
              new_line: line2 + 1,
              old_text: hunk[i].old_element,
              new_text: hunk[i].new_element,
            }
            line1 += 1
            line2 += 1
            i += 1
          end

          # Output all changes as a block with token highlighting
          change_pairs.each do |pair|
            old_tokens = tokenize_xml(pair[:old_text])
            new_tokens = tokenize_xml(pair[:new_text])
            token_diffs = ::Diff::LCS.sdiff(old_tokens, new_tokens)

            old_highlighted = build_token_highlighted_text(token_diffs, :old)
            new_highlighted = build_token_highlighted_text(token_diffs, :new)

            if @use_color
              yellow_old = Paint["%4d" % pair[:old_line], :yellow]
              yellow_pipe1 = Paint["|", :yellow]
              yellow_new = Paint["%4d" % pair[:new_line], :yellow]
              yellow_pipe2 = Paint["|", :yellow]
              red_marker = Paint["-", :red]
              green_marker = Paint["+", :green]

              output << "#{yellow_old}#{yellow_pipe1}    #{red_marker} #{yellow_pipe2} #{old_highlighted}"
              output << "    #{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
            else
              output << "#{'%4d' % pair[:old_line]}|    - | #{old_highlighted}"
              output << "    |#{'%4d' % pair[:new_line]}+ | #{new_highlighted}"
            end
          end
        end
      end

      output.join("\n")
    end

    # Format a deleted element
    def format_deleted_element(match, map1, lines1)
      range1 = map1[match.elem1]
      return nil unless range1

      output = []
      path_str = match.path.join("/")
      output << colorize("Element: #{path_str} [DELETED]", :red, :bold)

      # Show all lines as deleted
      (range1.start_line..range1.end_line).each do |i|
        output << format_unified_line(i + 1, nil, "-", lines1[i], :red)
      end

      output.join("\n")
    end

    # Format an inserted element
    def format_inserted_element(match, map2, lines2)
      range2 = map2[match.elem2]
      return nil unless range2

      output = []
      path_str = match.path.join("/")
      output << colorize("Element: #{path_str} [INSERTED]", :green, :bold)

      # Show all lines as inserted
      (range2.start_line..range2.end_line).each do |i|
        output << format_unified_line(nil, i + 1, "+", lines2[i], :green)
      end

      output.join("\n")
    end

    # Build a tree structure from differences
    def build_diff_tree(differences)
      tree = {}

      differences.each do |diff|
        if diff.key?(:path)
          # Ruby object difference
          add_to_tree(tree, diff[:path], diff)
        else
          # DOM difference - extract path from node
          path = extract_dom_path(diff)
          add_to_tree(tree, path, diff)
        end
      end

      tree
    end

    # Add a difference to the tree structure
    def add_to_tree(tree, path, diff)
      parts = path.to_s.split(/[.\[\]]/).reject(&:empty?)
      current = tree

      parts.each_with_index do |part, index|
        current[part] ||= {}
        if index == parts.length - 1
          current[part][:__diff__] = diff
        else
          current = current[part]
        end
      end
    end

    # Extract path from DOM node difference
    def extract_dom_path(diff)
      node = diff[:node1] || diff[:node2]
      return "" unless node

      parts = []
      current = node

      while current.respond_to?(:name)
        parts.unshift(current.name) if current.name
        current = current.parent if current.respond_to?(:parent)
      end

      parts.join(".")
    end

    # Render tree structure with box-drawing characters
    def render_tree(tree, prefix: "", is_last: true)
      output = []

      # Sort keys, filtering out the special :__diff__ key
      # Handle mixed types by converting to string for sorting
      sorted_keys = tree.keys.reject { |k| k == :__diff__ }
      begin
        sorted_keys = sorted_keys.sort_by(&:to_s)
      rescue ArgumentError
        # If sorting fails, just use the keys as-is
        sorted_keys = sorted_keys
      end

      sorted_keys.each_with_index do |key, index|
        is_last_item = (index == sorted_keys.length - 1)
        connector = is_last_item ? "└── " : "├── "
        continuation = is_last_item ? "    " : "│   "

        value = tree[key]
        diff = value[:__diff__] if value.is_a?(Hash)

        if diff
          # Render difference
          output << render_diff_node(key, diff, prefix, connector)
        else
          # Render intermediate path
          output << colorize("#{prefix}#{connector}#{key}:", :cyan)
          # Recurse into subtree
          if value.is_a?(Hash)
            output << render_tree(value, prefix: prefix + continuation,
                                         is_last: is_last_item)
          end
        end
      end

      output.join("\n")
    end

    # Render a single diff node
    def render_diff_node(key, diff, prefix, connector)
      output = []

      # Show full path if available (path in cyan, no color on tree structure)
      path_display = if diff[:path] && !diff[:path].empty?
                       colorize(diff[:path].to_s, :cyan, :bold)
                     else
                       colorize(key.to_s, :cyan)
                     end

      output << "#{prefix}#{connector}#{path_display}:"

      # Determine continuation for nested values
      # If connector is "├── " we use "│   " for continuation
      # If connector is "└── " we use "    " for continuation
      continuation = connector.start_with?("├") ? "│   " : "    "
      value_prefix = prefix + continuation

      diff_code = diff[:diff_code] || diff[:diff1]

      case diff_code
      when Comparison::MISSING_HASH_KEY
        # Added or removed key
        if diff[:value1].nil?
          # Added in file2
          if diff[:value2].is_a?(Hash) && !diff[:value2].empty?
            # Show nested structure for added hash
            output.concat(render_added_hash(diff[:value2], value_prefix))
          else
            value_str = format_value_for_diff(diff[:value2])
            output << "#{value_prefix}└── + #{colorize(value_str, :green)}"
          end
        elsif diff[:value1].is_a?(Hash) && !diff[:value1].empty?
          # Removed in file2
          # Show nested structure for removed hash
          output.concat(render_removed_hash(diff[:value1], value_prefix))
        else
          value_str = format_value_for_diff(diff[:value1])
          output << "#{value_prefix}└── - #{colorize(value_str, :red)}"
        end
      when Comparison::UNEQUAL_PRIMITIVES,
           Comparison::UNEQUAL_HASH_VALUES,
           Comparison::UNEQUAL_ARRAY_ELEMENTS,
           Comparison::UNEQUAL_TEXT_CONTENTS,
           Comparison::UNEQUAL_TYPES
        # Changed value - show detailed diff
        output.concat(render_value_diff(diff[:value1], diff[:value2],
                                        value_prefix))
      when Comparison::UNEQUAL_ARRAY_LENGTHS
        # Array length changed - show detailed element-by-element diff
        output.concat(render_value_diff(diff[:value1], diff[:value2],
                                        value_prefix))
      else
        # Fallback - show values if available
        if diff[:value1] && diff[:value2]
          output.concat(render_value_diff(diff[:value1], diff[:value2],
                                          value_prefix))
        elsif diff[:value1]
          value_str = format_value_for_diff(diff[:value1])
          output << "#{value_prefix}└── - #{colorize(value_str, :red)}"
        elsif diff[:value2]
          value_str = format_value_for_diff(diff[:value2])
          output << "#{value_prefix}└── + #{colorize(value_str, :green)}"
        else
          output << "#{value_prefix}└── [UNKNOWN CHANGE]"
        end
      end

      output.join("\n")
    end

    # Render an added hash with nested structure
    def render_added_hash(hash, prefix)
      output = []
      sorted_keys = hash.keys.sort_by(&:to_s)

      sorted_keys.each_with_index do |key, index|
        is_last = (index == sorted_keys.length - 1)
        connector = is_last ? "└──" : "├──"
        continuation = is_last ? "    " : "│   "

        value = hash[key]
        if value.is_a?(Hash) && !value.empty?
          # Nested hash - recurse
          output << "#{prefix}#{connector} + #{colorize(key.to_s, :green)}:"
          output.concat(render_added_hash(value, prefix + continuation))
        else
          # Leaf value
          value_str = format_value_for_diff(value)
          output << "#{prefix}#{connector} + #{colorize(key.to_s,
                                                        :green)}: #{colorize(
                                                          value_str, :green
                                                        )}"
        end
      end

      output
    end

    # Render a removed hash with nested structure
    def render_removed_hash(hash, prefix)
      output = []
      sorted_keys = hash.keys.sort_by(&:to_s)

      sorted_keys.each_with_index do |key, index|
        is_last = (index == sorted_keys.length - 1)
        connector = is_last ? "└──" : "├──"
        continuation = is_last ? "    " : "│   "

        value = hash[key]
        if value.is_a?(Hash) && !value.empty?
          # Nested hash - recurse
          output << "#{prefix}#{connector} - #{colorize(key.to_s, :red)}:"
          output.concat(render_removed_hash(value, prefix + continuation))
        else
          # Leaf value
          value_str = format_value_for_diff(value)
          output << "#{prefix}#{connector} - #{colorize(key.to_s,
                                                        :red)}: #{colorize(
                                                          value_str, :red
                                                        )}"
        end
      end

      output
    end

    # Render a detailed diff for two values
    def render_value_diff(val1, val2, prefix)
      output = []

      # Handle arrays - show element-by-element comparison
      if val1.is_a?(Array) && val2.is_a?(Array)
        max_len = [val1.length, val2.length].max
        changes = []

        (0...max_len).each do |i|
          elem1 = i < val1.length ? val1[i] : nil
          elem2 = i < val2.length ? val2[i] : nil

          if elem1.nil?
            # Element added
            elem_str = format_value_for_diff(elem2)
            changes << { type: :add, index: i, value: elem_str }
          elsif elem2.nil?
            # Element removed
            elem_str = format_value_for_diff(elem1)
            changes << { type: :remove, index: i, value: elem_str }
          elsif elem1 != elem2
            # Element changed
            elem1_str = format_value_for_diff(elem1)
            elem2_str = format_value_for_diff(elem2)
            changes << { type: :change, index: i, old: elem1_str,
                         new: elem2_str }
          end
          # Skip if elements are equal
        end

        # Render changes with proper connectors
        changes.each_with_index do |change, idx|
          is_last = (idx == changes.length - 1)
          connector = is_last ? "└──" : "├──"

          case change[:type]
          when :add
            output << "#{prefix}#{connector} [#{change[:index]}] + #{colorize(
              change[:value], :green
            )}"
          when :remove
            output << "#{prefix}#{connector} [#{change[:index]}] - #{colorize(
              change[:value], :red
            )}"
          when :change
            output << "#{prefix}├── [#{change[:index]}] - #{colorize(
              change[:old], :red
            )}"
            output << if is_last
                        "#{prefix}└── [#{change[:index]}] + #{colorize(
                          change[:new], :green
                        )}"
                      else
                        "#{prefix}├── [#{change[:index]}] + #{colorize(
                          change[:new], :green
                        )}"
                      end
          end
        end
      elsif val1.is_a?(Hash) && val2.is_a?(Hash)
        # For hashes, show summary (detailed comparison happens recursively)
        val1_str = format_value_for_diff(val1)
        val2_str = format_value_for_diff(val2)
        output << "#{prefix}├── - #{colorize(val1_str, :red)}"
        output << "#{prefix}└── + #{colorize(val2_str, :green)}"
      else
        # Primitives - show actual values
        val1_str = format_value_for_diff(val1)
        val2_str = format_value_for_diff(val2)
        output << "#{prefix}├── - #{colorize(val1_str, :red)}"
        output << "#{prefix}└── + #{colorize(val2_str, :green)}"
      end

      output
    end

    # Format a value for diff display (more detailed than inline)
    def format_value_for_diff(value)
      case value
      when String
        "\"#{value}\""
      when Numeric, TrueClass, FalseClass
        value.to_s
      when NilClass
        "nil"
      when Array
        if value.empty?
          "[]"
        elsif value.all? do |v|
          v.is_a?(String) || v.is_a?(Numeric) || v.is_a?(TrueClass) || v.is_a?(FalseClass) || v.nil?
        end
          # Simple array - show inline
          "[#{value.map { |v| format_value_for_diff(v) }.join(', ')}]"
        else
          # Complex array - show summary
          "{Array with #{value.length} elements}"
        end
      when Hash
        if value.empty?
          "{}"
        else
          "{Hash with #{value.keys.length} keys: #{value.keys.take(3).map(&:to_s).join(', ')}#{value.keys.length > 3 ? '...' : ''}}"
        end
      else
        value.inspect
      end
    end

    # Format a value inline for tree display
    def format_value_inline(value)
      case value
      when String
        "\"#{value}\""
      when Numeric, TrueClass, FalseClass
        value.to_s
      when NilClass
        "nil"
      when Array
        "{Array with #{value.length} elements}"
      when Hash
        "{Hash with #{value.keys.length} keys: #{value.keys.take(3).join(', ')}}"
      else
        value.inspect
      end
    end

    # Format a line for line-by-line diff
    def format_line(num, marker, content, color = nil)
      num_str = "%4d" % num
      marker_part = "#{marker} "

      if color
        colorize("#{num_str}#{marker_part}| #{content}", color)
      else
        "#{num_str}#{marker_part}| #{content}"
      end
    end

    # Format a single difference
    def format_difference(diff, number, format)
      if diff.key?(:path)
        # Ruby object difference (JSON/YAML)
        format_ruby_difference(diff, number)
      else
        # DOM difference (XML/HTML)
        format_dom_difference(diff, number, format)
      end
    end

    # Format a Ruby object difference
    def format_ruby_difference(diff, number)
      output = []
      diff_code = diff[:diff_code]
      description = DIFF_DESCRIPTIONS[diff_code]

      output << colorize("Difference #{number}: ", :cyan, :bold) +
        colorize("#{description} (#{diff_code})", :red)

      if diff[:path] && !diff[:path].empty?
        output << "  #{colorize('Path: ',
                                :blue)}#{colorize(diff[:path], :white, :bold)}"
      end

      case diff_code
      when Comparison::MISSING_HASH_KEY
        if diff[:value1].nil?
          output << "  #{colorize('Present in: ', :green)}file2"
          output << "  #{colorize('Missing in: ', :red)}file1"
          output << "  #{colorize('Value: ',
                                  :blue)}#{format_value(diff[:value2])}"
        else
          output << "  #{colorize('Present in: ', :green)}file1"
          output << "  #{colorize('Missing in: ', :red)}file2"
          output << "  #{colorize('Value: ',
                                  :blue)}#{format_value(diff[:value1])}"
        end
      when Comparison::UNEQUAL_TYPES
        output << "  #{colorize('Type 1: ',
                                :blue)}#{colorize(diff[:value1].class.name,
                                                  :white)}"
        output << "  #{colorize('Type 2: ',
                                :blue)}#{colorize(diff[:value2].class.name,
                                                  :white)}"
      when Comparison::UNEQUAL_ARRAY_LENGTHS
        output << "  #{colorize('Length 1: ',
                                :blue)}#{colorize(diff[:value1].length.to_s,
                                                  :white)}"
        output << "  #{colorize('Length 2: ',
                                :blue)}#{colorize(diff[:value2].length.to_s,
                                                  :white)}"
      else
        output << "  #{colorize('Value 1: ',
                                :blue)}#{format_value(diff[:value1])}"
        output << "  #{colorize('Value 2: ',
                                :blue)}#{format_value(diff[:value2])}"
      end

      output.join("\n")
    end

    # Format a DOM difference
    def format_dom_difference(diff, number, _format)
      output = []
      diff_code = diff[:diff1]
      description = DIFF_DESCRIPTIONS[diff_code]

      output << colorize("Difference #{number}: ", :cyan, :bold) +
        colorize("#{description} (#{diff_code})", :red)

      node1 = diff[:node1]
      node2 = diff[:node2]

      case diff_code
      when Comparison::UNEQUAL_ELEMENTS
        output << "  #{colorize('Element 1: ',
                                :blue)}#{colorize("<#{node1.name}>", :white,
                                                  :bold)}"
        output << "  #{colorize('Element 2: ',
                                :blue)}#{colorize("<#{node2.name}>", :white,
                                                  :bold)}"

      when Comparison::UNEQUAL_TEXT_CONTENTS
        text1 = extract_text(node1)
        text2 = extract_text(node2)
        parent_tag = parent_tag_name(node1)

        if parent_tag
          output << "  #{colorize('Element: ',
                                  :blue)}#{colorize("<#{parent_tag}>", :white,
                                                    :bold)}"
        end

        output << "  #{colorize('Text 1: ', :blue)}#{format_text(text1)}"
        output << "  #{colorize('Text 2: ', :blue)}#{format_text(text2)}"

      when Comparison::UNEQUAL_ATTRIBUTES
        output << "  #{colorize('Element: ',
                                :blue)}#{colorize("<#{node1.name}>", :white,
                                                  :bold)}"
        output << "  #{colorize('Attributes differ', :yellow)}"

      when Comparison::MISSING_ATTRIBUTE
        output << "  #{colorize('Element: ',
                                :blue)}#{colorize("<#{node1.name}>", :white,
                                                  :bold)}"
        output << "  #{colorize('Attribute mismatch', :yellow)}"

      when Comparison::UNEQUAL_COMMENTS
        content1 = node1.content.to_s.strip
        content2 = node2.content.to_s.strip
        output << "  #{colorize('Comment 1: ', :blue)}#{format_text(content1)}"
        output << "  #{colorize('Comment 2: ', :blue)}#{format_text(content2)}"

      when Comparison::MISSING_NODE
        output << "  #{colorize('Node missing or extra', :yellow)}"

      else
        output << "  #{colorize('Nodes differ', :yellow)}"
      end

      output.join("\n")
    end

    # Extract text from a node
    def extract_text(node)
      if node.respond_to?(:content)
        node.content.to_s
      elsif node.respond_to?(:text)
        node.text.to_s
      else
        ""
      end
    end

    # Get parent tag name if available
    def parent_tag_name(node)
      return nil unless node.respond_to?(:parent)

      parent = node.parent
      return nil unless parent
      return nil unless parent.respond_to?(:name)

      parent.name
    end

    # Format a value for display
    def format_value(value)
      case value
      when String
        colorize("\"#{value}\"", :green)
      when Numeric, TrueClass, FalseClass
        colorize(value.to_s, :magenta)
      when NilClass
        colorize("nil", :red)
      when Array
        colorize("[Array with #{value.length} elements]", :yellow)
      when Hash
        colorize("{Hash with #{value.keys.length} keys}", :yellow)
      else
        colorize(value.inspect, :white)
      end
    end

    # Format text content for display
    def format_text(text)
      # Truncate long text
      display_text = if text.length > 100
                       "#{text[0..97]}..."
                     else
                       text
                     end

      colorize("\"#{display_text}\"", :green)
    end

    # Check if a token is pure whitespace
    def whitespace_token?(token)
      token.match?(/\A\s+\z/)
    end

    # Apply character visualization using configurable visualization map
    #
    # @param token [String] The token to apply visualization to
    # @param color [Symbol, nil] Optional color to apply (e.g., :red, :green)
    # @return [String] Visualized and optionally colored token
    def apply_visualization(token, color = nil)
      # Replace each character with its visualization from the map
      visual = token.chars.map do |char|
        @visualization_map.fetch(char, char)
      end.join

      # Apply color if provided and color is enabled
      if color && @use_color
        Paint[visual, color, :bold]
      else
        visual
      end
    end

    # Detect non-ASCII characters in text
    def detect_non_ascii(text)
      non_ascii_chars = []
      text.each_char do |char|
        if char.ord > 127
          codepoint = "U+%04X" % char.ord
          visualization = @visualization_map.fetch(char, char)
          non_ascii_chars << if visualization == char
                               "'#{char}' (#{codepoint})"
                             else
                               "'#{char}' (#{codepoint}, shown as: '#{visualization}')"
                             end
        end
      end
      non_ascii_chars.uniq
    end

    # Colorize text if color is enabled
    # RSpec-aware: resets any existing ANSI codes before applying new colors
    def colorize(text, *colors)
      return text unless @use_color

      # Reset ANSI codes first to prevent RSpec's initial red from interfering
      "\e[0m#{Paint[text, *colors]}"
    end
  end
end
