# frozen_string_literal: true

require "spec_helper"
require "canon/validators/html_validator"

RSpec.describe Canon::Validators::HtmlValidator do
  describe ".validate!" do
    context "with valid HTML" do
      it "does not raise error for well-formed HTML5" do
        html = "<html><body><div>content</div></body></html>"
        expect { described_class.validate!(html) }.not_to raise_error
      end

      it "does not raise error for XHTML" do
        html = '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body><div>content</div></body></html>'
        expect { described_class.validate!(html) }.not_to raise_error
      end

      it "does not raise error for empty/nil input" do
        expect { described_class.validate!("") }.not_to raise_error
        expect { described_class.validate!(nil) }.not_to raise_error
      end
    end

    context "with malformed HTML" do
      it "raises ValidationError for malformed XHTML" do
        html = '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body><div>content</body></html>'
        expect { described_class.validate!(html) }.to raise_error(
          Canon::ValidationError,
        ) do |error|
          expect(error.format).to eq(:html)
          expect(error.message).to match(/HTML Validation Error/)
        end
      end
    end
  end
end
