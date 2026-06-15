# frozen_string_literal: true

module Canon
  # HTML-specific functionality for Canon.
  #
  # Children are autoloaded — never `require_relative` them.
  module Html
    autoload :DataModel, "canon/html/data_model"
  end
end
