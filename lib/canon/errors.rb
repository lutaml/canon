# frozen_string_literal: true

module Canon
  class Error < StandardError; end

  # Error raised when trying to compare objects of different formats
  class CompareFormatMismatchError < Error
    def initialize(format1, format2)
      super("Cannot compare different formats: #{format1} vs #{format2}")
    end
  end
end
