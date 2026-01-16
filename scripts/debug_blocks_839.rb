#!/usr/bin/env ruby
# Debug script for blocks_spec.rb:839

require "bundler/setup"
require "nokogiri"

HTML_HDR = <<~HEADER.freeze
  <html lang="en">
    <head/>
    <body lang="en">
      <div class="title-section">
        <p>\u00a0</p>
      </div>
      <br/>
      <div class="prefatory-section">
        <p>\u00a0</p>
      </div>
      <br/>
      <div class="main-section">
         <br/>
            <div class="TOC" id="_">
        <h1 class="IntroTitle">Table of contents</h1>
      </div>
HEADER

WORD_HDR = <<~HEADER.freeze
       <html xmlns:epub="http://www.idpf.org/2007/ops" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:m="http://schemas.microsoft.com/office/2004/12/omml" lang="en">
           <head>
    <style>
      <!--
      -->
    </style>
  </head>
         <body lang="EN-US" link="blue" vlink="#954F72">
           <div class="WordSection1">
             <p>\u00a0</p>
           </div>
HEADER

html5_doc = <<~HTML
  #{HTML_HDR}
              <br/>
              <div id="_">
                <h1 class="ForewordTitle">Foreword</h1>
                <p id="_" style="text-align:left;">Test</p>
              </div>
            </div>
          </body>
      </html>
HTML

html4_doc = <<~HTML
  #{WORD_HDR}
  <p class="page-break">
    <br clear="all" style="mso-special-character:line-break;page-break-before:always"/>
  </p>
          <div class="TOC" id="_">
    <h1 class="IntroTitle">Table of contents</h1>
  </div>
  <p class="page-break">
    <br clear="all" style="mso-special-character:line-break;page-break-before:always"/>
  </p>
          <div id="_">
            <h1 class="ForewordTitle">Foreword</h1>
            <p id="_" align="left" style="text-align:left;">Test</p>
          </div>
          <p>\u00a0</p>
        </div>
      </body>
  </html>
HTML

puts "=" * 80
puts "HTML5 PARSING"
puts "=" * 80

doc5 = Nokogiri::HTML5(html5_doc)
head5 = doc5.at("//head")
puts "HEAD element:"
puts head5.to_html
puts "\nCHILDREN:"
head5.children.each_with_index do |child, i|
  puts "  #{i}: #{child.name} - #{child.attributes.inspect}"
end

puts "\n#{'=' * 80}"
puts "HTML4 PARSING"
puts "=" * 80

doc4 = Nokogiri::HTML4(html4_doc)
head4 = doc4.at("//head")
puts "HEAD element:"
puts head4.to_html
puts "\nCHILDREN:"
head4.children.each_with_index do |child, i|
  puts "  #{i}: #{child.name} - #{child.attributes.inspect}"
end

puts "\n#{'=' * 80}"
puts "COMPARISON"
puts "=" * 80
puts "HTML5 head children: #{head5.children.size}"
puts "HTML4 head children: #{head4.children.size}"

meta5 = head5.xpath(".//meta")
meta4 = head4.xpath(".//meta")
puts "\nMETA elements:"
puts "HTML5: #{meta5.size} meta elements"
meta5.each_with_index do |m, i|
  puts "  #{i}: #{m.to_html}"
end
puts "HTML4: #{meta4.size} meta elements"
meta4.each_with_index do |m, i|
  puts "  #{i}: #{m.to_html}"
end
