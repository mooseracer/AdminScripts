# Queries the Application log of a remote host for any entries from source 'CryptoBlocker' within the last hour.
# Returns PRTG-friendly XML.
# C Anderson / Dec 2016

Trap {
$xmlOutput = @"
    <prtg>
        <error>
          <text>$($Error[0])</text>
        </error>
    </prtg>
"@

    Write-Host $xmlOutput
    Exit 2
}

$ComputerName = "$($args[0])"

Try {
    $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock {Get-EventLog -LogName Application -Source CryptoBlocker -EntryType Warning -After ((Get-Date).AddMinutes(-60))} -ErrorAction Continue
}
Catch [System.Management.Automation.RemoteException] {
    If ($Error[0].Exception -like '*No matches found*') {
        #Then it's ok.
    }
    Else {
        $xmlOutput = @"
    <prtg>
        <error>
            <text>$($Error[0])</text>
        </error>
    </prtg>
"@
        Write-Host $xmlOutput
        Exit 2
    }
}

#CryptoLocker entries found? Output how many, and the text of the most recent entry.
If ($result) {
	$Count = $result | Measure-Object | Select -ExpandProperty Count
$xmlOutput = @"
    <prtg>
        <result>
          <channel>Hourly Count</channel>
          <value>$Count</value>
          <unit>#</unit>
          <float>0</float>
        </result>
        <text>$($result[0].Message)</text>
    </prtg>
"@
}
#If nothing was found, output OK
Else {
$xmlOutput = @"
    <prtg>
        <result>
          <channel>Hourly Count</channel>
          <value>0</value>
          <unit>#</unit>
          <float>0</float>
        </result>
        <text>OK</text>
    </prtg>
"@
}

Write-Host $xmlOutput
Exit 0

