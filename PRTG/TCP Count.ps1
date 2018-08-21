#Returns counts of TCP connections to specified IP addresses.
$ComputerName = "$($args[0])"

$netsh = Invoke-Command -ComputerName $ComputerName -ScriptBlock {netsh int ipv4 show tcpconnections}
$count1 = ($netsh | select-string "192.168.100.").Count
$count2 = ($netsh | select-string "192.168.200.").Count

$xmlOutput = @"
<prtg>
  <result>
    <channel>Total Connections</channel>
    <value>$($count1 + $count2)</value>
    <unit>#</unit>
    <float>0</float>
  </result>
  <result>
    <channel>GHQ Connections</channel>
    <value>$count1</value>
    <float>0</float>
    <unit>#</unit>
  </result>
  <result>
    <channel>GDC Connections</channel>
    <value>$count2</value>
    <float>0</float>
    <unit>#</unit>
  </result>
</prtg>
"@

Write-Host $xmlOutput #Return
Exit 0