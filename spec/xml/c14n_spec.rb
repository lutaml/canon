# frozen_string_literal: true

RSpec.describe Xml::C14n do
  it "has a version number" do
    expect(Xml::C14n::VERSION).not_to be nil
  end

  Dir.glob("spec/fixtures/*.raw.xml").each do |f|
    c14n_filename = f.gsub(".raw.", ".c14n.")
    subject(:xml_raw) { File.open(f) }
    let(:xml_c14n) { File.open(c14n_filename) }

    it "canonicalizes #{File.basename(f)}" do
      input = Xml::C14n.format(File.read(xml_raw))
      output = Xml::C14n.format(File.read(xml_c14n))

      expect(output).to be_analogous_with(input)
    end
  end
end
