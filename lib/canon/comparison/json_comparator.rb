# frozen_string_literal: true

require "json"

module Canon
  module Comparison
    # JSON comparison class
    # Delegates to RubyObjectComparator for actual comparison logic
    class JsonComparator
      DEFAULT_OPTS = {
        verbose: false,
        match_profile: nil,
        match: nil,
        preprocessing: nil,
        global_profile: nil,
        global_options: nil,
        diff: nil,
      }.freeze

      class << self
        def parse(obj)
          parse_json(obj)
        end

        def equivalent?(json1, json2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          match_opts_hash = MatchOptions::Json.resolve(
            format: :json,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          opts[:match_opts] = match_opts_hash

          obj1 = parse_json(json1)
          obj2 = parse_json(json2)

          differences = []
          result = RubyObjectComparator.compare_objects(obj1, obj2, opts,
                                                        differences, "")

          if opts[:verbose]
            json_str1 = obj1.is_a?(String) ? obj1 : JSON.pretty_generate(obj1)
            json_str2 = obj2.is_a?(String) ? obj2 : JSON.pretty_generate(obj2)

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: [json_str1, json_str2],
              format: :json,
              match_options: match_opts_hash,
            )
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        def parse_json(obj)
          return obj unless obj.is_a?(String)

          begin
            JSON.parse(obj)
          rescue JSON::ParserError
            obj
          end
        end
      end
    end
  end
end
