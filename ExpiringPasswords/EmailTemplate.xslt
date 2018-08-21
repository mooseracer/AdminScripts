<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
 
<xsl:output media-type="xml" omit-xml-declaration="yes" />
    <xsl:param name="To"/>
    <xsl:param name="Content"/>
    <xsl:template match="/">
        <html>
            <head>
                <title>Domain Password Expiring</title>
            </head>
            <body>
            <div width="400px">
                <p><xsl:value-of select="$To" />,</p>
                <p></p>
                <p><xsl:value-of select="$Content" /> To avoid log-in issues please change your password as soon as possible.
				</p>
                <p></p>
				<p>To change your password:</p>
				<p><b>Windows 10 Users</b>
				<OL>
					<LI>Press <i>CTRL+ALT+DELETE</i></LI>
					<LI>Choose <i>Change a password...</i></LI>
					<LI>If you are presented with "Change Smart Card Password", click <i>Sign-in options</i> and then click the Key icon.</LI>
					<LI>Enter your current password, enter a new password, and then confirm your new password.</LI>
				</OL>
				</p>
				<p><b>Windows 7 Users</b>
				<OL>
					<LI>Press <i>CTRL+ALT+DELETE</i></LI>
					<LI>Choose <i>Change a password...</i></LI>
					<LI>Enter a new password, and then confirm your new password.</LI>
				</OL>
				<p>An automated system sent this email. If you have any questions or concerns please contact the Service Desk.</p>
				<p></p>
            <Address>
				Thank you,<br />	
				MyCorp Service Desk<br />
				Team Email: Tech.Support@MyCorp.com<br />
            </Address>
        </div>
      </body>
    </html>
    </xsl:template> 
</xsl:stylesheet>