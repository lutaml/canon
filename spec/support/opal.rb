# frozen_string_literal: true

# Opal runtime patches for canon specs.
#
# Canon uses XmlBackend to select the appropriate code path.
# Under Opal, moxml/REXML is used exclusively.

# Ensure moxml uses REXML adapter
Moxml.configure do |config|
  config.adapter = :rexml
  config.strict_parsing = false
  config.default_encoding = "UTF-8"
  config.entity_load_mode = :optional
end
