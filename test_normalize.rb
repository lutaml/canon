require "bundler/setup"
require "canon/html/data_model"

html1 = "<html><body><p>Test</p></body></html>"
html2 = "<html>\n\n<body>\n\n<p>Test</p>\n\n</body>\n\n</html>"

# Parse both without preprocessing
node1 = Canon::Html::DataModel.from_html(html1)
node2 = Canon::Html::DataModel.from_html(html2)

puts "=== Without preprocessing ==="
puts "node1 root children count: #{node1.children.count}"
node1.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class}"
  if child.is_a?(Canon::Xml::Nodes::ElementNode)
    puts "    Name: #{child.name}"
    puts "    Children count: #{child.children.count}"
  end
end

puts "\nnode2 root children count: #{node2.children.count}"
node2.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class}"
  if child.is_a?(Canon::Xml::Nodes::ElementNode)
    puts "    Name: #{child.name}"
    puts "    Children count: #{child.children.count}"
  end
end

# Now with normalize preprocessing
html2_norm = html2.lines.map(&:strip).reject(&:empty?).join("\n")
node2_norm = Canon::Html::DataModel.from_html(html2_norm)

puts "\n=== With :normalize preprocessing ==="
puts "html2_norm:"
puts html2_norm
puts ""
puts "node2_norm root children count: #{node2_norm.children.count}"
node2_norm.children.each_with_index do |child, i|
  puts "  Child #{i}: #{child.class}"
  if child.is_a?(Canon::Xml::Nodes::ElementNode)
    puts "    Name: #{child.name}"
    puts "    Children count: #{child.children.count}"
  end
end
