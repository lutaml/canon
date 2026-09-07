# frozen_string_literal: true

require "json"

module Canon
  # The only place canon talks to a JSON engine. The yeptris fast path
  # (fused C-API materializer) engages through Yeptris::JSON.load —
  # the strict JSON surface pinned to exact JSON.parse semantics
  # upstream; without the native materializer the stdlib parser
  # serves, unchanged.
  # Errors normalize to JSON::ParserError so canon's rescues hold on
  # both engines.
  module JsonParsing
    module_function

    def parse(json)
      if Canon::YamlBackend.json_yeptris?
        begin
          # The strict JSON surface — spec-pinned to exact JSON.parse
          # semantics upstream, deliberately separate from the YAML
          # (Psych-contract) surface, which applies the YAML 1.1 quirk
          # table to JSON-shaped input.
          ::Yeptris::JSON.load(json)
        rescue ::Yeptris::JSON::ParseError, ::Yeptris::ParseError => e
          raise JSON::ParserError, e.message
        end
      else
        JSON.parse(json)
      end
    end
  end
end
