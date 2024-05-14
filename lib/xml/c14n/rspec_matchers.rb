# frozen_string_literal: true

require "xml-c14n" unless defined?(::Xml::C14n)
require "compare-xml"

begin
  require "rspec/expectations"
rescue LoadError
end

module Xml
  module C14n
    module RSpecMatchers
      class AnalogousMatcher
        def initialize(expected)
          @expected = expected
          @result = nil
        end

        def matches?(target)
          @target = target

          @result = CompareXML.equivalent?(
            Nokogiri::XML(@target),
            Nokogiri::XML(@expected),
            { collapse_whitespace: true,
              ignore_attr_order: true,
              verbose: true },
          )

          @result.empty?
        end

        def failure_message
          index = 0
          @result.map do |hash|
            index += 1
            "DIFF #{index}: expected node: #{hash[:node1]}\n" \
                   "        actual node  : #{hash[:node2]}\n" \
                   "        diff from    : #{hash[:diff1]}\n" \
                   "        diff to      : #{hash[:diff2]}\n"
          end.join("\n")
        end

        def failure_message_when_negated
          ["expected:", @target.to_s, "not be analogous with:",
           @expected.to_s].join("\n")
        end

        def diffable
          true
        end
      end

      def be_analogous_with(expected)
        AnalogousMatcher.new(expected)
      end

      if defined?(::RSpec)
        RSpec.configure do |config|
          config.include(Xml::C14n::RSpecMatchers)
        end
      end
    end
  end
end
