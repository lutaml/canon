# frozen_string_literal: true

require "canon"
require "canon/diff_formatter/theme"

RSpec.describe Canon::DiffFormatter::Theme do
  describe "Validation constants" do
    it "defines valid ANSI colors" do
      expect(described_class::VALID_COLORS).to include(
        :default, :black, :red, :green, :yellow, :blue, :magenta, :cyan, :white,
        :bright_black, :bright_red, :bright_green, :bright_yellow, :bright_blue, :bright_magenta, :bright_cyan, :bright_white
      )
    end

    it "defines valid display modes" do
      expect(described_class::VALID_DISPLAY_MODES).to eq(%i[separate inline mixed])
    end

    it "defines styling properties" do
      expect(described_class::STYLING_PROPERTIES).to eq(%i[color bg bold underline strikethrough italic])
    end
  end

  describe "Theme lookup" do
    it "returns theme for known name" do
      expect(described_class[:light]).to be_a(Hash)
      expect(described_class[:dark]).to be_a(Hash)
      expect(described_class[:retro]).to be_a(Hash)
      expect(described_class[:claude]).to be_a(Hash)
    end

    it "raises ArgumentError for unknown theme" do
      expect { described_class[:nonexistent] }.to raise_error(ArgumentError)
    end

    it "returns theme names" do
      expect(described_class.names).to match_array(%i[light dark retro claude cyberpunk])
    end

    it "returns true for known theme" do
      expect(described_class.include?(:light)).to be true
      expect(described_class.include?(:dark)).to be true
    end

    it "returns false for unknown theme" do
      expect(described_class.include?(:nonexistent)).to be false
    end
  end

  describe "validate_all" do
    it "returns validation results for all predefined themes" do
      results = described_class.validate_all

      expect(results.keys).to match_array(described_class.names)

      results.each do |name, result|
        expect(result.valid).to eq(true),
          "Theme :#{name} invalid - missing: #{result.missing_keys}, extra: #{result.extra_keys}, invalid: #{result.invalid_values}"
      end
    end
  end

  describe ":light theme" do
    subject(:theme) { described_class[:light] }

    it "is complete and valid" do
      result = described_class.validate(theme)
      expect(result.valid).to eq(true),
        "Missing: #{result.missing_keys}, Extra: #{result.extra_keys}, Invalid: #{result.invalid_values}"
    end

    it "has name and description" do
      expect(theme[:name]).to eq("Light")
      expect(theme[:description]).to be_a(String)
    end

    it "uses light backgrounds for removed/added markers" do
      expect(theme[:diff][:removed][:marker][:bg]).to eq(:light_red)
      expect(theme[:diff][:added][:marker][:bg]).to eq(:light_green)
    end

    it "uses strikethrough for removed content" do
      expect(theme[:diff][:removed][:content][:strikethrough]).to be true
    end

    it "uses underline for changed_new content" do
      expect(theme[:diff][:changed][:content_new][:underline]).to be true
    end

    it "has xml section with tag differentiation" do
      expect(theme[:xml][:tag][:color]).to eq(:bright_blue)
      expect(theme[:xml][:attribute_name][:color]).to eq(:magenta)
      expect(theme[:xml][:attribute_value][:color]).to eq(:green)
    end

    it "has visualization characters" do
      expect(theme[:visualization][:space]).to eq("░")
      expect(theme[:visualization][:tab]).to eq("→")
      expect(theme[:visualization][:newline]).to eq("¶")
      expect(theme[:visualization][:nbsp]).to eq("␣")
    end

    it "uses separate display mode" do
      expect(theme[:display_mode]).to eq(:separate)
    end
  end

  describe ":dark theme" do
    subject(:theme) { described_class[:dark] }

    it "is complete and valid" do
      result = described_class.validate(theme)
      expect(result.valid).to eq(true),
        "Missing: #{result.missing_keys}, Extra: #{result.extra_keys}, Invalid: #{result.invalid_values}"
    end

    it "has no backgrounds for diff content" do
      expect(theme[:diff][:removed][:marker][:bg]).to be_nil
      expect(theme[:diff][:added][:marker][:bg]).to be_nil
      expect(theme[:diff][:removed][:content][:bg]).to be_nil
      expect(theme[:diff][:added][:content][:bg]).to be_nil
    end

    it "uses cyan for informative" do
      expect(theme[:diff][:informative][:marker][:color]).to eq(:cyan)
      expect(theme[:diff][:informative][:content][:color]).to eq(:cyan)
    end

    it "uses bright_blue for formatting" do
      expect(theme[:diff][:formatting][:marker][:color]).to eq(:bright_blue)
      expect(theme[:diff][:formatting][:content][:color]).to eq(:bright_blue)
    end

    it "uses yellow for changed marker" do
      expect(theme[:diff][:changed][:marker][:color]).to eq(:yellow)
    end
  end

  describe ":retro theme" do
    subject(:theme) { described_class[:retro] }

    it "is complete and valid" do
      result = described_class.validate(theme)
      expect(result.valid).to eq(true),
        "Missing: #{result.missing_keys}, Extra: #{result.extra_keys}, Invalid: #{result.invalid_values}"
    end

    it "uses yellow monochromatic palette (ANSI amber approximation)" do
      # ANSI doesn't have true amber, using yellow as approximation
      expect(theme[:xml][:tag][:color]).to eq(:bright_yellow)
      expect(theme[:xml][:attribute_name][:color]).to eq(:bright_yellow)
      expect(theme[:xml][:attribute_value][:color]).to eq(:bright_yellow)
    end

    it "uses inverse video (bg + bright) for removed" do
      expect(theme[:diff][:removed][:marker][:bg]).to eq(:yellow)
      expect(theme[:diff][:removed][:marker][:color]).to eq(:bright_yellow)
      expect(theme[:diff][:removed][:content][:bg]).to eq(:yellow)
      expect(theme[:diff][:removed][:content][:color]).to eq(:bright_yellow)
    end

    it "uses white for added (less emphasis)" do
      expect(theme[:diff][:added][:marker][:color]).to eq(:bright_white)
      expect(theme[:diff][:added][:marker][:bg]).to be_nil
    end

    it "uses italic for comments" do
      expect(theme[:xml][:comment][:italic]).to be true
    end

    it "uses yellow for structure" do
      expect(theme[:structure][:line_number][:color]).to eq(:yellow)
      expect(theme[:structure][:pipe][:color]).to eq(:yellow)
    end
  end

  describe ":claude theme" do
    subject(:theme) { described_class[:claude] }

    it "is complete and valid" do
      result = described_class.validate(theme)
      expect(result.valid).to eq(true),
        "Missing: #{result.missing_keys}, Extra: #{result.extra_keys}, Invalid: #{result.invalid_values}"
    end

    it "uses red background for removed" do
      expect(theme[:diff][:removed][:marker][:bg]).to eq(:red)
      expect(theme[:diff][:removed][:marker][:color]).to eq(:white)
      expect(theme[:diff][:removed][:content][:bg]).to eq(:red)
      expect(theme[:diff][:removed][:content][:color]).to eq(:white)
    end

    it "uses green background for added" do
      expect(theme[:diff][:added][:marker][:bg]).to eq(:green)
      expect(theme[:diff][:added][:marker][:color]).to eq(:white)
      expect(theme[:diff][:added][:content][:bg]).to eq(:green)
      expect(theme[:diff][:added][:content][:color]).to eq(:white)
    end

    it "uses magenta background for changed marker" do
      expect(theme[:diff][:changed][:marker][:bg]).to eq(:magenta)
      expect(theme[:diff][:changed][:marker][:color]).to eq(:white)
    end

    it "uses bright colors for changed content" do
      expect(theme[:diff][:changed][:content_old][:color]).to eq(:bright_red)
      expect(theme[:diff][:changed][:content_new][:color]).to eq(:bright_green)
    end

    it "uses yellow for structure" do
      expect(theme[:structure][:line_number][:color]).to eq(:yellow)
      expect(theme[:structure][:pipe][:color]).to eq(:yellow)
    end
  end

  describe "Theme Inheritance" do
    it "creates inherited theme with merge" do
      inherited = described_class.inherit_from(:dark).merge(
        diff: {
          removed: {
            content: { bg: :light_red }
          }
        }
      ).build

      # Inherits all dark theme properties
      expect(inherited[:diff][:added][:marker][:color]).to eq(:green)
      expect(inherited[:diff][:formatting][:marker][:color]).to eq(:bright_blue)

      # Override applied
      expect(inherited[:diff][:removed][:content][:bg]).to eq(:light_red)

      # Original theme unchanged
      expect(described_class[:dark][:diff][:removed][:content][:bg]).to be_nil
    end

    it "supports chaining merge calls" do
      inherited = described_class.inherit_from(:retro)
        .merge(diff: { removed: { content: { bg: :light_red } } })
        .merge(xml: { tag: { color: :bright_green } })
        .build

      expect(inherited[:diff][:removed][:content][:bg]).to eq(:light_red)
      expect(inherited[:xml][:tag][:color]).to eq(:bright_green)
      expect(inherited[:diff][:added][:marker][:color]).to eq(:bright_white) # from retro
    end

    it "deep merges nested hashes" do
      inherited = described_class.inherit_from(:dark).merge(
        diff: {
          removed: {
            marker: { color: :bright_red } # Only override color, keep bg
          }
        }
      ).build

      # Only color should be overridden, bg should remain nil from dark theme
      expect(inherited[:diff][:removed][:marker][:color]).to eq(:bright_red)
      expect(inherited[:diff][:removed][:marker][:bg]).to be_nil
    end

    it "raises error for unknown base theme" do
      expect {
        described_class.inherit_from(:nonexistent).build
      }.to raise_error(ArgumentError, /Unknown theme/)
    end
  end

  describe "Theme validation edge cases" do
    it "rejects invalid color value" do
      invalid_theme = described_class[:dark].dup
      invalid_theme[:diff][:removed][:marker][:color] = :invalid_color

      result = described_class.validate(invalid_theme)
      expect(result.valid).to be false
      expect(result.invalid_values).to include(/color must be one of/)
    end

    it "rejects invalid bg value" do
      invalid_theme = described_class[:dark].dup
      invalid_theme[:diff][:removed][:marker][:bg] = :invalid_bg

      result = described_class.validate(invalid_theme)
      expect(result.valid).to be false
      expect(result.invalid_values).to include(/bg must be one of/)
    end

    it "rejects invalid boolean value" do
      invalid_theme = described_class[:dark].dup
      invalid_theme[:diff][:removed][:content][:bold] = "yes"

      result = described_class.validate(invalid_theme)
      expect(result.valid).to be false
      expect(result.invalid_values).to include(/bold must be true or false/)
    end

    it "rejects invalid display_mode" do
      invalid_theme = described_class[:dark].dup
      invalid_theme[:display_mode] = :invalid_mode

      result = described_class.validate(invalid_theme)
      expect(result.valid).to be false
      expect(result.invalid_values).to include(/display_mode must be one of/)
    end

    it "rejects missing top-level keys" do
      invalid_theme = described_class[:dark].dup
      invalid_theme.delete(:xml)

      result = described_class.validate(invalid_theme)
      expect(result.valid).to be false
      expect(result.missing_keys).to include("top-level.xml")
    end
  end

  describe "html section mirrors xml" do
    it "light theme has same structure for html and xml" do
      theme = described_class[:light]
      expect(theme[:html].keys).to match_array(theme[:xml].keys)
    end

    it "dark theme has same structure for html and xml" do
      theme = described_class[:dark]
      expect(theme[:html].keys).to match_array(theme[:xml].keys)
    end

    it "retro theme has same structure for html and xml" do
      theme = described_class[:retro]
      expect(theme[:html].keys).to match_array(theme[:xml].keys)
    end

    it "claude theme has same structure for html and xml" do
      theme = described_class[:claude]
      expect(theme[:html].keys).to match_array(theme[:xml].keys)
    end
  end
end
