# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

begin
  require "opal/rspec/rake_task"

  # Configure Opal load paths at load time (same pattern as moxml)
  if defined?(Opal)
    Opal.append_path File.expand_path("lib", __dir__)

    # moxml gem
    begin
      moxml_spec = Gem::Specification.find_by_name("moxml")
      moxml_lib = moxml_spec.full_require_paths.first
      Opal.append_path moxml_lib
      moxml_compat = File.expand_path("compat/opal", moxml_lib)
      Opal.append_path moxml_compat if File.directory?(moxml_compat)
    rescue Gem::MissingSpecError
      # moxml not installed
    end

    # REXML: bundled gem since Ruby 3.4
    rexml_lib = $LOAD_PATH.find do |p|
      File.exist?(File.join(p, "rexml", "document.rb"))
    end
    Opal.append_path rexml_lib if rexml_lib
  end
rescue LoadError
  # Opal not available or incompatible with current Ruby version
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

namespace :spec do
  if defined?(Opal::RSpec::RakeTask)
    desc "Run Opal (JavaScript) tests"
    Opal::RSpec::RakeTask.new(:opal) do |_server, runner|
      runner.default_path = "spec"
      runner.requires = %w[rexml_compat rexml/document rexml/xpath
                           moxml moxml/adapter/rexml spec_helper]
      runner.pattern = "spec/canon/opal_xml_smoke_spec.rb"
    end
  end
end

task default: %i[spec rubocop]
