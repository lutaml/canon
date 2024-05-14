# frozen_string_literal: true

require_relative "c14n/version"
require "nokogiri"

require_relative "c14n/rspec_matchers" if defined?(::RSpec)

module Xml
  # C14n stands for canonicalization
  module C14n
    # Source of XSLT
    # https://emmanueloga.wordpress.com/2009/09/29/pretty-printing-xhtml-with-nokogiri-and-xslt/
    NOKOGIRI_C14N_XSL = <<~XSL
      <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
        <xsl:output method="xml" encoding="ISO-8859-1"/>
        <xsl:param name="indent-increment" select="'   '"/>
        <xsl:template name="newline">
          <xsl:text disable-output-escaping="yes">
      </xsl:text>
        </xsl:template>

        <xsl:template match="comment() | processing-instruction()">
          <xsl:param name="indent" select="''"/>
          <xsl:call-template name="newline"/>
          <xsl:value-of select="$indent"/>
          <xsl:copy />
        </xsl:template>

        <xsl:template match="text()">
          <xsl:param name="indent" select="''"/>
          <xsl:call-template name="newline"/>
          <xsl:value-of select="$indent"/>
          <xsl:value-of select="normalize-space(.)"/>
        </xsl:template>

        <xsl:template match="text()[normalize-space(.)='']"/>

        <xsl:template match="*">
          <xsl:param name="indent" select="''"/>
          <xsl:call-template name="newline"/>
          <xsl:value-of select="$indent"/>
          <xsl:choose>
            <xsl:when test="count(child::*) > 0">
              <xsl:copy>
              <xsl:copy-of select="@*"/>
              <xsl:apply-templates select="*|text()">
                <xsl:with-param name="indent" select="concat ($indent, $indent-increment)"/>
              </xsl:apply-templates>
              <xsl:call-template name="newline"/>
              <xsl:value-of select="$indent"/>
              </xsl:copy>
            </xsl:when>
            <xsl:otherwise>
              <xsl:copy-of select="."/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:template>
      </xsl:stylesheet>
    XSL

    def self.format(xml)
      Nokogiri::XSLT(NOKOGIRI_C14N_XSL)
        .transform(Nokogiri::XML(xml, &:noblanks))
        .to_xml(indent: 2, pretty: true, encoding: "UTF-8")
    end

    class Error < StandardError; end
    # Your code goes here...
  end
end
