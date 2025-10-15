# frozen_string_literal: true

require "spec_helper"
require "canon/cli"
require "tempfile"

RSpec.describe Canon::Cli do
  describe "format command" do
    it "canonicalizes an XML file" do
      with_temp_file("<root><b>2</b><a>1</a></root>", ".xml") do |input|
        output = capture_stdout do
          described_class.start(["format", input])
        end

        expect(output).to include("<root>")
        expect(output).to include("<a>1</a>")
        expect(output).to include("<b>2</b>")
      end
    end

    it "canonicalizes a JSON file" do
      with_temp_file('{"z":3,"a":1}', ".json") do |input|
        output = capture_stdout do
          described_class.start(["format", input])
        end

        expect(output).to include('"a"')
        expect(output).to include('"z"')
      end
    end

    it "canonicalizes a YAML file" do
      with_temp_file("z: 3\na: 1", ".yaml") do |input|
        output = capture_stdout do
          described_class.start(["format", input])
        end

        expect(output).to include("a:")
        expect(output).to include("z:")
      end
    end

    it "writes output to file when --output specified" do
      with_temp_file("<root><b>2</b><a>1</a></root>", ".xml") do |input|
        Tempfile.create(["output", ".xml"]) do |output_file|
          capture_stdout do
            described_class.start(["format", input, "--output",
                                   output_file.path])
          end

          result = File.read(output_file.path)
          expect(result).to include("<root>")
        end
      end
    end

    it "respects --format option" do
      with_temp_file("<root><a>1</a></root>", ".txt") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--format", "xml"])
        end

        expect(output).to include("<root>")
      end
    end

    it "uses pretty mode by default" do
      with_temp_file("<root><b>2</b><a>1</a></root>", ".xml") do |input_file|
        output = capture_stdout do
          described_class.start(["format", input_file])
        end

        # Default is now pretty mode with indentation
        expect(output).to include("<root>")
        expect(output).to include("  <b>2</b>")
        expect(output).to include("  <a>1</a>")
      end
    end

    it "uses pretty mode when specified" do
      with_temp_file("<root><b>2</b><a>1</a></root>", ".xml") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--mode", "pretty"])
        end

        # Pretty mode includes indentation
        expect(output).to include("  <a>")
        expect(output).to include("  <b>")
      end
    end

    it "respects --indent option in pretty mode" do
      with_temp_file("<root><a>1</a></root>", ".xml") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--mode", "pretty",
                                 "--indent", "4"])
        end

        # Should have 4 spaces of indentation
        expect(output).to include("    <a>")
      end
    end

    it "uses tab indentation for XML when indent_type is tab" do
      with_temp_file("<root><a>1</a></root>", ".xml") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--mode", "pretty",
                                 "--indent-type", "tab"])
        end

        # Should have tab indentation
        expect(output).to include("\t<a>")
      end
    end

    it "uses space indentation for XML by default" do
      with_temp_file("<root><a>1</a></root>", ".xml") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--mode", "pretty"])
        end

        # Should have space indentation (2 spaces default)
        expect(output).to include("  <a>")
        expect(output).not_to include("\t<a>")
      end
    end

    it "uses tab indentation for JSON when indent_type is tab" do
      with_temp_file('{"z":3,"a":1}', ".json") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--mode", "pretty",
                                 "--indent-type", "tab"])
        end

        # Should have tab indentation
        expect(output).to include("\t\"a\"")
      end
    end

    it "uses custom space indentation for JSON" do
      with_temp_file('{"a":{"b":1}}', ".json") do |input|
        output = capture_stdout do
          described_class.start(["format", input, "--mode", "pretty",
                                 "--indent", "4"])
        end

        # Should have 4-space indentation
        expect(output).to include("    \"a\"")
        expect(output).to include("        \"b\"")
      end
    end
  end

  describe "diff command" do
    it "reports files as equivalent when they are" do
      with_temp_file("<root><a>1</a></root>", ".xml") do |file1|
        with_temp_file("<root><a>1</a></root>", ".xml") do |file2|
          output = capture_stdout do
            expect do
              described_class.start(["diff", file1, file2])
            end.to raise_error(SystemExit) do |error|
              expect(error.status).to eq(0)
            end
          end

          expect(output).to include("semantically equivalent")
        end
      end
    end

    it "shows diff when files differ" do
      with_temp_file("<root><a>1</a></root>", ".xml") do |file1|
        with_temp_file("<root><a>2</a></root>", ".xml") do |file2|
          output = capture_stdout do
            expect do
              described_class.start(["diff", file1, file2, "--verbose"])
            end.to raise_error(SystemExit) do |error|
              expect(error.status).to eq(1)
            end
          end

          expect(output).to include("Visual Diff:")
        end
      end
    end
  end

  private

  def with_temp_file(content, ext)
    Tempfile.create(["test", ext]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
