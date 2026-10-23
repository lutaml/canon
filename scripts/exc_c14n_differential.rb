require_relative "../lib/canon"
require "nokogiri"

# Diagnostic: the ExclusiveC14n differential against nokogiri/libxml2
# over the vendored merlin-c14n-two corpus. NOT a battery gate — see
# TODO.sota/05 for the residual map (the extended-predicate subset
# semantics and the default-ns law disposition).
CORPUS = File.join(__dir__, "../spec/fixtures/corpora/exc-c14n")
results = Hash.new { |h, k| h[k] = [] }

Dir.glob("#{CORPUS}/*.xml").each do |input|
  base = File.basename(input, ".xml")
  xpath_file = "#{CORPUS}/#{base}.xpath"
  ns_file = "#{CORPUS}/#{base}.ns"
  ns_list = File.exist?(ns_file) ? File.read(ns_file).split : []

  doc = Nokogiri::XML(File.read(input))
  # compact product: strip whitespace-only text nodes (canon's C14N
  # lane parses noblanks; the compact bytes are the product)
  doc.xpath("//text()").select { |t| t.content.strip.empty? }.each(&:remove)

  if File.exist?(xpath_file)
    # subset case: canon evaluates its own XPath marking
    mine = Canon::Xml::ExclusiveC14n.canonicalize(
      File.read(input), xpath: File.read(xpath_file).strip,
                        inclusive_ns_prefixes: ns_list
    )
    # oracle: subtree selection — evaluate the same selector, take
    # the topmost matched element(s), canonicalize exclusive with
    # the same prefix list
    xp = Nokogiri::XML(File.read(xpath_file))
    prefix_map = xp.root.namespaces.transform_values { |v| v.to_s.sub(%r{^xmlns(?::)?}, "") }
    expr = xp.root.text.strip
    matched = doc.xpath(expr, prefix_map).grep(Nokogiri::XML::Element)
    tops = matched.reject { |n| n.ancestors.any? { |a| a.element? && matched.include?(a) } }
    ref = tops.map do |t|
      t.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, ns_list, false)
    end.join
  else
    mine = Canon::Xml::ExclusiveC14n.canonicalize(
      File.read(input), inclusive_ns_prefixes: ns_list
    )
    ref = doc.root.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0, ns_list, false)
  end

  if mine == ref
    results[:match] << base
  elsif base == "merlin-c14n-two-10"
    File.write("/tmp/exc_ref.txt", ref)
    File.write("/tmp/exc_mine.txt", mine)
  elsif mine.include?("xmlns=") == ref.include?("xmlns=") &&
      mine.gsub(/ xmlns(:\w+)?="[^"]*"/, "") == ref.gsub(/ xmlns(:\w+)?="[^"]*"/, "")
    results[:default_ns_only] << base
  else
    results[:differ] << base
  end
rescue StandardError => e
  results[:error] << "#{base} (#{e.class.name.split('::').last}: #{e.message[0, 60]})"
end

results.each { |k, v| puts "#{k}: #{v.count} #{v.first(6).inspect}" }
