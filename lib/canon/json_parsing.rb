# frozen_string_literal: true

require "json"

module Canon
  # The only place canon talks to a JSON engine. The yeptris fast path
  # (fused C-API materializer, on par with the stdlib C extension)
  # engages through Yeptris::YAML.load's JSON auto-detection; without
  # the native materializer the stdlib parser serves, unchanged.
  # Errors normalize to JSON::ParserError so canon's rescues hold on
  # both engines.
  module JsonParsing
    module_function

    def parse(json)
      if Canon::YamlBackend.yeptris_native?
        begin
          ::Yeptris::YAML.load(json)
        rescue ::Yeptris::ParseError, ::FFI::NullPointerError => e
          raise JSON::ParserError, e.message
        end
      else
        JSON.parse(json)
      end
    end
  end
end
