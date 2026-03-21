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
    CYAN    = "\e[36m"
    GREEN   = "\e[32m"
    YELLOW  = "\e[33m"
    MAGENTA = "\e[35m"
    WHITE   = "\e[37m"
    GRAY    = "\e[90m"
    RED     = "\e[31m"
    HL = "─"
    VL = "│"
    TL = "┌"
    TR = "┐"
    BL = "└"
    BR = "┘"

    def self.header(title, color: CYAN)
      line = HL * 76
      "#{color}#{TL}#{line}#{TR}#{CLEAR}\n" \
        "#{color}#{VL}#{CLEAR}  #{BOLD}#{color}#{title}#{CLEAR}#{' ' * (76 - title.length)}#{color}#{VL}#{CLEAR}\n" \
        "#{color}#{BL}#{line}#{BR}#{CLEAR}"
    end

    def self.section(title, icon: "▶")
      puts
      puts "#{CYAN}#{VL}#{CLEAR}  #{BOLD}#{WHITE}#{icon} #{title}#{CLEAR}"
      puts "#{GRAY}#{VL}#{CLEAR}  #{DIM}#{'─' * (title.length + 3)}#{CLEAR}"
    end

    def self.result(label, ips, deviation:, faster_than: nil)
      status_color = if faster_than && faster_than > 1.0
                       GREEN
                     elsif faster_than && faster_than < 0.9
                       RED
                     else
                       WHITE
                     end

      bar = render_bar(ips, 20)
      speedup = if faster_than
                  "  #{GREEN}⚡#{faster_than.round(2)}x#{CLEAR}"
                else
                  ""
                end

      puts "  #{status_color}#{label}#{CLEAR}"
      puts "  #{bar}  #{status_color}#{format('%.1f', ips).rjust(8)}#{CLEAR} IPS  ±#{deviation.round(1)}%#{speedup}"
    end

    def self.comparison(label, base_ips, curr_ips, change:)
      color = if change > 0.05
                GREEN
              elsif change < -0.05
                RED
              else
                WHITE
              end

      change_str = format("%+.1f%%", change * 100)
      bar = render_bar(curr_ips, 16)

      base_str = format("%.1f", base_ips).rjust(8)
      curr_str = format("%.1f", curr_ips).rjust(8)

      puts
      puts "  #{BOLD}#{label}#{CLEAR}"
      puts "  #{bar}"
      puts "  #{GRAY}base:  #{base_str} IPS#{CLEAR}"
      puts "  #{color}curr:  #{curr_str} IPS#{CLEAR}"
      puts "  #{color}#{change_str}#{CLEAR}"
    end

    def self.new_benchmark(label)
      print "  #{YELLOW}◆#{CLEAR} #{label} ... "
      $stdout.flush
    end

    def self.speedup(factor, label)
      puts "  #{GREEN}⚡#{CLEAR} #{label} #{GREEN}#{factor.round(2)}x#{CLEAR} faster"
    end

    def self.hint(msg)
      puts "  #{DIM}#{msg}#{CLEAR}"
    end

    def self.reset_max_ips
      @max_ips = nil
    end

    def self.render_bar(ips, max_width)
      @max_ips ||= ips
      ratio = ips / @max_ips.to_f
      width = [(ratio * max_width).round, 1].max
      filled = [width, max_width].min
      empty = max_width - filled
      bar = ("█" * filled) + ("░" * empty)
      "#{DIM}#{bar}#{CLEAR}"
    end
  end

  REPO_ROOT = File.expand_path(File.join(__dir__, "..", ".."))

  # Benchmark configuration
  DEFAULT_RUN_TIME = 5
  DEFAULT_WARMUP = 2
  DEFAULT_ITEMS = 50

  # Test data generators
  module DataGenerator
    class << self
      # Generate XML with varying complexity
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
          child = build_xml_element(items / 2, depth - 1, prefix, with_attrs,
                                    "")
          "<#{prefix}root#{ns_attr}#{attrs}>#{child}</#{prefix}root>"
        end
      end

      # Generate HTML document
      def generate_html(items: DEFAULT_ITEMS, with_scripts: false,
with_tables: false)
        scripts = if with_scripts
                    <<-HTML
          <script type="text/javascript">
            //<!-- Some inline script
            function test() { return true; }
            //-->
          </script>
          <style>
            /* <!-- Inline styles --> */
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
          "<li class=\"item-#{i}\">List item #{i} with <strong>bold</strong> text</li>"
        end.join("\n              ")

        # Ensure nav has at least 2 items
        nav_item_count = [(items / 5), 2].max
        nav_items = items.times.first(nav_item_count).map do |i|
          "<li class=\"nav-#{i}\">Nav #{i}</li>"
        end.join("\n                ")

        <<-HTML
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
                <p>This is a paragraph with <em>emphasized</em> and <strong>strong</strong> text.</p>
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

      # Generate JSON data
      def generate_json(items: DEFAULT_ITEMS)
        data = {
          metadata: {
            version: "1.0",
            generated: Time.now.iso8601,
          },
          items: Array.new(items) do |i|
            {
              id: i,
              name: "Item #{i}",
              value: rand * 1000,
              tags: ["tag1", "tag2", "tag#{i % 10}"],
              nested: {
                level1: {
                  level2: {
                    data: "deeply nested value #{i}",
                  },
                },
              },
            }
          end,
        }
        JSON.generate(data)
      end

      # Generate YAML data
      def generate_yaml(items: DEFAULT_ITEMS)
        data = JSON.parse(generate_json(items: items))
        data.to_yaml
      end

      # Large XML document for SAX vs DOM comparison
      def generate_large_xml(items: 500)
        generate_xml(items: items, depth: 3, with_namespaces: true,
                     with_attributes: true)
      end

      # Deeply nested XML for tree traversal testing
      def generate_deep_xml(depth: 50)
        return "<leaf>content</leaf>" if depth <= 0

        "<nested level=\"#{depth}\">#{generate_deep_xml(depth - 1)}</nested>"
      end

      # XML with many attributes
      def generate_attributed_xml(attrs_per_element: 20, elements: 20)
        items = Array.new(elements) do |i|
          attrs = Array.new(attrs_per_element) do |j|
            "attr#{j}=\"value#{j}_#{i}\""
          end.join(" ")
          "<element #{attrs}>Content #{i}</element>"
        end.join
        "<root>#{items}</root>"
      end

      # HTML with mixed content (text + elements)
      def generate_mixed_html(items: DEFAULT_ITEMS)
        paragraphs = Array.new(items) do |i|
          "<p>This is paragraph <strong>#{i}</strong> with " \
            "<em>mixed</em> content and " \
            "<a href=\"http://example.com/#{i}\">links</a>.</p>"
        end.join("\n")
        generate_html(items: 5).sub("</main>", "#{paragraphs}</main>")
      end
    end
  end

  def initialize(run_time: nil, warmup: nil, items: nil, benchmark: nil)
    @run_time = run_time || DEFAULT_RUN_TIME
    @warmup = warmup || DEFAULT_WARMUP
    @items = items || DEFAULT_ITEMS
    @benchmark = benchmark
    @label = self.class.name.split("::")[1]
  end

  # Run the specified benchmark(s)
  def run_benchmarks
    Term.reset_max_ips
    puts Term.header("Canon Performance Benchmarks", color: Term::CYAN)
    puts "#{Term::DIM}ruby #{RUBY_VERSION}#{Term::CLEAR}"
    puts

    results = if @benchmark
                send(:"benchmark_#{@benchmark}")
              else
                run_all_benchmarks
              end

    puts
    puts Term.header("Summary", color: Term::MAGENTA)
    puts

    results.each do |label, metrics|
      ips = (metrics[:lower] + metrics[:upper]) / 2.0
      deviation = ((metrics[:upper] - metrics[:lower]) / metrics[:upper] * 100).round(1)
      Term.result(label, ips, deviation: deviation)
    end

    puts
    results
  end

  private

  def run_all_benchmarks
    results = {}

    # XML Parsing benchmarks
    results.merge!(benchmark_xml_parsing_dom)
    results.merge!(benchmark_xml_parsing_sax)
    results.merge!(benchmark_xml_parsing_large)

    # HTML Parsing benchmarks
    results.merge!(benchmark_html_parsing)
    results.merge!(benchmark_html_parsing_complex)

    # Comparison benchmarks
    results.merge!(benchmark_xml_comparison)
    results.merge!(benchmark_html_comparison)

    # Formatting/Canonicalization benchmarks
    results.merge!(benchmark_xml_c14n)
    results.merge!(benchmark_json_formatting)
    results.merge!(benchmark_yaml_formatting)

    results
  end

  # ============================================================
  # XML PARSING BENCHMARKS
  # ============================================================

  def benchmark_xml_parsing_dom
    Term.section("XML Parsing", icon: "📄")
    xml = DataGenerator.generate_xml(items: @items)
    Term.new_benchmark("DOM parser (simple)")
    result = run_ips_benchmark("xml_parse_dom_simple") { Canon::Xml::DataModel.from_xml(xml) }
    display_ips_result(result)
    result
  end

  def benchmark_xml_parsing_sax
    return {} unless SAX_AVAILABLE

    xml = DataGenerator.generate_xml(items: @items)
    Term.new_benchmark("SAX parser (simple)")
    result = run_ips_benchmark("xml_parse_sax_simple") { Canon::Xml::SaxBuilder.parse(xml) }
    display_ips_result(result)

    # Show comparison if both DOM and SAX were run
    result
  end

  def benchmark_xml_parsing_large
    Term.section("XML Parsing (Large Document)", icon: "📋")
    xml = DataGenerator.generate_large_xml(items: @items * 5)
    results = {}

    Term.new_benchmark("DOM parser (large)")
    results["xml_parse_dom_large"] = time_with_error do
      Canon::Xml::DataModel.from_xml(xml)
    end
    display_time_result("xml_parse_dom_large", results["xml_parse_dom_large"])

    if SAX_AVAILABLE
      Term.new_benchmark("SAX parser (large)")
      results["xml_parse_sax_large"] = time_with_error { Canon::Xml::SaxBuilder.parse(xml) }
      display_time_result("xml_parse_sax_large", results["xml_parse_sax_large"])

      # Show speedup if SAX is faster
      if results["xml_parse_dom_large"] && results["xml_parse_sax_large"]
        dom_ips = results["xml_parse_dom_large"][:upper]
        sax_ips = results["xml_parse_sax_large"][:upper]
        speedup = sax_ips / dom_ips
        if speedup > 1.0
          Term.speedup(speedup, "SAX vs DOM:")
          Term.hint("(#{format('%.1f', dom_ips)} IPS → #{format('%.1f', sax_ips)} IPS)")
        else
          Term.hint("(SAX: #{format('%.1f', sax_ips)} IPS, DOM: #{format('%.1f', dom_ips)} IPS)")
        end
      end
    end
    results
  end

  # ============================================================
  # HTML PARSING BENCHMARKS
  # ============================================================

  def benchmark_html_parsing
    Term.section("HTML Parsing", icon: "🌐")
    html = DataGenerator.generate_html(items: @items)
    Term.new_benchmark("Simple HTML")
    result = run_ips_benchmark("html_parse_simple") { Canon.parse_html(html) }
    display_ips_result(result)
    result
  end

  def benchmark_html_parsing_complex
    html = DataGenerator.generate_html(items: @items, with_scripts: true,
                                       with_tables: true)
    Term.new_benchmark("Complex HTML (scripts, tables)")
    result = run_ips_benchmark("html_parse_complex") { Canon.parse_html(html) }
    display_ips_result(result)
    result
  end

  # ============================================================
  # COMPARISON BENCHMARKS
  # ============================================================

  def benchmark_xml_comparison
    Term.section("XML Comparison", icon: "⚖️")
    xml1 = DataGenerator.generate_xml(items: @items)
    xml2 = DataGenerator.generate_xml(items: @items)
    xml3 = DataGenerator.generate_xml(items: @items, with_namespaces: true)

    results = {}
    Term.new_benchmark("Identical XML")
    results.merge!(run_ips_benchmark("xml_compare_identical") do
      Canon::Comparison.equivalent?(xml1, xml1, format: :xml)
    end)
    display_ips_result(results)

    Term.new_benchmark("Similar XML")
    results.merge!(run_ips_benchmark("xml_compare_similar") do
      Canon::Comparison.equivalent?(xml1, xml2, format: :xml)
    end)
    display_ips_result(results)

    Term.new_benchmark("Different XML (namespaces)")
    results.merge!(run_ips_benchmark("xml_compare_different") do
      Canon::Comparison.equivalent?(xml1, xml3, format: :xml)
    end)
    display_ips_result(results)
    results
  end

  def benchmark_html_comparison
    Term.section("HTML Comparison", icon: "🔍")
    html1 = DataGenerator.generate_html(items: @items)
    html2 = DataGenerator.generate_html(items: @items)
    html3 = DataGenerator.generate_html(items: @items, with_tables: true)

    results = {}
    Term.new_benchmark("Identical HTML")
    results.merge!(run_ips_benchmark("html_compare_identical") do
      Canon::Comparison.equivalent?(html1, html1, format: :html)
    end)
    display_ips_result(results)

    Term.new_benchmark("Similar HTML")
    results.merge!(run_ips_benchmark("html_compare_similar") do
      Canon::Comparison.equivalent?(html1, html2, format: :html)
    end)
    display_ips_result(results)

    Term.new_benchmark("Different HTML (tables)")
    results.merge!(run_ips_benchmark("html_compare_different") do
      Canon::Comparison.equivalent?(html1, html3, format: :html)
    end)
    display_ips_result(results)
    results
  end

  # ============================================================
  # FORMATTING/CANONICALIZATION BENCHMARKS
  # ============================================================

  def benchmark_xml_c14n
    Term.section("XML Canonicalization", icon: "✨")
    xml = DataGenerator.generate_xml(items: @items, with_namespaces: true)
    Term.new_benchmark("XML C14N format")
    result = run_ips_benchmark("xml_c14n_format") { Canon.format_xml(xml) }
    display_ips_result(result)
    result
  end

  def benchmark_json_formatting
    Term.section("JSON Formatting", icon: "{}")
    json = DataGenerator.generate_json(items: @items)
    data = JSON.parse(json)
    Term.new_benchmark("JSON format")
    result = run_ips_benchmark("json_format") { Canon.format_json(data) }
    display_ips_result(result)
    result
  end

  def benchmark_yaml_formatting
    Term.section("YAML Formatting", icon: "📝")
    yaml = DataGenerator.generate_yaml(items: @items)
    data = YAML.safe_load(yaml, permitted_classes: [Time])
    Term.new_benchmark("YAML format")
    result = run_ips_benchmark("yaml_format") { Canon.format_yaml(data) }
    display_ips_result(result)
    result
  end

  # ============================================================
  # BENCHMARK INFRASTRUCTURE
  # ============================================================

  def run_ips_benchmark(label, &block)
    job = Benchmark::IPS::Job.new
    job.config(time: @run_time, warmup: @warmup)
    job.report(label, &block)
    job.run

    entry = job.full_report.entries.first
    samples = entry.stats.samples

    raise "No samples collected for #{label}" if samples.empty?

    mean = samples.sum.to_f / samples.size
    variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
    std_dev = Math.sqrt(variance)
    error_margin = std_dev / mean

    error_percentage = error_margin.round(4)
    lower = mean.round(4) * (1 - error_percentage)
    upper = mean.round(4) * (1 + error_percentage)

    { label => { lower: lower, upper: upper } }
  end

  def display_ips_result(results)
    return if results.nil? || results.empty?

    results.each do |label, metrics|
      ips = (metrics[:lower] + metrics[:upper]) / 2.0
      deviation = ((metrics[:upper] - metrics[:lower]) / metrics[:upper] * 100).round(1)
      Term.result(label, ips, deviation: deviation)
    end
  end

  def display_time_result(label, metrics)
    return if metrics.nil?

    ips = metrics[:upper]
    Term.result(label, ips, deviation: 5.0)
  end

  def time_with_error
    # For longer-running operations, use fewer iterations but measure accurately
    times = []
    iterations = 5

    iterations.times do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      times << (finish - start)
    end

    mean = times.sum / times.size
    variance = times.sum { |t| (t - mean)**2 } / (times.size - 1)
    std_dev = Math.sqrt(variance)
    std_dev / mean

    # Convert to IPS (iterations per second)
    lower_ips = (1.0 / (mean + std_dev)).round(4)
    upper_ips = (1.0 / (mean - std_dev)).round(4)

    { lower: lower_ips, upper: upper_ips }
  end
end
