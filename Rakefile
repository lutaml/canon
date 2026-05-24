# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

begin
  require "opal/rspec/rake_task"
rescue LoadError
  # Opal not available or incompatible with current Ruby version
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

namespace :spec do
  if defined?(Opal::RSpec::RakeTask)
    desc "Run Opal (JavaScript) tests"
    Opal::RSpec::RakeTask.new(:opal) do |server, runner|
      server.append_path "lib"
      runner.default_path = "spec"
      runner.pattern = "spec/canon/opal_xml_smoke_spec.rb"
    end
  end
end

task default: %i[spec rubocop]
