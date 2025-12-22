# frozen_string_literal: true

require "spec_helper"
require "canon/commands/diff_command"
require "tmpdir"
require "fileutils"

RSpec.describe Canon::Commands::DiffCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:file1_path) { File.join(temp_dir, "file1.xml") }
  let(:file2_path) { File.join(temp_dir, "file2.xml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "diff display behavior" do
    context "when files differ" do
      before do
        File.write(file1_path, "<root><item>A</item></root>")
        File.write(file2_path, "<root><item>B</item></root>")
      end

      it "shows diff by default without --verbose flag" do
        command = described_class.new(color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Visual Diff:/).to_stdout.and raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "shows diff with --verbose flag" do
        command = described_class.new(verbose: true, color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Visual Diff:/).to_stdout.and raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it "exits with status 1 when files differ" do
        command = described_class.new(color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context "when files are equivalent" do
      before do
        File.write(file1_path, "<root><item>A</item></root>")
        File.write(file2_path, "<root><item>A</item></root>")
      end

      it "shows success message without --verbose" do
        command = described_class.new(color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to output(/semantically equivalent/).to_stdout.and raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end

      it "shows success message with --verbose" do
        command = described_class.new(verbose: true, color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to output(/semantically equivalent/).to_stdout.and raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end

      it "exits with status 0 when files are equivalent" do
        command = described_class.new(color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end
    end

    context "with different diff modes" do
      before do
        File.write(file1_path, "<root><item>A</item></root>")
        File.write(file2_path, "<root><item>B</item></root>")
      end

      it "shows diff in by_object mode" do
        command = described_class.new(diff_mode: "by_object", color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Visual Diff:/).to_stdout.and raise_error(SystemExit)
      end

      it "shows diff in by_line mode" do
        command = described_class.new(diff_mode: "by_line", color: false)

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Line-by-line diff/).to_stdout.and raise_error(SystemExit)
      end
    end
  end

  describe "comment handling" do
    context "with comment differences in by_object mode" do
      before do
        File.write(file1_path, <<~XML)
          <root>
            <!-- Comment A -->
            <item>Value</item>
          </root>
        XML
        File.write(file2_path, <<~XML)
          <root>
            <!-- Comment B -->
            <item>Value</item>
          </root>
        XML
      end

      it "shows actual comment content, not just counts" do
        command = described_class.new(
          diff_mode: "by_object",
          comments: "strict",
          color: false,
        )

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Comment A/).to_stdout.and raise_error(SystemExit)
      end

      it "distinguishes between different comments" do
        command = described_class.new(
          diff_mode: "by_object",
          comments: "strict",
          color: false,
        )

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Comment B/).to_stdout.and raise_error(SystemExit)
      end
    end

    context "with comment differences in by_line mode" do
      before do
        File.write(file1_path, <<~XML)
          <root>
            <!-- Comment A -->
            <item>Value</item>
          </root>
        XML
        File.write(file2_path, <<~XML)
          <root>
            <!-- Comment B -->
            <item>Value</item>
          </root>
        XML
      end

      it "shows actual comment content in line diff" do
        command = described_class.new(
          diff_mode: "by_line",
          comments: "strict",
          color: false,
        )

        # Comment content is shown but spaces may be visualized
        expect do
          command.run(file1_path, file2_path)
        end.to output(/Comment.*A/).to_stdout.and raise_error(SystemExit)
      end
    end

    context "with MULTIPLE comment differences" do
      before do
        File.write(file1_path, <<~XML)
          <root>
            <!-- Comment 1 -->
            <item>A</item>
            <!-- Comment 2 -->
            <item>B</item>
            <!-- Comment 3 -->
            <item>C</item>
          </root>
        XML
        File.write(file2_path, <<~XML)
          <root>
            <!-- Different 1 -->
            <item>A</item>
            <!-- Different 2 -->
            <item>B</item>
            <!-- Different 3 -->
            <item>C</item>
          </root>
        XML
      end

      it "shows ALL comment differences in by_object mode, not just first" do
        command = described_class.new(
          diff_mode: "by_object",
          comments: "strict",
          color: false,
        )

        expect do
          command.run(file1_path, file2_path)
        end.to output(/Comment 1.*Comment 2.*Comment 3/m).to_stdout.and raise_error(SystemExit)
      end

      it "shows ALL comment differences in by_line mode without duplication" do
        command = described_class.new(
          diff_mode: "by_line",
          comments: "strict",
          color: false,
        )

        # All 3 comments should appear (spaces visualized as ░)
        expect do
          command.run(file1_path, file2_path)
        end.to output(/Comment.*1.*Comment.*2.*Comment.*3/m).to_stdout.and raise_error(SystemExit)
      end
    end
  end
end
