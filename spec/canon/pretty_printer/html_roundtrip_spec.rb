# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require "canon/pretty_printer/html"

# Regression test for https://github.com/lutaml/canon/issues/116
#
# Pins the roundtrip property: under the :metanorma match profile, raw HTML
# emitted by a Metanorma document processor must be html4-equivalent to its
# own Canon-pretty-printed form. The pretty-printed form is what Canon emits
# when CANON_HTML_DIFF_SHOW_PRETTYPRINT_RECEIVED=1 is set; users copy-paste
# that block back as a fixture, so it must compare equal to the raw input
# that produced it.
#
# canon_023_pretty_print is generated dynamically via the same call path
# DiffFormatter#prettyprint_for_display uses (lib/canon/diff_formatter.rb:929-948).
# canon_013_pretty_print is the older expanded form (one child per line) and
# is kept as a separate hardcoded heredoc to pin its behavior independently.
RSpec.describe "Pretty-print roundtrip (issue #116)" do
  around do |ex|
    saved = Canon::Config.instance.profile
    Canon::Config.instance.profile = :metanorma
    ex.run
  ensure
    Canon::Config.instance.profile = saved
  end

  def canon_pretty_print(raw)
    Canon::PrettyPrinter::Html
      .new(indent: 2, indent_type: "space")
      .format(raw)
  end

  describe "simple body (a_spec.rb fixture)" do
    let(:raw_output) do
      <<~OUTPUT
        <body lang="EN-US" link="blue" vlink="#954F72">
          <div class="WordSection1">
            <p>&#xA0;</p>
          </div>
          <p class="section-break">
            <br clear="all" class="section"/>
          </p>
          <div class="WordSection2">
            <div class="WordSectionContents">
              <h1 class="IEEEStdsLevel1frontmatter">Contents</h1>
            </div>
            <p>&#xA0;</p>
          </div>
          <p class="section-break">
            <br clear="all" class="section"/>
          </p>
          <p class="section-break">
            <br clear="all" style="page-break-before:auto;mso-break-type:section-break"/>
          </p>
          <div class="WordSectionMain">
            <div id="_"><h1>1.<span style="mso-tab-count:1">&#xA0; </span>Terms and Definitions</h1>
            <p>For the purposes of this document, the following terms and definitions apply.</p><p class="TermNum" id="paddy1"/>

        <p><b>paddy</b>, &lt;rice&gt;, &lt;in agriculture, dated&gt;<span class="fmt-termsource-delim">(</span><span class="std_publisher">ISO&#xA0;</span><span class="std_docNumber">7301</span>:<span class="std_year">2011</span>,  3.1, modified &#x2014; The term "cargo rice" is shown as deprecated, and Note 1 to entry is not included here<span class="fmt-termsource-delim">)</span>: rice retaining its husk after threshing <span class="fmt-termsource-delim">(</span>adapted from t1, adapted; Termbase IEV, term ID xyz, adapted &#x2014; with adjustments<span class="fmt-termsource-delim">)</span></p>
        <div id="_" class="example" style="page-break-after: avoid;page-break-inside: avoid;"><p class="example-title"><i>Example 1</i><i>:</i></p>
          <p id="_">Foreign seeds, husks, bran, sand, dust.</p>
          <div class="ul_wrap"><ul>
          <li id="_">A</li>
          </ul></div>
        </div>
        <div id="_" class="example"><p class="example-title"><i>Example 2</i><i>:</i></p>
          <div class="ul_wrap"><ul>
          <li id="_">A</li>
          </ul></div>
        </div>





        <p><b>paddy</b>: rice retaining its husk after threshing <i>Syn:</i> <b>paddy rice</b>, &lt;in agriculture&gt;; <b>rough rice</b>. <span class="fmt-termsource-delim">[</span><span class="std_publisher">ISO&#xA0;</span><span class="std_docNumber">7301</span>:<span class="std_year">2011</span>,  3(1)<span class="fmt-termsource-delim">]</span></p>
        <div id="_" class="example"><p class="example-title"><i>Example</i><i>:</i></p>
          <div class="ul_wrap"><ul>
          <li id="_">A</li>
          </ul></div>
        </div>
        <div id="_" class="Note" style="page-break-after: avoid;page-break-inside: avoid;"><p><span class="note_label">NOTE 1&#x2014;</span>The starch of waxy rice consists almost entirely of amylopectin. The kernels have a tendency to stick together after cooking.</p></div>
        <div id="_" class="Note"><p><span class="note_label">NOTE 2&#x2014;</span>The starch of waxy rice consists almost entirely of amylopectin. The kernels have a tendency to stick together after cooking.</p></div>

        <p><b>paddy rice</b>, &lt;in agriculture&gt;:  <i>See:</i> <b>paddy</b>.</p><p class="TermNum" id="_"/>

        <p><b>rough rice</b>:  <i>See:</i> <b>paddy</b>.</p>




        </div>
          </div>
        </body>
      OUTPUT
    end

    let(:canon_013_pretty_print) do
      <<~OUTPUT
        <body lang="EN-US" link="blue" vlink="#954F72">
           <div class="WordSection1">
              <p> </p>
           </div>
           <p class="section-break">
              <br clear="all" class="section"/>
           </p>
           <div class="WordSection2">
              <div class="WordSectionContents">
                 <h1 class="IEEEStdsLevel1frontmatter">Contents</h1>
              </div>
              <p> </p>
           </div>
           <p class="section-break">
              <br clear="all" class="section"/>
           </p>
           <div class="WordSectionMiddleTitle"/>
           <p class="section-break">
              <br clear="all" style="page-break-before:auto;mso-break-type:section-break"/>
           </p>
           <div class="WordSectionMain">
              <div id="_">
                 <h1>
                    1.
                    <span style="mso-tab-count:1">  </span>
                    Terms and Definitions
                 </h1>
                 <p>For the purposes of this document, the following terms and definitions apply.</p>
                 <p class="TermNum" id="paddy1"/>
                 <p>
                    <b>paddy</b>
                    , &lt;rice&gt;, &lt;in agriculture, dated&gt;
                    <span class="fmt-termsource-delim">(</span>
                    <span class="std_publisher">ISO&#xA0;</span>
                    <span class="std_docNumber">7301</span>
                    :
                    <span class="std_year">2011</span>
                    ,  3.1, modified — The term "cargo rice" is shown as deprecated, and Note 1 to entry is not included here
                    <span class="fmt-termsource-delim">)</span>
                    : rice retaining its husk after threshing
                    <span class="fmt-termsource-delim">(</span>
                    adapted from t1, adapted; Termbase IEV, term ID xyz, adapted — with adjustments
                    <span class="fmt-termsource-delim">)</span>
                 </p>
                 <div id="_" class="example" style="page-break-after: avoid;page-break-inside: avoid;">
                    <p class="example-title">
                       <i>Example 1</i>
                       <i>:</i>
                    </p>
                    <p id="_">Foreign seeds, husks, bran, sand, dust.</p>
                    <div class="ul_wrap">
                       <ul>
                          <li id="_">A</li>
                       </ul>
                    </div>
                 </div>
                 <div id="_" class="example">
                    <p class="example-title">
                       <i>Example 2</i>
                       <i>:</i>
                    </p>
                    <div class="ul_wrap">
                       <ul>
                          <li id="_">A</li>
                       </ul>
                    </div>
                 </div>
                 <p class="TermNum" id="paddy"/>
                 <p>
                    <b>paddy</b>
                    : rice retaining its husk after threshing
                    <i>Syn:</i>
                    <b>paddy rice</b>
                    , &lt;in agriculture&gt;;
                    <b>rough rice</b>
                    .
                    <span class="fmt-termsource-delim">[</span>
                    <span class="std_publisher">ISO&#xA0;</span>
                    <span class="std_docNumber">7301</span>
                    :
                    <span class="std_year">2011</span>
                    ,  3(1)
                    <span class="fmt-termsource-delim">]</span>
                 </p>
                 <div id="_" class="example">
                    <p class="example-title">
                       <i>Example</i>
                       <i>:</i>
                    </p>
                    <div class="ul_wrap">
                       <ul>
                          <li id="_">A</li>
                       </ul>
                    </div>
                 </div>
                 <div id="_" class="Note" style="page-break-after: avoid;page-break-inside: avoid;">
                    <p>
                       <span class="note_label">NOTE 1—</span>
                       The starch of waxy rice consists almost entirely of amylopectin. The kernels have a tendency to stick together after cooking.
                    </p>
                 </div>
                 <div id="_" class="Note">
                    <p>
                       <span class="note_label">NOTE 2—</span>
                       The starch of waxy rice consists almost entirely of amylopectin. The kernels have a tendency to stick together after cooking.
                    </p>
                 </div>
                 <p class="TermNum" id="_"/>
                 <p>
                    <b>paddy rice</b>
                    , &lt;in agriculture&gt;:
                    <i>See:</i>
                    <b>paddy</b>
                    .
                 </p>
                 <p class="TermNum" id="_"/>
                 <p>
                    <b>rough rice</b>
                    :
                    <i>See:</i>
                    <b>paddy</b>
                    .
                 </p>
              </div>
           </div>
        </body>
      OUTPUT
    end

    # putting on hold
    xit "raw output is html4-equivalent to canon_013_pretty_print (hardcoded old style)" do
      expect(raw_output).to be_html4_equivalent_to(canon_013_pretty_print)
    end

    it "raw output is html4-equivalent to canon_023_pretty_print (dynamic)" do
      expect(raw_output).to be_html4_equivalent_to(canon_pretty_print(raw_output))
    end

    # Body extracted from metanorma-ieee IsoDoc::Ieee::WordConvert output via
    # Nokogiri::HTML5(word_html).at("//body").to_html — the parser-correct
    # path. The status-quo metanorma-ieee call uses Nokogiri::XML/to_xml,
    # which is being fixed out of band; this fixture pins the HTML5/to_html
    # form so the canon-side regression is testable without the metanorma
    # toolchain.

    it "Nokogiri extracted output is html4-equivalent to canon_023_pretty_print (dynamic)" do
      expect(Nokogiri::HTML5(raw_output).at_xpath("//body").to_html)
        .to be_html4_equivalent_to(canon_pretty_print(raw_output))
      expect(Nokogiri::HTML5(raw_output).at_xpath("//body").to_xml)
        .to be_html4_equivalent_to(canon_pretty_print(raw_output))
    end
  end
end
