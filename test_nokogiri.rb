require "bundler/setup"
require "nokogiri"

html1 = "<html><body><p>Test</p></body></html>"
html2 = "<html>\n\n<body>\n\n<p>Test</p>\n\n</body>\n\n</html>"

puts "=== Nokogiri HTML5.fragment ==="
frag1 = Nokogiri::HTML5.fragment(html1)
frag2 = Nokogiri::HTML5.fragment(html2)

puts "html1 children count: #{frag1.children.count}"
frag1.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class} - #{child.name}"
end

puts "\nhtml2 children count: #{frag2.children.count}"
frag2.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class} - #{child.name}"
end

puts "\n=== Nokogiri::XML.fragment ==="
frag3 = Nokogiri::XML.fragment(html1)
frag4 = Nokogiri::XML.fragment(html2)

puts "html1 children count: #{frag3.children.count}"
frag3.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class} - #{child.name}"
end

puts "\nhtml2 children count: #{frag4.children.count}"
frag4.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class} - #{child.name}"
end
