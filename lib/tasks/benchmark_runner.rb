# frozen_string_literal: true

require "benchmark/ips"

# Ensure lib/ is on the load path regardless of tmp location
lib_path = File.expand_path(File.join(__dir__, "..", "..", "lib"))
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

require "canon"

# Try to load SaxBuilder if available (new in feat/xml-performance branch)
begin
  require "canon/xml/sax_builder"
  SAX_AVAILABLE = true
rescue LoadError
  SAX_AVAILABLE = false
end

class BenchmarkRunner
  # Pretty terminal formatting for benchmark output
  module Term
    CLEAR   = "\e[0m"
    BOLD    = "\e[1m"
    DIM     = "\e[2m"
    BLACK   = "\e[30m"
    RED     = "\e[31m"
    GREEN   = "\e[32m"
    YELLOW  = "\e[33m"
    BLUE    = "\e[34m"
    MAGENTA = "\e[35m"
    CYAN    = "\e[36m"
    WHITE   = "\e[37m"
    BG_RED  = "\e[41m"
    BG_GREEN = "\e[42m"

    # Box-drawing
    HL = "─"
    VL = "│"
    TL = "┌"
    TR = "┐"
    BL = "└"
    BR = "┘"
    TT = "┬"
    BT = "┴"
    LT = "├"
    RT = "┤"
    CROSS = "┼"

    # Spinner frames
    SPINNER = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze

    @spinner_idx = 0

    def self.spin
      print "\b#{SPINNER[@spinner_idx % SPINNER.length]} "
      $stdout.flush
      @spinner_idx += 1
    end

    def self.clear_spinner
      print "\b \b"
      $stdout.flush
    end

    def self.ok
      puts " #{GREEN}✓#{CLEAR}"
    end

    def self.fail(msg = nil)
      puts " #{RED}✗#{CLEAR}"
      puts "  #{RED}#{msg}#{CLEAR}" if msg
    end

    def self.info(msg)
      puts "  #{DIM}#{msg}#{CLEAR}"
    end

    def self.hint(msg)
      puts "  #{CYAN}→#{CLEAR} #{DIM}#{msg}#{CLEAR}"
    end

    def self.sep(char: HL, width: 78)
      puts "#{DIM}#{char * width}#{CLEAR}"
    end

    def self.header(title, color: CYAN)
      width = 78
      line = HL * width
      puts
      puts "#{color}#{TL}#{line}#{TR}#{CLEAR}"
      puts "#{color}#{VL}#{CLEAR}  #{BOLD}#{color}#{title}#{CLEAR}#{' ' * (width - title.length - 4)}#{color}#{VL}#{CLEAR}"
      puts "#{color}#{BL}#{line}#{BR}#{CLEAR}"
    end

    def self.env_info(ruby_version, platform)
      puts
      puts "  #{DIM}Environment:#{CLEAR}"
      puts "  #{VL}  Ruby #{ruby_version} on #{platform}#{' ' * (60 - ruby_version.length - platform.length)}#{VL}"
      puts "  #{DIM}#{BL}#{HL * 76}#{BR}#{CLEAR}"
      puts
    end

    # Category section with description
    def self.category(title, icon:, description:, failure_means:, compare_against: nil)
      puts
      puts "#{CYAN}#{VL}#{CLEAR}  #{BOLD}#{MAGENTA}#{icon} #{title}#{CLEAR}"
      puts

      # Description
      puts "  #{DIM}#{description}#{CLEAR}"
      puts

      # What we compare
      if compare_against
        puts "  #{CYAN}Comparing against:#{CLEAR} #{compare_against}"
        puts
      end

      # What failure means
      puts "  #{YELLOW}⚠️  Failure means:#{CLEAR} #{failure_means}"
      puts

      sep(width: 76)
      puts
    end

    # Results table for a category
    def self.table_header
      puts "  #{BOLD}#{'%-35s'} #{'%10s'} #{'%8s'} #{'%s'}#{CLEAR}"
      puts "  Test                                       IPS       ±% Speedup"
      sep(char: "─", width: 76)
    end

    def self.table_row(label, ips, deviation, speedup: nil, is_best: false)
      speedup_str = speedup ? "  ⚡#{speedup.round(2)}x" : ""
      label_str = is_best ? "#{GREEN}#{label}#{CLEAR}" : label
      bar = render_bar(ips)

      puts "  #{label_str}"
      puts "  #{DIM}#{bar}#{CLEAR}  #{format('%10.1f', ips)}  #{format('%6.1f%%', deviation)}#{speedup_str}"
      puts
    end

    def self.table_footer
      sep(char: "─", width: 76)
      puts
    end

    def self.speedup_badge(factor, label)
      puts "  #{GREEN}⚡ #{label}#{CLEAR}"
      puts "  #{GREEN}   #{factor.round(2)}x faster#{CLEAR}"
    end

    def self.reset_max_ips
      @max_ips = nil
    end

    def self.set_max_ips(val)
      @max_ips = val
    end

    def self.render_bar(ips, max_width: 20)
      @max_ips ||= ips
      ratio = ips / @max_ips.to_f
      width = [(ratio * max_width).round, 1].max
      filled = [width, max_width].min
      empty = max_width - filled
      ("█" * filled) + ("░" * empty)
    end

    # Summary card
    def self.summary_card(results)
      puts
      sep(width: 78)
      puts
      puts "  #{BOLD}#{MAGENTA}SUMMARY#{CLEAR}"
      puts

      total = results.length

      results.each do |r|
        # For standalone runs, all results are shown as "current" without comparison
        ips_str = r[:ips] ? format("%10.1f IPS", r[:ips]) : ""
        puts "  #{DIM}◆#{CLEAR} #{format('%-35s', r[:label])} #{ips_str}"
      end

      puts
      puts "  #{DIM}#{total} benchmarks completed#{CLEAR}"
      puts
    end
  end

  REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))

  # Benchmark configuration
  DEFAULT_RUN_TIME = 5
  DEFAULT_WARMUP = 2
  DEFAULT_ITEMS = 50

  # Category definitions with descriptions
  CATEGORIES = {
    xml_parsing: {
      name: "XML Parsing",
      icon: "📄",
      description: "XML parsing performance tests. Measures how quickly we can convert XML strings into internal data structures.",
      failure_means: "Slow XML parsing impacts all downstream operations. A regression here means users will experience delays when processing XML documents.",
      compare_against: "Previous branch (main). We test both DOM parsing and SAX parsing.",
    },
    html_parsing: {
      name: "HTML Parsing",
      icon: "🌐",
      description: "HTML parsing for web scraping and document processing. Tests both simple and complex HTML with scripts/styles.",
      failure_means: "Slow HTML parsing affects web scraping workflows. Complex HTML tests include scripts and tables.",
      compare_against: "Previous branch (main).",
    },
    xml_comparison: {
      name: "XML Comparison",
      icon: "⚖️",
      description: "XML semantic comparison. Tests three scenarios: identical documents, similar documents, and documents with different namespaces.",
      failure_means: "Slow comparison means CI/CD pipelines and test suites will take longer. Critical for regression testing workflows.",
      compare_against: "Previous branch (main). Identical should be fastest, then similar, then different.",
    },
    html_comparison: {
      name: "HTML Comparison",
      icon: "🔍",
      description: "HTML semantic comparison. Tests HTML document equivalence including structural normalization.",
      failure_means: "Slow HTML comparison affects automated testing of web content. Critical for validation workflows.",
      compare_against: "Previous branch (main).",
    },
    formatting: {
      name: "Format Canonicalization",
      icon: "✨",
      description: "Format canonicalization (XML C14N, JSON, YAML). Tests how quickly we can produce canonical output from data structures.",
      failure_means: "Slow formatting affects serialization performance. C14N is critical for digital signatures and XML canonicalization.",
      compare_against: "Previous branch (main).",
    },
  }.freeze

  # Test definitions
  BENCHMARKS = {
    xml_parsing: [
      { name: "DOM (simple)", method: :xml_parse_dom_simple, desc: "Standard DOM parsing" },
      { name: "SAX (simple)", method: :xml_parse_sax_simple, desc: "Streaming SAX parsing" },
      { name: "DOM (large)", method: :xml_parse_dom_large, desc: "Large document DOM" },
      { name: "SAX (large)", method: :xml_parse_sax_large, desc: "Large document SAX" },
    ],
    html_parsing: [
      { name: "Simple HTML", method: :html_parse_simple, desc: "Basic HTML" },
      { name: "Complex HTML", method: :html_parse_complex, desc: "HTML with scripts/tables" },
    ],
    xml_comparison: [
      { name: "Identical XML", method: :xml_compare_identical, desc: "Same documents" },
      { name: "Similar XML", method: :xml_compare_similar, desc: "Slightly different" },
      { name: "Different XML", method: :xml_compare_different, desc: "Different namespaces" },
    ],
    html_comparison: [
      { name: "Identical HTML", method: :html_compare_identical, desc: "Same HTML" },
      { name: "Similar HTML", method: :html_compare_similar, desc: "Slightly different" },
      { name: "Different HTML", method: :html_compare_different, desc: "Different structure" },
    ],
    formatting: [
      { name: "XML C14N", method: :xml_c14n_format, desc: "Canonical XML" },
      { name: "JSON", method: :json_format, desc: "JSON formatting" },
      { name: "YAML", method: :yaml_format, desc: "YAML formatting" },
    ],
  }.freeze

  # Test data generators
  module DataGenerator
    class << self
      def generate_xml(items: DEFAULT_ITEMS, depth: 1, with_namespaces: false,
                       with_attributes: true)
        ns = with_namespaces ? 'xmlns:ns="http://example.org"' : ""
        prefix = with_namespaces ? "ns:" : ""

        build_xml_element(items, depth, prefix, with_attributes, ns)
      end

      def build_xml_element(items, depth, prefix, with_attrs, ns_decl)
        attrs = with_attrs ? " id=\"#{rand(1000)}\" status=\"active\"" : ""
        ns_attr = ns_decl.empty? ? "" : " #{ns_decl}"

        if depth <= 1
          children = Array.new(items) do |i|
            inner_attrs = with_attrs ? " index=\"#{i}\"" : ""
            "<#{prefix}item#{inner_attrs}>Item #{i} content with some text</#{prefix}item>"
          end.join
          "<#{prefix}root#{ns_attr}#{attrs}>#{children}</#{prefix}root>"
        else
          child = build_xml_element(items / 2, depth - 1, prefix, with_attrs, "")
          "<#{prefix}root#{ns_attr}#{attrs}>#{child}</#{prefix}root>"
        end
      end

      def generate_html(items: DEFAULT_ITEMS, with_scripts: false,
                        with_tables: false)
        scripts = if with_scripts
                    <<~HTML
                      <script type="text/javascript">
                        // Some inline script
                        function test() { return true; }
                      </script>
                      <style>
                        body { margin: 0; }
                      </style>
                    HTML
                  else
                    ""
                  end

        tables = if with_tables
                   rows = Array.new(items) do |i|
                     "<tr><td>Cell #{i}A</td><td>Cell #{i}B</td></tr>"
                   end.join
                   "<table>#{rows}</table>"
                 else
                   ""
                 end

        list_items = Array.new(items) do |i|
          "<li class=\"item-#{i}\">List item #{i} with bold text</li>"
        end.join("\n              ")

        nav_item_count = [(items / 5), 2].max
        nav_items = items.times.first(nav_item_count).map do |i|
          "<li class=\"nav-#{i}\">Nav #{i}</li>"
        end.join("\n                ")

        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <title>Benchmark Document</title>
            #{scripts}
          </head>
          <body>
            <header>
              <h1>Benchmark Test Document</h1>
              <nav>
                <ul>
                #{nav_items}
                </ul>
              </nav>
            </header>
            <main>
              <section id="content">
                <p>This is a paragraph with emphasized and strong text.</p>
                <ul>
                #{list_items}
                </ul>
                #{tables}
              </section>
            </main>
            <footer>
              <p>Copyright 2024</p>
            </footer>
          </body>
          </html>
        HTML
      end

      def generate_json(items: DEFAULT_ITEMS)
        data = {
          metadata: { version: "1.0", generated: Time.now.iso8601 },
          items: Array.new(items) do |i|
            {
              id: i,
              name: "Item #{i}",
              value: rand * 1000,
              tags: ["tag1", "tag2", "tag#{i % 10}"],
              nested: {
                level1: { level2: { data: "deeply nested value #{i}" } },
              },
            }
          end,
        }
        JSON.generate(data)
      end

      def generate_yaml(items: DEFAULT_ITEMS)
        data = JSON.parse(generate_json(items: items))
        data.to_yaml
      end

      def generate_large_xml(items: 500)
        generate_xml(items: items, depth: 3, with_namespaces: true,
                     with_attributes: true)
      end
    end
  end

  def initialize(run_time: nil, warmup: nil, items: nil, benchmark: nil)
    @run_time = run_time || DEFAULT_RUN_TIME
    @warmup = warmup || DEFAULT_WARMUP
    @items = items || DEFAULT_ITEMS
    @benchmark = benchmark
    @results = {}
    @env_shown = false
    @all_results = []
  end

  def run_benchmarks
    Term.reset_max_ips

    # Header
    Term.header("Canon Performance Benchmarks", color: Term::CYAN)

    unless @env_shown
      Term.env_info(RUBY_VERSION, RUBY_PLATFORM)
      @env_shown = true
    end

    # Run all categories
    BENCHMARKS.each do |category, tests|
      run_category(category, tests)
    end

    # Summary
    print_summary

    @results
  end

  private

  def run_category(category, tests)
    config = CATEGORIES[category]
    Term.category(
      config[:name],
      icon: config[:icon],
      description: config[:description],
      failure_means: config[:failure_means],
      compare_against: config[:compare_against],
    )

    Term.table_header

    # Run each test in category
    category_results = []
    max_ips = 0

    tests.each do |test|
      next if test[:method] == :xml_parse_sax_simple && !SAX_AVAILABLE
      next if test[:method] == :xml_parse_sax_large && !SAX_AVAILABLE

      # Redirect stdout during benchmark to suppress benchmark-ips output
      original_stdout = $stdout
      $stdout = StringIO.new

      result = run_single_test(test[:method])
      ips = (result[:lower] + result[:upper]) / 2.0
      max_ips = ips if ips > max_ips
      category_results << { name: test[:name], result: result }

      # Restore stdout
      $stdout = original_stdout
    end

    # Reset for relative bars within category
    Term.set_max_ips(max_ips)

    # Print results with relative bars
    category_results.each do |r|
      is_best = r[:result][:upper] >= max_ips
      Term.table_row(r[:name], (r[:result][:lower] + r[:result][:upper]) / 2.0,
                     calculate_deviation(r[:result]), is_best: is_best)
      @all_results << { label: "#{config[:name]}: #{r[:name]}", ips: (r[:result][:lower] + r[:result][:upper]) / 2.0 }
    end

    Term.table_footer

    # SAX vs DOM comparison for XML parsing
    if category == :xml_parsing && SAX_AVAILABLE
      sax = category_results.find { |r| r[:name].include?("SAX") && r[:name].include?("large") }
      dom = category_results.find { |r| r[:name].include?("DOM") && r[:name].include?("large") }

      if sax && dom
        sax_ips = (sax[:result][:lower] + sax[:result][:upper]) / 2.0
        dom_ips = (dom[:result][:lower] + dom[:result][:upper]) / 2.0
        speedup = sax_ips / dom_ips

        if speedup > 1.0
          Term.speedup_badge(speedup, "SAX is faster than DOM for large documents")
        else
          Term.hint("DOM is #{format('%.2f', 1 / speedup)}x faster than SAX for large documents")
        end
      end
    end

    puts
  end

  def run_single_test(method)
    case method
    when :xml_parse_dom_simple
      xml = DataGenerator.generate_xml(items: @items)
      measure { Canon::Xml::DataModel.from_xml(xml) }
    when :xml_parse_sax_simple
      xml = DataGenerator.generate_xml(items: @items)
      measure { Canon::Xml::SaxBuilder.parse(xml) }
    when :xml_parse_dom_large
      xml = DataGenerator.generate_large_xml(items: @items * 5)
      measure_time { Canon::Xml::DataModel.from_xml(xml) }
    when :xml_parse_sax_large
      xml = DataGenerator.generate_large_xml(items: @items * 5)
      measure_time { Canon::Xml::SaxBuilder.parse(xml) }
    when :html_parse_simple
      html = DataGenerator.generate_html(items: @items)
      measure { Canon.parse_html(html) }
    when :html_parse_complex
      html = DataGenerator.generate_html(items: @items, with_scripts: true, with_tables: true)
      measure { Canon.parse_html(html) }
    when :xml_compare_identical
      xml = DataGenerator.generate_xml(items: @items)
      measure { Canon::Comparison.equivalent?(xml, xml, format: :xml) }
    when :xml_compare_similar
      xml1 = DataGenerator.generate_xml(items: @items)
      xml2 = DataGenerator.generate_xml(items: @items)
      measure { Canon::Comparison.equivalent?(xml1, xml2, format: :xml) }
    when :xml_compare_different
      xml1 = DataGenerator.generate_xml(items: @items)
      xml2 = DataGenerator.generate_xml(items: @items, with_namespaces: true)
      measure { Canon::Comparison.equivalent?(xml1, xml2, format: :xml) }
    when :html_compare_identical
      html = DataGenerator.generate_html(items: @items)
      measure { Canon::Comparison.equivalent?(html, html, format: :html) }
    when :html_compare_similar
      html1 = DataGenerator.generate_html(items: @items)
      html2 = DataGenerator.generate_html(items: @items)
      measure { Canon::Comparison.equivalent?(html1, html2, format: :html) }
    when :html_compare_different
      html1 = DataGenerator.generate_html(items: @items)
      html2 = DataGenerator.generate_html(items: @items, with_tables: true)
      measure { Canon::Comparison.equivalent?(html1, html2, format: :html) }
    when :xml_c14n_format
      xml = DataGenerator.generate_xml(items: @items, with_namespaces: true)
      measure { Canon.format_xml(xml) }
    when :json_format
      json = DataGenerator.generate_json(items: @items)
      data = JSON.parse(json)
      measure { Canon.format_json(data) }
    when :yaml_format
      yaml = DataGenerator.generate_yaml(items: @items)
      data = YAML.safe_load(yaml, permitted_classes: [Time])
      measure { Canon.format_yaml(data) }
    else
      raise "Unknown benchmark: #{method}"
    end
  end

  def measure(&block)
    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: @warmup)
    job.report("test", &block)
    job.run

    entry = job.full_report.entries.first
    samples = entry.stats.samples

    return { lower: 0, upper: 0 } if samples.empty?

    mean = samples.sum.to_f / samples.size
    variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
    std_dev = Math.sqrt(variance)
    error_margin = std_dev / mean
    error_pct = error_margin.round(4)

    { lower: mean.round(4) * (1 - error_pct), upper: mean.round(4) * (1 + error_pct) }
  end

  def measure_time
    times = []
    iterations = 5

    iterations.times do
      start_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      finish_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      times << (finish_t - start_t)
    end

    mean = times.sum / times.size
    variance = times.sum { |t| (t - mean)**2 } / (times.size - 1)
    std_dev = Math.sqrt(variance)

    # Ensure positive values for IPS calculation
    # Use conservative estimate: mean + std_dev for lower bound, mean for upper
    lower_time = [mean - std_dev, mean * 0.5].max
    lower_ips = (1.0 / (lower_time * 1.5)).round(4)
    upper_ips = (1.0 / mean).round(4)

    # Sanity check: if mean is very small, we might have measurement noise
    if mean < 0.001 # Less than 1ms
      # For fast operations, estimate more conservatively
      upper_ips = (1.0 / mean).round(4)
      lower_ips = (upper_ips * 0.8).round(4)
    end

    { lower: lower_ips, upper: upper_ips }
  end

  def calculate_deviation(metrics)
    ((metrics[:upper] - metrics[:lower]) / metrics[:upper] * 100).round(1)
  end

  def print_summary
    Term.summary_card(@all_results)
  end
end
