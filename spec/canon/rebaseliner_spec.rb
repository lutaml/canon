# frozen_string_literal: true

require "spec_helper"
require "canon/rebaseliner"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe Canon::Rebaseliner do
  describe ".enabled?" do
    before { Canon::Rebaseliner.reset! }
    after { Canon::Rebaseliner.reset! }

    it "is false by default" do
      expect(Canon::Rebaseliner.enabled?).to be false
    end

    it "is true when env var is 'true'" do
      ENV["CANON_REGENERATE_EXPECTED"] = "true"
      Canon::Rebaseliner.reset!
      expect(Canon::Rebaseliner.enabled?).to be true
    ensure
      ENV.delete("CANON_REGENERATE_EXPECTED")
    end

    it "is true when env var is '1'" do
      ENV["CANON_REGENERATE_EXPECTED"] = "1"
      Canon::Rebaseliner.reset!
      expect(Canon::Rebaseliner.enabled?).to be true
    ensure
      ENV.delete("CANON_REGENERATE_EXPECTED")
    end

    it "is false for empty string" do
      ENV["CANON_REGENERATE_EXPECTED"] = ""
      Canon::Rebaseliner.reset!
      expect(Canon::Rebaseliner.enabled?).to be false
    ensure
      ENV.delete("CANON_REGENERATE_EXPECTED")
    end
  end

  describe "end-to-end fixture rewrites" do
    # Run a fixture spec file in a subprocess with the rebaseliner env var
    # set, then assert the file content was (or was not) modified.

    let(:fixture_dir) { File.expand_path("../fixtures/rebaseliner", __dir__) }

    def copy_fixture(name)
      target = File.join(@tmpdir, name)
      FileUtils.cp(File.join(fixture_dir, name), target)
      target
    end

    def run_rspec(spec_path, regenerate: false)
      env = regenerate ? { "CANON_REGENERATE_EXPECTED" => "true" } : {}
      Open3.capture3(env,
                     "bundle", "exec", "rspec",
                     "--no-color",
                     "--format", "doc",
                     spec_path,
                     chdir: canon_root)
    end

    def canon_root
      File.expand_path("../..", __dir__)
    end

    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    it "rewrites a squiggly heredoc on failure" do
      target = copy_fixture("simple_squiggly_input.rb")
      stdout, stderr, status = run_rspec(target, regenerate: true)

      aggregate_failures do
        expect(status).to be_success, "rspec failed: #{stdout}\n#{stderr}"
        expect(File.read(target)).to include("<root>fresh</root>")
        expect(File.read(target)).not_to include("<root>stale</root>")
        expect(stderr).to match(/\[canon:rebaseline\] rewritten/)
        # Second run with the env var OFF must pass.
        _stdout2, _stderr2, status2 = run_rspec(target, regenerate: false)
        expect(status2).to be_success
      end
    end

    it "rewrites the most-recent assignment for a reassigned variable" do
      target = copy_fixture("multiple_assignments_input.rb")
      _stdout, stderr, status = run_rspec(target, regenerate: true)

      aggregate_failures do
        expect(status).to be_success
        contents = File.read(target)
        expect(contents).to include("<first>fresh1</first>")
        expect(contents).to include("<second>fresh2</second>")
        expect(contents).not_to include("<first>stale</first>")
        expect(contents).not_to include("<second>stale</second>")
        expect(stderr.scan(/\[canon:rebaseline\] rewritten/).size).to eq(2)
      end
    end

    it "rewrites a heredoc passed inline to the matcher" do
      target = copy_fixture("inline_heredoc_input.rb")
      _stdout, _stderr, status = run_rspec(target, regenerate: true)

      aggregate_failures do
        expect(status).to be_success
        expect(File.read(target)).to include("<root>fresh</root>")
        expect(File.read(target)).not_to include("<root>stale</root>")
      end
    end

    it "skips heredoc with interpolation and leaves the file untouched" do
      target = copy_fixture("interpolation_skip_input.rb")
      original_contents = File.read(target)
      _stdout, stderr, status = run_rspec(target, regenerate: true)

      aggregate_failures do
        # Assertion still fails — interpolation case is not rewritten.
        expect(status).not_to be_success
        expect(File.read(target)).to eq(original_contents)
        expect(stderr).to match(/\[canon:rebaseline\] skipped_interpolation/)
      end
    end

    it "skips an inline string literal expected and leaves the file untouched" do
      target = copy_fixture("inline_string_skip_input.rb")
      original_contents = File.read(target)
      _stdout, stderr, status = run_rspec(target, regenerate: true)

      aggregate_failures do
        expect(status).not_to be_success
        expect(File.read(target)).to eq(original_contents)
        expect(stderr).to match(/\[canon:rebaseline\] skipped_inline_string/)
      end
    end

    it "never rewrites under .not_to" do
      target = copy_fixture("negated_input.rb")
      original_contents = File.read(target)
      _stdout, stderr, status = run_rspec(target, regenerate: true)

      aggregate_failures do
        # The .not_to expectation should PASS (actual != expected, so the
        # negation holds). The file must NOT be rewritten.
        expect(status).to be_success
        expect(File.read(target)).to eq(original_contents)
        expect(stderr).not_to match(/\[canon:rebaseline\] rewritten/)
      end
    end
  end
end
