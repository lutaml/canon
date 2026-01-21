# frozen_string_literal: true

require "spec_helper"
require "canon/color_detector"

RSpec.describe Canon::ColorDetector do
  describe ".supports_color?" do
    before do
      # Save original ENV values
      @original_env = ENV.to_h
    end

    after do
      # Restore original ENV values
      ENV.clear
      @original_env.each { |k, v| ENV[k] = v }
    end

    context "when NO_COLOR is set" do
      it "disables colors regardless of other settings" do
        ENV["NO_COLOR"] = "1"
        ENV["TERM"] = "xterm-256color"
        ENV["COLORTERM"] = "truecolor"

        expect(described_class.supports_color?).to be false
      end

      it "disables colors even with explicit true" do
        ENV["NO_COLOR"] = "1"

        expect(described_class.supports_color?(explicit: true)).to be false
      end

      it "disables colors when NO_COLOR is set but empty" do
        ENV["NO_COLOR"] = ""

        expect(described_class.supports_color?).to be false
      end
    end

    context "when explicit choice is provided" do
      it "returns true when explicit is true" do
        expect(described_class.supports_color?(explicit: true)).to be true
      end

      it "returns false when explicit is false" do
        expect(described_class.supports_color?(explicit: false)).to be false
      end

      it "ignores NO_COLOR when explicit is false" do
        ENV["NO_COLOR"] = "1"

        expect(described_class.supports_color?(explicit: false)).to be false
      end
    end

    context "when output is not a TTY" do
      it "disables colors for non-TTY output" do
        non_tty = StringIO.new

        expect(described_class.supports_color?(output: non_tty)).to be false
      end
    end

    context "terminal capability detection via ENV" do
      let(:mock_tty) do
        Object.new.tap do |obj|
          def obj.tty?
            true
          end

          def obj.isatty
            true
          end
        end
      end

      context "COLORTERM variable" do
        it "enables colors for 24bit" do
          ENV["COLORTERM"] = "24bit"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "enables colors for truecolor" do
          ENV["COLORTERM"] = "truecolor"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "enables colors for true" do
          ENV["COLORTERM"] = "true"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end
      end

      context "TERM variable" do
        it "enables colors for 256-color terminals" do
          ENV["TERM"] = "xterm-256color"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "enables colors for terminals ending with 256" do
          ENV["TERM"] = "screen-256"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "enables colors for direct color terminals" do
          ENV["TERM"] = "xterm-direct"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "disables colors for dumb terminals" do
          ENV["TERM"] = "dumb"

          expect(described_class.supports_color?(output: mock_tty)).to be false
        end

        it "disables colors for emacs terminals" do
          ENV["TERM"] = "emacs"

          expect(described_class.supports_color?(output: mock_tty)).to be false
        end

        it "enables colors for common modern terminals" do
          ENV["TERM"] = "xterm"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "enables colors for screen" do
          ENV["TERM"] = "screen"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "defaults to true for unknown TERM" do
          ENV["TERM"] = "unknown"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "defaults to true for empty TERM" do
          ENV["TERM"] = ""

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end
      end

      context "CI environments" do
        it "enables colors for GitHub Actions" do
          ENV["CI"] = "1"
          ENV["GITHUB_ACTIONS"] = "1"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "enables colors for TeamCity" do
          ENV["TEAMCITY_VERSION"] = "1.0.0"

          expect(described_class.supports_color?(output: mock_tty)).to be true
        end

        it "disables colors for CI with dumb TERM" do
          ENV["CI"] = "1"
          ENV["TERM"] = "dumb"

          expect(described_class.supports_color?(output: mock_tty)).to be false
        end
      end
    end
  end
end
