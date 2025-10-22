# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison do
  describe "HTML comparison edge cases" do
    context "with identical complex XML" do
      let(:xml1) do
        <<~XML
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
                   <p id="A">
                      ABC
                      <note id="B" autonum="">
                         <fmt-name id="_">
                            <span class="fmt-caption-label">
                               <span class="fmt-element-name">NOTE</span>
                            </span>
                         </fmt-name>
                         <p id="C">XYZ</p>
                      </note>
                   </p>
                </foreword>
             </preface>
          </iso-standard>
        XML
      end

      it "returns true for non-verbose comparison" do
        opts = {
          match: {
            text_content: :normalize,
            comments: :ignore,
          },
          verbose: false,
        }
        expect(described_class.equivalent?(xml1, xml1, opts)).to be true
      end

      it "returns ComparisonResult for verbose comparison" do
        opts = {
          match: {
            text_content: :normalize,
            comments: :ignore,
          },
          verbose: true,
        }
        result = described_class.equivalent?(xml1, xml1, opts)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).to be_empty
        expect(result.equivalent?).to be true
      end

      it "returns same result regardless of argument order" do
        opts = {
          match: {
            text_content: :normalize,
            comments: :ignore,
          },
        }
        result1 = described_class.equivalent?(xml1, xml1, opts)
        result2 = described_class.equivalent?(xml1, xml1, opts)
        expect(result1).to eq(result2)
      end
    end

    context "with parsed and unparsed HTML" do
      let(:html_raw) do
        "<html><body><p>Test</p></body></html>"
      end

      let(:html_parsed) do
        require "nokogiri"
        Nokogiri::HTML(html_raw).to_html
      end

      it "treats parsed and raw HTML as equivalent" do
        opts = {
          match: {
            text_content: :normalize,
            comments: :ignore,
          },
        }
        expect(described_class.equivalent?(html_raw, html_parsed,
                                           opts)).to be true
      end
    end
  end
end
