# frozen_string_literal: true

require "yaml"

module Canon
  # The only place canon talks to a YAML engine. All string loads go
  # through safe_load here (see XmlParsing for the XML equivalent);
  # YAML.dump stays on Psych everywhere — canonical output bytes are
  # canon's product and the writers differ.
  module YamlParsing
    module_function

    # Psych::safe_load semantics. yeptris is safe-by-default plain
    # data with Symbol/Date/Time built in (aliases resolve), so the
    # permitted-class list is inherently satisfied; parse failures are
    # normalized to Psych::SyntaxError so canon's rescues hold on both
    # engines. Canon always resolves anchors (aliases: true at every
    # call site) — a canonicalizer treats anchors as content: yeptris
    # resolves them unconditionally, so :true keeps both engines
    # behavior-identical.
    def safe_load(yaml, permitted_classes: [Symbol, Date, Time],
                  aliases: true)
      if YamlBackend.yeptris?
        begin
          ::Yeptris::YAML.load(yaml)
        rescue ::Yeptris::ParseError => e
          raise Psych::SyntaxError.new(nil, 0, 0, 0, e.message, "")
        end
      else
        YAML.safe_load(yaml, permitted_classes: permitted_classes,
                             aliases: aliases)
      end
    end
  end
end
