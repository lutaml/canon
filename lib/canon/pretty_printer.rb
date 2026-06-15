# frozen_string_literal: true

module Canon
  # Pretty-printers that emit format-aware, fixture-ready output.
  module PrettyPrinter
    autoload :Html, "canon/pretty_printer/html"
    autoload :HtmlVoidElements, "canon/pretty_printer/html_void_elements"
    autoload :Json, "canon/pretty_printer/json"
    autoload :Xml, "canon/pretty_printer/xml"
    autoload :XmlNormalized, "canon/pretty_printer/xml_normalized"
  end
end
