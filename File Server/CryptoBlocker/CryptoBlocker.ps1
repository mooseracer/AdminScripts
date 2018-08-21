<#
Executed by FSRM when the CryptoBlocker file screen is triggered. Writes an
event to the Application log containing the username who triggered FSRM,
the path of the file, and any IP addresses + hostnames of currently connected
sessions from that username.
#>

Param (
    [Parameter(Position=0)]
    [String]
    $UserName
    ,
    [Parameter(Position=1)]
    [String]
    $Path
)

#Strip off the domain
$UserName = $UserName.Split("\")[-1]

#Look up current network session(s) with $UserName
$sessions = & NET SESSION | Select-String $UserName

$AddressPairs = @()
Foreach ($session in $sessions) {
    If ($session -match '(\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b)') {$IP = $Matches[1]}
    #Resolve IP
    If ($IP) {
        $hostname = [System.Net.Dns]::GetHostbyAddress($IP).HostName
    }
    Else {$hostname = ''}

    $AddressPair = New-Object -TypeName PSObject
    $AddressPair | Add-Member -MemberType NoteProperty -Name 'IP' -Value $IP
    $AddressPair | Add-Member -MemberType NoteProperty -Name 'Hostname' -Value $hostname
    $AddressPairs += $AddressPair
}

$EventText = "FSRM blocked a file operation:`n$UserName attempted to save $Path`n`nUser is currently connected from:`n"
Foreach ($Pair in $AddressPairs) {
    $EventText += "$($Pair.IP) ($($Pair.Hostname))"
}

Write-EventLog -Message $EventText -LogName Application -Source CryptoBlocker -EventId 8215 -EntryType Warning -Category 0


# SIG # Begin signature block
# MIIHhQYJKoZIhvcNAQcCoIIHdjCCB3ICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUW3njNUMkj08vk6kwbL0L3pNV
# TyWgggVrMIIFZzCCBNCgAwIBAgIEVMHpTzANBgkqhkiG9w0BAQUFADBcMQswCQYD
# VQQGEwJDQTELMAkGA1UECBMCT04xHjAcBgNVBAoTFUdvdmVybm1lbnQgb2YgT250
# YXJpbzEPMA0GA1UECxMGR08tUEtJMQ8wDQYDVQQLEwZPUFAtQ0EwHhcNMTUxMjEx
# MTI1NzM4WhcNMTcxMjExMTMyNzM4WjCBlDELMAkGA1UEBhMCQ0ExCzAJBgNVBAgT
# Am9uMR4wHAYDVQQKExVHb3Zlcm5tZW50IG9mIE9udGFyaW8xDzANBgNVBAsTBkdP
# LVBLSTEPMA0GA1UECxMGT1BQLUNBMRcwFQYDVQQLEw5TZWN1cmUgRGV2aWNlczEd
# MBsGA1UEAxMUT1BQIENvZGUgU2lnbmluZyAoSCkwgZ8wDQYJKoZIhvcNAQEBBQAD
# gY0AMIGJAoGBALhsXlj9FKFGJLH6rxpXSWAFv4J42iFVk0h13NTOXsXeui2hRZhd
# FR8h7394te8RjQM5gyeDQd7qOfrnaYnsme3kPT3DIWbA9PAkbYGkMswAe73ZpKb/
# 75OH7VXxEmulOmQOMmaAk8NJp50BRCWbrNZoVNpAN42yS8xRwkl9G+hZAgMBAAGj
# ggL7MIIC9zALBgNVHQ8EBAMCB4AwHgYDVR0lBBcwFQYIKwYBBQUHAwMGCWCGSAGG
# +msoATAgBgNVHSAEGTAXMAgGBmB8CGVkATALBglgfAhlZAEBAgIwQAYDVR0RBDkw
# N6A1BgorBgEEAYI3FAIDoCcMJUFuZGVyc0NIQSAtIGNoYXJsZXMuai5hbmRlcnNv
# bkBvcHAuY2EwggHPBgNVHR8EggHGMIIBwjCCAR+gggEboIIBF6RvMG0xCzAJBgNV
# BAYTAkNBMQswCQYDVQQIEwJPTjEeMBwGA1UEChMVR292ZXJubWVudCBvZiBPbnRh
# cmlvMQ8wDQYDVQQLEwZHTy1QS0kxDzANBgNVBAsTBk9QUC1DQTEPMA0GA1UEAxMG
# Q1JMNTE0hnVsZGFwOi8veC5qdXNjZXJ0aWZ5LmNhL2NuPUNSTDUxNCxvdT1PUFAt
# Q0Esb3U9R08tUEtJLG89R292ZXJubWVudCUyMG9mJTIwT250YXJpbyxzdD1PTixj
# PUNBP2NlcnRpZmljYXRlUmV2b2NhdGlvbkxpc3SGLWh0dHA6Ly9wa2l3ZWIuanVz
# Y2VydGlmeS5jYS9DUkwvcF9DUkxjNTE0LmNybDCBnKCBmaCBloZrbGRhcDovL3gu
# anVzY2VydGlmeS5jYS9vdT1PUFAtQ0Esb3U9R08tUEtJLG89R292ZXJubWVudCUy
# MG9mJTIwT250YXJpbyxzdD1PTixjPUNBP2NlcnRpZmljYXRlUmV2b2NhdGlvbkxp
# c3SGJ2h0dHA6Ly9wa2l3ZWIuanVzY2VydGlmeS5jYS9DUkwvQ1JMLmNybDArBgNV
# HRAEJDAigA8yMDE1MTIxMTEyNTczOFqBDzIwMTcwNTA2MDUyNzM4WjAfBgNVHSME
# GDAWgBS119P1rm2a2xP+mu44wks885hZMjAdBgNVHQ4EFgQURha/7buox3HTAo7w
# 7pPw542yGpgwCQYDVR0TBAIwADAZBgkqhkiG9n0HQQAEDDAKGwRWOC4xAwIEsDAN
# BgkqhkiG9w0BAQUFAAOBgQChlcCK+nuMnDW78sK/owv3BHFu8hGaQLzzRmm+yJUd
# RJWljugorDkeS0rKnzoZ1bm2vPo3Iqyh4JaiSM7I1kIcTYNXw0weZ2dxke+zWRUr
# jpMqm/dTzGmgbNt3Nr9+GJZLYkxb9Yro4J3QCC/W2TQIZdbtYVraadLe0zyHJX76
# XzGCAYQwggGAAgEBMGQwXDELMAkGA1UEBhMCQ0ExCzAJBgNVBAgTAk9OMR4wHAYD
# VQQKExVHb3Zlcm5tZW50IG9mIE9udGFyaW8xDzANBgNVBAsTBkdPLVBLSTEPMA0G
# A1UECxMGT1BQLUNBAgRUwelPMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQow
# CKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcC
# AQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRLdMBrUpPFiw4iDK8n
# qvNtFtu8OjANBgkqhkiG9w0BAQEFAASBgJMdxqhWolrPl70LjZHb2Pkdlb6RKRRn
# prQNrUuDJ9i7U+fOoRpvJf82ZyoRfIenEX9MQDno83hDXr35Wx0wBSG9B+kFdIuf
# fbEWKOGn1lI4ikTzWp0Jp/uDs+PFisRQMo9yZnoMLJLsYcUActMrtTwiC50SZI8S
# U1bCT347dSJS
# SIG # End signature block
