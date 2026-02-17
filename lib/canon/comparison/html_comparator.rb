# frozen_string_literal: true

require "nokogiri"
require_relative "../comparison" # Load base module with constants first
require_relative "markup_comparator"
require_relative "xml_comparator"
require_relative "match_options"
require_relative "comparison_result"
require_relative "compare_profile"
require_relative "html_compare_profile"
require_relative "../diff/diff_node"
require_relative "../diff/diff_classifier"
require_relative "strategies/match_strategy_factory"
require_relative "../html/data_model"
require_relative "xml_node_comparison"
# Whitespace sensitivity module (single source of truth for sensitive elements)
require_relative "whitespace_sensitivity"

module Canon
  module Comparison
    # HTML comparison class
    # Handles comparison of HTML nodes with various options
    #
    # Inherits shared comparison functionality from MarkupComparator.
    class HtmlComparator < MarkupComparator
      # Default comparison options for HTML
      DEFAULT_OPTS = {
        # Structural filtering options
        ignore_children: false,
        ignore_text_nodes: false,
        ignore_attr_content: [],
        ignore_attrs: [],
        ignore_attrs_by_name: [],
        ignore_nodes: [],

        # Output options
        verbose: false,
        diff_children: false,

        # Match system options
        match_profile: nil,
        match: nil,
        preprocessing: nil,
        global_profile: nil,
        global_options: nil,

        # Diff display options
        diff: nil,
      }.freeze

      class << self
        # Compare two HTML nodes for equivalence
        #
        # @param html1 [String, Nokogiri::HTML::Document] First HTML
        # @param html2 [String, Nokogiri::HTML::Document] Second HTML
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(html1, html2, opts = {}, child_opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Capture original HTML strings BEFORE any parsing/transformation
          # These are used for display to preserve original formatting
          original_str1 = extract_original_string(html1)
          original_str2 = extract_original_string(html2)

          # Resolve match options with format-specific defaults
          match_opts_hash = MatchOptions::Xml.resolve(
            format: :html,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Parse nodes to detect HTML version before creating profile
          # We need to parse early to know if we're dealing with HTML4 or HTML5
          node1 = parse_node(html1, match_opts_hash[:preprocessing],
                             match_opts_hash)
          node2 = parse_node(html2, match_opts_hash[:preprocessing],
                             match_opts_hash)

          # Detect HTML version from parsed nodes
          html_version = detect_html_version_from_node(node1)

          # Create HTML-specific compare profile
          compare_profile = HtmlCompareProfile.new(
            match_opts_hash,
            html_version: html_version,
          )

          # Wrap in ResolvedMatchOptions for DiffClassifier
          match_opts = Canon::Comparison::ResolvedMatchOptions.new(
            match_opts_hash,
            format: :html,
            compare_profile: compare_profile,
          )

          # Store resolved match options hash for use in comparison logic
          opts[:match_opts] = match_opts_hash

          # Use tree diff if semantic_diff option is enabled
          if match_opts.semantic_diff?
            return perform_semantic_tree_diff(html1, html2, opts,
                                              match_opts_hash)
          end

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Serialize preprocessed nodes for diff display (avoid re-preprocessing)
          preprocessed_str1 = serialize_for_display(node1)
          preprocessed_str2 = serialize_for_display(node2)

          differences = []
          diff_children = opts[:diff_children] || false

          # DocumentFragment nodes need special handling - compare their children
          # instead of the fragment nodes themselves
          # This is a SAFETY CHECK for legacy cases where Nokogiri nodes might still be used
          # The main path (parse_node) now returns Canon::Xml::Nodes::RootNode, so this
          # check should rarely trigger, but we keep it for robustness
          result = if fragment_nodes?(node1, node2)
                     compare_fragment_children(node1, node2, opts, child_opts,
                                               diff_children, differences)
                   else
                     XmlNodeComparison.compare_nodes(node1, node2, opts,
                                                     child_opts, diff_children,
                                                     differences)
                   end

          # Classify DiffNodes as normative/informative if we have verbose output
          if opts[:verbose] && !differences.empty?
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select do |d|
              d.is_a?(Canon::Diff::DiffNode)
            end)
          end

          if opts[:verbose]
            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: [preprocessed_str1, preprocessed_str2],
              original_strings: [original_str1, original_str2],
              format: :html,
              html_version: detect_html_version_from_node(node1),
              match_options: match_opts_hash,
              algorithm: :dom,
            )
          elsif result != Comparison::EQUIVALENT && !differences.empty?
            # Non-verbose mode: check equivalence
            # If comparison found differences, classify them to determine if normative
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select do |d|
              d.is_a?(Canon::Diff::DiffNode)
            end)
            # Equivalent if no normative differences (matches semantic algorithm)
            differences.none?(&:normative?)
          else
            # Either equivalent or no differences tracked
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Check if both nodes are document fragments
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Boolean] true if both are document fragments
        def fragment_nodes?(node1, node2)
          (node1.is_a?(Nokogiri::HTML4::DocumentFragment) ||
           node1.is_a?(Nokogiri::XML::DocumentFragment)) &&
            (node2.is_a?(Nokogiri::HTML4::DocumentFragment) ||
             node2.is_a?(Nokogiri::XML::DocumentFragment))
        end

        # Compare children of document fragments
        #
        # @param node1 [Nokogiri::DocumentFragment] First fragment
        # @param node2 [Nokogiri::DocumentFragment] Second fragment
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Child comparison options
        # @param diff_children [Boolean] Whether to diff children
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result constant
        def compare_fragment_children(node1, node2, opts, child_opts,
                                      diff_children, differences)
          all_children1 = node1.children.to_a
          all_children2 = node2.children.to_a

          children1 = XmlNodeComparison.filter_children(all_children1, opts)
          children2 = XmlNodeComparison.filter_children(all_children2, opts)

          if children1.length != children2.length
            return Comparison::UNEQUAL_ELEMENTS
          elsif children1.empty?
            return Comparison::EQUIVALENT
          end

          # Compare each pair of children
          children1.zip(children2).each do |child1, child2|
            child_result = XmlNodeComparison.compare_nodes(child1, child2,
                                                           opts, child_opts,
                                                           diff_children,
                                                           differences)
            return child_result if child_result != Comparison::EQUIVALENT
          end

          Comparison::EQUIVALENT
        end

        # Perform semantic tree diff using SemanticTreeMatchStrategy
        #
        # @param html1 [String, Nokogiri::HTML::Document] First HTML
        # @param html2 [String, Nokogiri::HTML::Document] Second HTML
        # @param opts [Hash] Comparison options
        # @param match_opts_hash [Hash] Resolved match options
        # @return [Boolean, ComparisonResult] Result of tree diff comparison
        def perform_semantic_tree_diff(html1, html2, opts, match_opts_hash)
          # Capture original HTML strings BEFORE any parsing/transformation
          # These are used for display to preserve original formatting
          original_str1 = extract_original_string(html1)
          original_str2 = extract_original_string(html2)

          # Parse to Canon::Xml::Node (preserves preprocessing)
          # For HTML, we parse as XML to get Canon::Xml::Node structure
          node1 = parse_node_for_semantic(html1,
                                          match_opts_hash[:preprocessing])
          node2 = parse_node_for_semantic(html2,
                                          match_opts_hash[:preprocessing])

          # Create strategy using factory
          strategy = Strategies::MatchStrategyFactory.create(
            format: :html,
            match_options: match_opts_hash,
          )

          # Pass Canon::Xml::Node directly - adapter now handles it
          differences = strategy.match(node1, node2)

          # Return based on verbose mode
          if opts[:verbose]
            # Get preprocessed strings for display
            preprocessed = strategy.preprocess_for_display(node1, node2)

            # Detect HTML version (default to HTML5 for Canon nodes)
            html_version = :html5

            # Return ComparisonResult with strategy metadata
            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              original_strings: [original_str1, original_str2],
              format: :html,
              html_version: html_version,
              match_options: match_opts_hash.merge(strategy.metadata),
              algorithm: :semantic,
            )
          else
            # Simple boolean result - equivalent if no normative differences
            differences.none?(&:normative?)
          end
        end

        # Parse node as fragment to preserve actual content
        # Uses HTML4.fragment or HTML5.fragment based on content detection
        #
        # @param node [String, Nokogiri node] Node to parse
        # @param preprocessing [Symbol] Preprocessing mode
        # @param match_opts [Hash] Match options
        # @return [Nokogiri::HTML::DocumentFragment] Parsed fragment
        def parse_node_as_fragment(node, preprocessing = :none, match_opts = {})
          # If already an XML fragment (no meta tags), return it
          if node.is_a?(Nokogiri::XML::DocumentFragment)
            return node
          end

          # Convert HTML fragments to string and re-parse as XML to remove phantom tags
          # This handles cases where pre-parsed HTML4/HTML5 fragments have auto-inserted meta
          html_string = if node.is_a?(Nokogiri::HTML4::DocumentFragment) ||
              node.is_a?(Nokogiri::HTML5::DocumentFragment)
                          node.to_s # Use to_s to avoid re-inserting meta tags
                        elsif node.is_a?(String)
                          node
                        else
                          node.to_html
                        end

          # Use XML fragment parser to preserve structure without auto-generated elements
          # This avoids both HTML4's meta tag insertion and HTML5's tag stripping
          # See: https://stackoverflow.com/questions/25998824/stop-nokogiri-from-adding-doctype-and-meta-tags
          frag = Nokogiri::XML.fragment(html_string)

          # Apply preprocessing if needed
          if preprocessing == :rendered
            normalize_html_style_script_comments(frag)
            normalize_rendered_whitespace(frag, match_opts)
            remove_whitespace_only_text_nodes(frag)
          end

          frag
        end

        # Parse HTML for semantic tree diff using Canon::Html::DataModel
        # Returns Canon::Xml::Node for preprocessing preservation
        #
        # @param html [String, Object] HTML to parse
        # @param preprocessing [Symbol] Preprocessing mode
        # @return [Canon::Xml::Node] Parsed Canon node
        def parse_node_for_semantic(html, preprocessing = :none)
          # If already a Canon::Xml::Node, return as-is
          return html if html.is_a?(Canon::Xml::Node)

          # Convert to string if needed
          html_string = if html.is_a?(String)
                          html
                        elsif html.respond_to?(:to_html)
                          html.to_html
                        elsif html.respond_to?(:to_s)
                          html.to_s
                        else
                          raise Canon::Error,
                                "Unable to convert HTML to string: #{html.class}"
                        end

          # Strip DOCTYPE for consistent parsing
          # Use non-regex approach to avoid ReDoS vulnerability
          # DOCTYPE declarations end with first > character
          doctype_start = html_string =~ /<!DOCTYPE/i
          if doctype_start
            doctype_end = html_string.index(">", doctype_start)
            html_string = html_string[0...doctype_start] + html_string[(doctype_end + 1)..] if doctype_end
            html_string.strip!
          else
            html_string = html_string.strip
          end

          # Apply preprocessing to HTML string before parsing
          processed_html = case preprocessing
                           when :normalize
                             # Normalize whitespace
                             html_string.lines.map(&:strip).reject(&:empty?).join("\n")
                           when :c14n
                             # Canonicalize
                             Canon::Xml::C14n.canonicalize(html_string,
                                                           with_comments: false)
                           when :format
                             # Pretty format
                             Canon.format(html_string, :html)
                           else
                             # :none or unrecognized
                             html_string
                           end

          # Parse using Canon::Html::DataModel to get Canon::Xml::Node
          # HTML parsing with proper HTML-specific handling
          Canon::Html::DataModel.from_html(processed_html)
        end

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        # Returns Nokogiri nodes for DOM comparison (preserves original behavior)
        def parse_node(node, preprocessing = :none, match_opts = {})
          # If already a Canon::Xml::Node, convert to Nokogiri for DOM path
          if node.is_a?(Canon::Xml::Node)
            # Canon nodes used in semantic diff path, convert to Nokogiri for DOM path
            xml_str = Canon::Xml::DataModel.serialize(node)
            node = xml_str
          end

          # If already a Nokogiri node, check for incompatible XML documents
          unless node.is_a?(String)
            # Detect if this is an XML document (not HTML)
            if is_xml_document?(node)
              raise Canon::CompareFormatMismatchError.new(:xml, :html)
            end

            # Normalize HTML documents to fragments to avoid DTD differences
            # This ensures comparing string with document works correctly
            if node.is_a?(Nokogiri::HTML::Document) ||
                node.is_a?(Nokogiri::HTML4::Document) ||
                node.is_a?(Nokogiri::HTML5::Document)
              # Get root element and create fragment from its outer HTML
              # This avoids DOCTYPE and other document-level nodes
              root = node.at_css("html") || node.root
              if root
                node = Nokogiri::XML.fragment(root.to_html)
              end
            end

            # For :rendered preprocessing with Nokogiri nodes
            if preprocessing == :rendered
              # Normalize and return
              frag = node.is_a?(Nokogiri::XML::DocumentFragment) ? node : Nokogiri::XML.fragment(node.to_html)
              normalize_html_style_script_comments(frag)
              normalize_rendered_whitespace(frag, match_opts)
              remove_whitespace_only_text_nodes(frag)
              return frag
            end

            # Return Nokogiri node (now normalized if it was a document)
            return node
          end

          # Check if string contains XML declaration but is actually HTML
          if node.strip.start_with?("<?xml") && !node.match?(/<html[\s>]/i)
            # No <html> tag, this is likely pure XML
            raise Canon::CompareFormatMismatchError.new(:xml, :html)
          end

          # Strip DOCTYPE declarations from HTML strings
          # This normalizes parsed HTML (which includes DOCTYPE) with raw HTML strings
          # Use non-regex approach to avoid ReDoS vulnerability
          doctype_start = node =~ /<!DOCTYPE/i
          if doctype_start
            doctype_end = node.index(">", doctype_start)
            node = node[0...doctype_start] + node[(doctype_end + 1)..] if doctype_end
            node.strip!
          else
            node = node.strip
          end

          # Apply preprocessing to HTML string before parsing
          html_string = case preprocessing
                        when :normalize
                          # Normalize whitespace: collapse runs, trim lines
                          node.lines.map(&:strip).reject(&:empty?).join("\n")
                        when :c14n
                          # Canonicalize the HTML (use XML canonicalization)
                          Canon::Xml::C14n.canonicalize(node,
                                                        with_comments: false)
                        when :format
                          # Pretty format the HTML
                          Canon.format(node, :html)
                        else
                          # :none, :rendered or unrecognized - use as-is
                          node
                        end

          # Parse as Nokogiri fragment for DOM comparison
          # Use XML fragment parser to avoid auto-inserted meta tags
          frag = Nokogiri::XML.fragment(html_string)

          # Apply post-parsing filtering for :normalize, :format, and :rendered preprocessing
          if %i[normalize format rendered].include?(preprocessing)
            normalize_html_style_script_comments(frag)
            if preprocessing == :rendered
              normalize_rendered_whitespace(frag, match_opts)
            end
            remove_whitespace_only_text_nodes(frag)
          end

          frag
        end

        # Normalize HTML comments within style and script tags for DataModel nodes
        def normalize_html_style_script_comments_datamodel(root)
          # Walk the tree to find style/script elements
          find_and_normalize_style_script(root)
        end

        def find_and_normalize_style_script(node)
          return unless node.respond_to?(:children)

          node.children.each do |child|
            next unless child.is_a?(Canon::Xml::Nodes::ElementNode)

            # If this is a style or script element, normalize its text content
            if %w[style script].include?(child.name.downcase)
              # Get text children and remove HTML comments from them
              child.children.each do |text_child|
                next unless text_child.is_a?(Canon::Xml::Nodes::TextNode)

                # Remove HTML comments from text content
                normalized = text_child.value.gsub(/<!--.*?-->/m, "").strip
                # Update the text value
                text_child.instance_variable_set(:@value, normalized)
              end
            end

            # Recursively process children
            find_and_normalize_style_script(child)
          end
        end

        # Detect HTML version from content
        #
        # @param content [String] HTML content
        # @return [Symbol] :html5 or :html4
        def detect_html_version(content)
          # Check for HTML5 doctype (case-insensitive)
          if content.match?(/<!DOCTYPE\s+html>/i)
            :html5
          # Check for HTML4 doctype patterns
          elsif content.match?(/<!DOCTYPE\s+HTML\s+PUBLIC/i)
            :html4
          else
            # Default to HTML5 for modern usage
            :html5
          end
        end

        # Detect HTML version from node
        #
        # @param node [Canon::Xml::Node, Nokogiri::XML::Node] HTML node
        # @return [Symbol] :html5 or :html4
        def detect_html_version_from_node(node)
          # Check node type for Nokogiri
          if node.is_a?(Nokogiri::HTML5::Document) ||
              node.is_a?(Nokogiri::HTML5::DocumentFragment)
            :html5
          elsif node.is_a?(Nokogiri::HTML4::Document) ||
              node.is_a?(Nokogiri::HTML4::DocumentFragment)
            :html4
          else
            # Default to HTML5 for Canon::Xml::Node and unknown types
            :html5
          end
        end

        # Serialize node to string for diff display
        # This ensures the displayed diff matches what was compared
        #
        # @param node [Canon::Xml::Node, Nokogiri::HTML::Document] Parsed node
        # @return [String] Serialized HTML string
        def serialize_for_display(node)
          # Use XmlNodeComparison's serializer for Canon::Xml::Node
          if node.is_a?(Canon::Xml::Node)
            XmlNodeComparison.serialize_node_to_xml(node)
          elsif node.respond_to?(:to_html)
            node.to_html
          elsif node.respond_to?(:to_xml)
            node.to_xml
          else
            node.to_s
          end
        end

        # Extract original HTML string from various input types
        # This preserves the original formatting without minification
        #
        # @param html [String, Nokogiri::Node, Canon::Xml::Node] Input HTML
        # @return [String] Original HTML string
        def extract_original_string(html)
          if html.is_a?(String)
            html
          elsif html.is_a?(Canon::Xml::Node)
            # Serialize Canon nodes to string
            Canon::Xml::DataModel.serialize(html)
          elsif html.respond_to?(:to_html)
            # Nokogiri nodes - use to_html to preserve formatting
            html.to_html
          elsif html.respond_to?(:to_s)
            html.to_s
          else
            raise Canon::Error,
                  "Unable to extract original string from: #{html.class}"
          end
        end

        # Normalize HTML comments within style and script tags
        # Also removes whitespace-only CDATA children that Nokogiri creates
        def normalize_html_style_script_comments(doc)
          doc.css("style, script").each do |element|
            # Remove HTML comments from style/script content
            # SAFE: This regex operates on already-parsed DOM element content,
            # not on raw user input. The non-greedy .*? correctly matches
            # comment boundaries. Any remaining <!-- would be literal text
            # (not a comment), which is safe in this context.
            # CodeQL false positive: see https://github.com/github/codeql/issues/XXXX
            normalized = element.content.gsub(/<!--.*?-->/m, "").strip

            if normalized.empty?
              # Remove all children (including whitespace-only CDATA nodes)
              element.children.remove
            else
              element.content = normalized
            end
          end
        end

        # Normalize whitespace in text nodes according to HTML rendering rules
        # In HTML rendering, sequences of whitespace (spaces, tabs, newlines)
        # collapse to a single space, except in elements where whitespace is
        # significant (pre, code, textarea, script, style)
        #
        # @param doc [Nokogiri::HTML::Document] Document to normalize
        # @param match_opts [Hash] Match options to respect during normalization
        # @param compare_profile [HtmlCompareProfile] Optional profile for whitespace rules
        def normalize_rendered_whitespace(doc, match_opts = {},
compare_profile = nil)
          # If text_content is :strict, don't normalize ANY text content
          # This allows users to explicitly request strict text matching
          return if match_opts[:text_content] == :strict

          # Elements where whitespace is significant - don't normalize
          # SINGLE SOURCE OF TRUTH: WhitespaceSensitivity.format_default_sensitive_elements
          # This ensures consistency between preprocessing and comparison logic
          # SINGLE SOURCE OF TRUTH: WhitespaceSensitivity.format_default_sensitive_elements
          # This ensures consistency between preprocessing and comparison logic
          preserve_whitespace = if compare_profile.is_a?(HtmlCompareProfile)
                                  # Profile handles HTML-specific whitespace rules
                                  # Get default list and filter by profile
                                  WhitespaceSensitivity
                                    .format_default_sensitive_elements(match_opts)
                                    .select do |elem|
                                      compare_profile.preserve_whitespace?(elem.to_s)
                                    end
                                    .map(&:to_s)
                                else
                                  # Use default list from WhitespaceSensitivity (single source of truth)
                                  WhitespaceSensitivity.format_default_sensitive_elements(match_opts).map(&:to_s)
                                end

          # Walk all text nodes
          doc.xpath(".//text()").each do |text_node|
            # Skip if this text node is inside a whitespace-preserving element
            # Check all ancestors, not just immediate parent
            # Whitespace preservation happens REGARDLESS of text_content setting
            parent = text_node.parent
            next if ancestor_preserves_whitespace?(parent, preserve_whitespace)

            # Collapse whitespace sequences (spaces, tabs, newlines) to single
            # space
            normalized = text_node.content.gsub(/\s+/, " ")

            # Trim leading/trailing whitespace if appropriate
            normalized = normalized.strip if should_trim_text_node?(text_node)

            text_node.content = normalized
          end
        end

        # Check if any ancestor of the given node preserves whitespace
        def ancestor_preserves_whitespace?(node, preserve_list)
          current = node
          while current.respond_to?(:name)
            return true if preserve_list.include?(current.name.downcase)

            # Stop at document root - documents don't have parents
            break if current.is_a?(Nokogiri::XML::Document)

            current = current.parent
          end
          false
        end

        # Determine if a text node should have leading/trailing whitespace
        # trimmed Text nodes at the start or end of their parent element should
        # be trimmed
        def should_trim_text_node?(text_node)
          parent = text_node.parent
          siblings = parent.children

          # Trim if text is the only child
          return true if siblings.length == 1

          # Trim if text is at the start or end of parent
          text_node == siblings.first || text_node == siblings.last
        end

        # Remove whitespace-only text nodes from the document
        # These are typically insignificant in HTML rendering (e.g., between
        # block elements)
        #
        # CRITICAL: Do NOT remove whitespace-only text nodes from whitespace-sensitive
        # elements like <pre>, <code>, <textarea>, <script>, <style>
        #
        # SINGLE SOURCE OF TRUTH: Uses WhitespaceSensitivity.format_default_sensitive_elements
        def remove_whitespace_only_text_nodes(doc)
          # Elements where whitespace is significant - don't remove whitespace-only nodes
          # SINGLE SOURCE OF TRUTH: WhitespaceSensitivity.format_default_sensitive_elements
          preserve_whitespace = WhitespaceSensitivity.format_default_sensitive_elements(format: :html).map(&:to_s)

          doc.xpath(".//text()").each do |text_node|
            # CRITICAL: Skip if this text node is inside a whitespace-preserving element
            parent = text_node.parent
            next if ancestor_preserves_whitespace?(parent, preserve_whitespace)

            # Remove if the text is only whitespace (after normalization)
            if text_node.content.strip.empty?
              text_node.remove
            end
          end
        end

        # Check if a node is an XML document (not HTML)
        # XML documents typically have XML processing instructions or are
        # instances of Nokogiri::XML::Document (not HTML variants)
        def is_xml_document?(node)
          # Check if it's a pure XML document (not HTML4/HTML5 which also
          # inherit from XML::Document)
          # Check both Document and DocumentFragment variants
          return false if node.is_a?(Nokogiri::HTML4::Document) ||
            node.is_a?(Nokogiri::HTML5::Document) ||
            node.is_a?(Nokogiri::HTML4::DocumentFragment) ||
            node.is_a?(Nokogiri::HTML5::DocumentFragment)

          # If it's an XML document, check for XML processing instruction
          if node.is_a?(Nokogiri::XML::Document) && node.children.any? do |child|
            child.is_a?(Nokogiri::XML::ProcessingInstruction) &&
                child.name == "xml"
          end
            # XML documents often start with <?xml ...?> processing instruction
            return true

            # Note: We don't blindly return true here because HTML documents
            # also inherit from XML::Document. We only return true if there's
            # an XML processing instruction above.
          end

          # Check if it's a fragment that contains XML processing instructions
          if node.respond_to?(:children) && node.children.any? do |child|
            child.is_a?(Nokogiri::XML::ProcessingInstruction) &&
                child.name == "xml"
          end
            return true
          end

          false
        end
      end
    end
  end
end
