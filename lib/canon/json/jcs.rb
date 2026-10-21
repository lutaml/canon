# frozen_string_literal: true

require "json"

module Canon
  module Json
    # RFC 8785 — the I-JSON Canonicalization Scheme (JCS).
    #
    # Produces the canonical JSON form the RFC defines: UTF-8, object
    # keys sorted by their UTF-16 code units, ECMAScript
    # `Number::toString` number serialization, RFC 8785 §3.2.2.2
    # string escaping, and no insignificant whitespace. The result is
    # byte-stable across platforms and suitable for hashing and
    # signing.
    #
    # Input must be I-JSON (RFC 7493): valid UTF-8 without lone
    # surrogates, no duplicate object keys, numbers expressible as
    # IEEE 754 doubles. Violations raise {Canon::Json::JCS::Error}.
    module JCS
      class Error < ::Canon::Error; end

      module_function

      # @param json [String, Hash, Array] an I-JSON document or an
      #   already-parsed Ruby object graph
      # @return [String] the RFC 8785 canonical form
      def canonicalize(json)
        doc = json.is_a?(String) ? ::JSON.parse(json) : json
        serialize(doc)
      end

      def serialize(value)
        out = +""
        write(value, out)
        out
      end

      def write(value, out)
        case value
        when Hash
          write_object(value, out)
        when Array
          out << "["
          value.each_with_index do |item, i|
            out << "," if i.positive?
            write(item, out)
          end
          out << "]"
        when String
          out << escape_string(value)
        when Integer
          out << ijson_integer(value)
        when Float
          out << es6_number(value)
        when true then out << "true"
        when false then out << "false"
        when nil then out << "null"
        else
          raise Error, "JCS input must be JSON data; got #{value.class}"
        end
      end

      def write_object(hash, out)
        out << "{"
        hash.keys.sort_by { |key| utf16_code_units(key) }
          .each_with_index do |key, i|
          out << "," if i.positive?
          out << escape_string(key) << ":"
          write(hash[key], out)
        end
        out << "}"
      end

      # RFC 8785 §3.2.2.2 — the JSON.stringify escaping set: short
      # forms for \b \t \n \f \r, two-hex lowercase \u00xx for the
      # remaining C0 controls, \" and \\; every other code point is
      # emitted verbatim as UTF-8 (DEL U+007F is NOT escaped).
      SHORT_ESCAPES = {
        0x08 => "\\b", 0x09 => "\\t", 0x0A => "\\n",
        0x0C => "\\f", 0x0D => "\\r"
      }.freeze

      def escape_string(string)
        out = +"\""
        string.each_codepoint do |cp|
          out << case cp
                 when 0x22 then "\\\""
                 when 0x5C then "\\\\"
                 when 0x08, 0x09, 0x0A, 0x0C, 0x0D then SHORT_ESCAPES[cp]
                 when 0x00..0x1F then format("\\u%04x", cp)
                 else
                   cp.chr(Encoding::UTF_8)
                 end
        end
        out << "\""
      rescue ArgumentError
        raise Error, "JCS input must be valid UTF-8 without lone surrogates"
      end

      # RFC 8785 §2.1 (I-JSON): numbers must be expressible as IEEE
      # 754 doubles; anything wider is a contract violation, not a
      # rounding opportunity.
      def ijson_integer(value)
        if value.abs > 9_007_199_254_740_992 # 2**53
          raise Error,
                "JCS input must be I-JSON: #{value} exceeds the IEEE 754 " \
                "double range for exact integers"
        end
        value.to_s
      end

      # ECMA-262 `Number::toString` (the JSON.stringify number shape):
      # shortest-round-trip digits formatted per the spec's fixed /
      # exponential cases, with the boundaries 1e-6 (inclusive fixed
      # on the small side) and 1e21 (exclusive fixed on the large
      # side). -0.0 serializes as "0"; non-finite values are not
      # JSON data and raise.
      def es6_number(value)
        raise Error, "JCS input must be finite numbers" if
          value.nan? || value.infinite?
        return "0" if value.zero?

        sign = value.negative? ? "-" : ""
        s = value.abs.to_s
        if (m = s.match(/\A(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?\z/))
          int_part = m[1]
          frac = m[2] || ""
          exp = m[3] ? m[3].to_i : 0
          digits = (int_part + frac).sub(/\A0+/, "")
          k = int_part.length + exp - (int_part.length + frac.length - digits.length)
          digits = digits.sub(/0+\z/, "")
          digits = "0" if digits.empty?
          n = digits.length
          return sign + format_digits(digits, n, k)
        end
        # Float#to_s always matches above; the fallthrough is defensive
        raise Error, "unserializable number: #{s}"
      end

      # n and k are ECMA-262 7.1.12.1's own notation (digit count and
      # the decimal-point position); renamed parameters would lose the
      # spec mapping.
      # rubocop:disable Naming/MethodParameterName
      def format_digits(digits, n, k)
        if k <= 0
          # 0.s × 10^k: fixed for -6 < k <= 0 ("0." + zeros + digits),
          # exponential at k <= -6 (values below 1e-6, ECMA boundary)
          return exp_form(digits, k) if k <= -6

          ["0.", "0" * -k, digits].join
        elsif k >= n
          return digits if k == n

          # integer-shaped: pad zeros while k <= 21 ("1" + twenty
          # zeros for 1e20); exponential above (1e21 -> "1e+21")
          return exp_form(digits, k) if k > 21

          digits + ("0" * (k - n))
        else
          # 0 < k < n: the point sits inside the digit string
          "#{digits[0, k]}.#{digits[k..]}"
        end
      end

      def exp_form(digits, k)
        mantissa = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
        e = k - 1
        "#{mantissa}e#{e.negative? ? '-' : '+'}#{e.abs}"
      end
      # rubocop:enable Naming/MethodParameterName

      # RFC 8785 §3.2.3: keys sort by their UTF-16 code units (the
      # ECMAScript array sort). Ruby string <=> compares by codepoint,
      # which diverges from UTF-16 order above the BMP (astral planes
      # sort after U+E000..U+FFFF in UTF-16 order).
      def utf16_code_units(string)
        string.encode("UTF-16LE").unpack("v*")
      rescue Encoding::UndefinedConversionError
        raise Error,
              "JCS keys must be valid UTF-16 (no lone surrogates): " \
              "#{string.inspect}"
      end
    end
  end
end
