# frozen_string_literal: true

require "spec_helper"
require "canon/rspec_matchers"

RSpec.describe "IsoDoc XML comparison" do
  it "compares identical complex XML with many nested elements" do
    xml = <<~XML
      <iso-standard xmlns="http://riboseinc.com/isoxml" type="presentation">
         <preface>
            <clause type="toc" id="_" displayorder="1">
               <fmt-title id="_" depth="1">Table of contents</fmt-title>
            </clause>
            <foreword id="fwd" displayorder="2">
               <title id="_">Foreword</title>
               <fmt-title id="_" depth="1">
                  <semx element="title" source="_">Foreword</semx>
               </fmt-title>
               <figure id="F" autonum="1">
                  <fmt-name id="_">
                     <span class="fmt-caption-label">
                        <span class="fmt-element-name">Figure</span>
                        <semx element="autonum" source="F">1</semx>
                     </span>
                  </fmt-name>
                  <note id="FB" autonum="">
                     <fmt-name id="_">
                        <span class="fmt-caption-label">
                           <span class="fmt-element-name">NOTE</span>
                        </span>
                     </fmt-name>
                     <p>XYZ</p>
                  </note>
               </figure>
            </foreword>
         </preface>
      </iso-standard>
    XML

    expect(xml).to be_xml_equivalent_to(xml)
  end
end
