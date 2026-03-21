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
    if @benchmark
      send(:"benchmark_#{@benchmark}")
    else
      run_all_benchmarks
    end
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
    xml = DataGenerator.generate_xml(items: @items)
    run_ips_benchmark("xml_parse_dom_simple") { Canon::Xml::DataModel.from_xml(xml) }
  end

  def benchmark_xml_parsing_sax
    return {} unless SAX_AVAILABLE

    xml = DataGenerator.generate_xml(items: @items)
    run_ips_benchmark("xml_parse_sax_simple") { Canon::Xml::SaxBuilder.parse(xml) }
  end

  def benchmark_xml_parsing_large
    xml = DataGenerator.generate_large_xml(items: @items * 5)
    results = {
      "xml_parse_dom_large" => time_with_error do
        Canon::Xml::DataModel.from_xml(xml)
      end,
    }
    if SAX_AVAILABLE
      results["xml_parse_sax_large"] = time_with_error { Canon::Xml::SaxBuilder.parse(xml) }
    end
    results
  end

  # ============================================================
  # HTML PARSING BENCHMARKS
  # ============================================================

  def benchmark_html_parsing
    html = DataGenerator.generate_html(items: @items)
    run_ips_benchmark("html_parse_simple") { Canon.parse_html(html) }
  end

  def benchmark_html_parsing_complex
    html = DataGenerator.generate_html(items: @items, with_scripts: true,
                                       with_tables: true)
    run_ips_benchmark("html_parse_complex") { Canon.parse_html(html) }
  end

  # ============================================================
  # COMPARISON BENCHMARKS
  # ============================================================

  def benchmark_xml_comparison
    xml1 = DataGenerator.generate_xml(items: @items)
    xml2 = DataGenerator.generate_xml(items: @items)
    xml3 = DataGenerator.generate_xml(items: @items, with_namespaces: true)

    results = {}
    results.merge!(run_ips_benchmark("xml_compare_identical") do
      Canon::Comparison.equivalent?(xml1, xml1, format: :xml)
    end)
    results.merge!(run_ips_benchmark("xml_compare_similar") do
      Canon::Comparison.equivalent?(xml1, xml2, format: :xml)
    end)
    results.merge!(run_ips_benchmark("xml_compare_different") do
      Canon::Comparison.equivalent?(xml1, xml3, format: :xml)
    end)
    results
  end

  def benchmark_html_comparison
    html1 = DataGenerator.generate_html(items: @items)
    html2 = DataGenerator.generate_html(items: @items)
    html3 = DataGenerator.generate_html(items: @items, with_tables: true)

    results = {}
    results.merge!(run_ips_benchmark("html_compare_identical") do
      Canon::Comparison.equivalent?(html1, html1, format: :html)
    end)
    results.merge!(run_ips_benchmark("html_compare_similar") do
      Canon::Comparison.equivalent?(html1, html2, format: :html)
    end)
    results.merge!(run_ips_benchmark("html_compare_different") do
      Canon::Comparison.equivalent?(html1, html3, format: :html)
    end)
    results
  end

  # ============================================================
  # FORMATTING/CANONICALIZATION BENCHMARKS
  # ============================================================

  def benchmark_xml_c14n
    xml = DataGenerator.generate_xml(items: @items, with_namespaces: true)

    run_ips_benchmark("xml_c14n_format") { Canon.format_xml(xml) }
  end

  def benchmark_json_formatting
    json = DataGenerator.generate_json(items: @items)
    data = JSON.parse(json)

    run_ips_benchmark("json_format") { Canon.format_json(data) }
  end

  def benchmark_yaml_formatting
    yaml = DataGenerator.generate_yaml(items: @items)
    data = YAML.safe_load(yaml, permitted_classes: [Time])

    run_ips_benchmark("yaml_format") { Canon.format_yaml(data) }
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
