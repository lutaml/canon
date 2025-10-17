# frozen_string_literal: true

require "paint"
require "diff/lcs"
require "diff/lcs/hunk"
require "strscan"
require "set"

module Canon
  # Formatter for displaying semantic differences with color support
  class DiffFormatter
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

    def initialize(use_color: true, mode: :by_object, context_lines: 3, diff_grouping_lines: nil)
      @use_color = use_color
      @mode = mode
      @context_lines = context_lines
      @diff_grouping_lines = diff_grouping_lines
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
        diffs = Diff::LCS.sdiff(lines1, lines2)

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
        diffs = Diff::LCS.sdiff(lines1, lines2)

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
    def format_semantic_diff(diffs, _lines1, _lines2, format)
      output = []

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
          token_diffs = Diff::LCS.sdiff(old_tokens, new_tokens)

          # Build highlighted versions
          old_highlighted = build_token_highlighted_text(token_diffs, :old)
          new_highlighted = build_token_highlighted_text(token_diffs, :new)

          # Format both lines
          output << "#{'%4d' % old_line}|    - | #{old_highlighted}"
          output << "    |#{'%4d' % new_line}+ | #{new_highlighted}"
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
        output << colorize("Warning: DOM parsing failed, using simple diff", :yellow)
        output << colorize("Error: #{e.class}: #{e.message}", :red)

        # Include relevant backtrace lines (first 3 lines from canon library)
        relevant_trace = e.backtrace.select { |line| line.include?('canon') }.take(3)
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
      diffs = Diff::LCS.sdiff(lines1, lines2)

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

      line = "#{old_str}|#{new_str}#{marker_part}| #{content}"

      color ? colorize(line, color) : line
    end

    # Format changed lines with XML-aware token-level diff
    def format_changed_line(line_num, old_text, new_text)
      output = []

      # Tokenize XML lines
      old_tokens = tokenize_xml(old_text)
      new_tokens = tokenize_xml(new_text)

      # Get token-level diff
      token_diffs = Diff::LCS.sdiff(old_tokens, new_tokens)

      # Build highlighted versions
      old_highlighted = build_token_highlighted_text(token_diffs, :old)
      new_highlighted = build_token_highlighted_text(token_diffs, :new)

      # Format both lines
      old_str = "%4d" % line_num
      new_str = "%4d" % line_num

      output << "#{old_str}|    - | #{old_highlighted}"
      output << "    |#{new_str}+ | #{new_highlighted}"

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
          # Unchanged token
          parts << change.old_element
        when "-"
          # Deleted token (only show on old side)
          if side == :old
            parts << Paint[change.old_element, :red, :bold]
          end
        when "+"
          # Added token (only show on new side)
          if side == :new
            parts << Paint[change.new_element, :green, :bold]
          end
        when "!"
          # Changed token
          parts << if side == :old
                     Paint[change.old_element, :red, :bold]
                   else
                     Paint[change.new_element, :green, :bold]
                   end
        end
      end

      parts.join
    end

    # Format element matches for display
    def format_element_matches(matches, map1, map2, lines1, lines2)
      # Build set of all elements that have matched descendants
      elements_with_matched_descendants = Set.new
      matches.each do |match|
        next unless match.status == :matched

        # Mark all ancestors of this matched element
        current = match.elem1.parent if match.elem1.respond_to?(:parent)
        while current && current.respond_to?(:name)
          elements_with_matched_descendants.add(current)
          break unless current.respond_to?(:parent)
          current = current.parent
        end
      end

      # Collect diff sections with metadata
      diff_sections = []
      matches.each do |match|
        case match.status
        when :matched
          # Skip if this element has matched descendants - only show the leaf elements
          next if elements_with_matched_descendants.include?(match.elem1)

          # Format and collect diff section
          section = format_matched_element_with_metadata(match, map1, map2, lines1, lines2)
          diff_sections << section if section
        when :deleted
          section = format_deleted_element_with_metadata(match, map1, lines1)
          diff_sections << section if section
        when :inserted
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
        path: match.path.join("/")
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
        path: match.path.join("/")
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
        path: match.path.join("/")
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
                 Float::INFINITY  # If either file doesn't have this section, treat as infinite gap
               end

        # For file 2
        gap2 = if last_section[:end_line2] && section[:start_line2]
                 section[:start_line2] - last_section[:end_line2] - 1
               else
                 Float::INFINITY  # If either file doesn't have this section, treat as infinite gap
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
        output << "" if group_idx > 0

        if group.length > 1
          # Multiple diffs - show as contiguous code block
          output << colorize("Context block has #{group.length} diffs", :yellow, :bold)
          output << ""
          output << format_contiguous_context_block(group, lines1, lines2)
        else
          # Single diff - no header needed
          output << group[0][:formatted]
        end
      end

      output.join("\n")
    end

    # Format a contiguous code block showing all lines in range with diffs highlighted
    def format_contiguous_context_block(group, lines1, lines2)
      # Find the min/max line range across all diffs in the group
      min_line1 = group.map { |s| s[:start_line1] }.compact.min
      max_line1 = group.map { |s| s[:end_line1] }.compact.max
      min_line2 = group.map { |s| s[:start_line2] }.compact.min
      max_line2 = group.map { |s| s[:end_line2] }.compact.max

      return "" unless min_line1 && max_line1 && min_line2 && max_line2

      # Extract the line ranges
      range1_lines = lines1[min_line1..max_line1]
      range2_lines = lines2[min_line2..max_line2]

      # Run LCS diff on this range
      diffs = Diff::LCS.sdiff(range1_lines, range2_lines)

      # Format as unified diff
      output = []
      line1 = min_line1
      line2 = min_line2

      diffs.each do |change|
        case change.action
        when "="
          # Unchanged line
          output << format_unified_line(line1 + 1, line2 + 1, " ", change.old_element)
          line1 += 1
          line2 += 1
        when "-"
          # Deletion
          output << format_unified_line(line1 + 1, nil, "-", change.old_element, :red)
          line1 += 1
        when "+"
          # Addition
          output << format_unified_line(nil, line2 + 1, "+", change.new_element, :green)
          line2 += 1
        when "!"
          # Change - show with token-level highlighting
          old_tokens = tokenize_xml(change.old_element)
          new_tokens = tokenize_xml(change.new_element)
          token_diffs = Diff::LCS.sdiff(old_tokens, new_tokens)

          old_highlighted = build_token_highlighted_text(token_diffs, :old)
          new_highlighted = build_token_highlighted_text(token_diffs, :new)

          output << "#{'%4d' % (line1 + 1)}|    - | #{old_highlighted}"
          output << "    |#{'%4d' % (line2 + 1)}+ | #{new_highlighted}"
          line1 += 1
          line2 += 1
        end
      end

      output.join("\n")
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
    def format_matched_element(match, map1, map2, lines1, lines2)
      range1 = map1[match.elem1]
      range2 = map2[match.elem2]

      return nil unless range1 && range2

      # Extract line ranges for both elements
      elem_lines1 = lines1[range1.start_line..range1.end_line]
      elem_lines2 = lines2[range2.start_line..range2.end_line]

      # Skip if identical
      return nil if elem_lines1 == elem_lines2

      output = []
      path_str = match.path.join("/")
      output << colorize("Element: #{path_str}", :cyan, :bold)

      # For elements with only opening tag changes (like attribute additions)
      # show just the opening tag line
      if elem_lines1.length == elem_lines2.length &&
          elem_lines1[1..] == elem_lines2[1..] &&
          elem_lines1[0] != elem_lines2[0]
        # Only first line differs - show token-level diff for opening tag
        old_tokens = tokenize_xml(elem_lines1[0])
        new_tokens = tokenize_xml(elem_lines2[0])
        token_diffs = Diff::LCS.sdiff(old_tokens, new_tokens)

        old_highlighted = build_token_highlighted_text(token_diffs, :old)
        new_highlighted = build_token_highlighted_text(token_diffs, :new)

        output << "#{'%4d' % (range1.start_line + 1)}|    - | #{old_highlighted}"
        output << "    |#{'%4d' % (range2.start_line + 1)}+ | #{new_highlighted}"

        return output.join("\n")
      end

      # Run line diff on the element's lines
      diffs = Diff::LCS.sdiff(elem_lines1, elem_lines2)

      # Format line-by-line within element, grouping consecutive changes
      line1 = range1.start_line
      line2 = range2.start_line

      i = 0
      while i < diffs.length
        change = diffs[i]

        case change.action
        when "="
          # Unchanged line
          output << format_unified_line(line1 + 1, line2 + 1, " ",
                                        change.old_element)
          line1 += 1
          line2 += 1
          i += 1
        when "-"
          # Collect consecutive deletions
          del_lines = []
          while i < diffs.length && diffs[i].action == "-"
            del_lines << { line_num: line1 + 1, text: diffs[i].old_element }
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
          while i < diffs.length && diffs[i].action == "+"
            add_lines << { line_num: line2 + 1, text: diffs[i].new_element }
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
          while i < diffs.length && diffs[i].action == "!"
            change_pairs << {
              old_line: line1 + 1,
              new_line: line2 + 1,
              old_text: diffs[i].old_element,
              new_text: diffs[i].new_element
            }
            line1 += 1
            line2 += 1
            i += 1
          end

          # Output all changes as a block with token highlighting
          change_pairs.each do |pair|
            old_tokens = tokenize_xml(pair[:old_text])
            new_tokens = tokenize_xml(pair[:new_text])
            token_diffs = Diff::LCS.sdiff(old_tokens, new_tokens)

            old_highlighted = build_token_highlighted_text(token_diffs, :old)
            new_highlighted = build_token_highlighted_text(token_diffs, :new)

            output << "#{'%4d' % pair[:old_line]}|    - | #{old_highlighted}"
            output << "    |#{'%4d' % pair[:new_line]}+ | #{new_highlighted}"
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

    # Colorize text if color is enabled
    def colorize(text, *colors)
      return text unless @use_color

      Paint[text, *colors]
    end
  end
end
