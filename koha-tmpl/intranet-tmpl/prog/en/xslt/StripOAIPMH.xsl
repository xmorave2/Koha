<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:oai="http://www.openarchives.org/OAI/2.0/"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
    <!-- NOTE: This XSLT strips the OAI-PMH wrapper from the metadata. -->

    <!-- Match the root oai:record element -->
    <xsl:template match="oai:record">
        <!-- Apply templates only to the child metadata element(s) -->
        <xsl:apply-templates select="oai:metadata" />
    </xsl:template>

    <!-- Matches an oai:metadata element -->
    <xsl:template match="oai:metadata">
        <!-- Create a copy of child attributes and nodes -->
        <xsl:apply-templates select="@* | node()" />
    </xsl:template>

    <!-- Identity transformation: this template copies attributes and nodes -->
    <xsl:template match="@* | node()">
        <!-- Create a copy of this attribute or node -->
        <xsl:copy>
            <!-- Recursively apply this template to the attributes and child nodes of this element -->
            <xsl:apply-templates select="@* | node()" />
        </xsl:copy>
    </xsl:template>
</xsl:stylesheet>
