## Must be run from each Domain Controller. NTFS permissions on this file must allow Read & Execute for each DC's computer object,
## and Modify access to the \Locked Out folder.
## Will export to text file list of current locked out users and the machines that last sent the bad password
##
##
Import-Module activedirectory

$DT = [DateTime]::Now.AddHours(-6)
$logName = '{0}LockoutReport.txt' -f "\\server\Reports\" #, $DT.tostring("yyyy-MM-dd")

#Check the log file
$logfile = gci $logName -ErrorAction SilentlyContinue
if ($logfile -eq $null -or (Get-Date).AddMinutes(-15) -gt $logfile.CreationTime) { #If the log is missing, or >15 minutes old, write the header:
    $logfile.CreationTime = Get-Date
    (Get-Date).ToString()+"`t"+$(Hostname) | Out-File -FilePath $logName -Encoding UTF8
    #Generate list of locked out accounts
    $locked = Search-ADAccount -LockedOut -Server $(hostname) | FT -Property Name,LockedOut,Enabled,PasswordExpired,LastLogonDate -AutoSize | Out-String
    if ($locked -eq "") { $locked = "No locked out accounts found on $(hostname).`r`n" }
    $locked | Out-File -FilePath $logname -Append -Encoding UTF8
}

$eventlog = Get-EventLog -LogName 'Security' -InstanceId 4740 -After $DT |
        Select-Object @{
        Name='UserName'
        Expression={$_.ReplacementStrings[0]}
        },
        @{
        Name='WorkstationName'
        Expression={$_.ReplacementStrings[1] -replace '\$$'}
        },TimeGenerated | Out-String
$(Hostname) | Out-File -FilePath $logName -Append -Encoding UTF8
If ($eventlog -eq "" -or $eventlog -eq $null) { $eventlog = "No lockout events.`r`n" }
$eventlog | Out-File -FilePath $logName -Append -Encoding UTF8

# SIG # Begin signature block
# MIIJHAYJKoZIhvcNAQcCoIIJDTCCCQkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUe81DWGKWjAtIUzF0TFktkQqB
# 4KSgggaBMIIGfTCCBWWgAwIBAgIEWIq/9zANBgkqhkiG9w0BAQsFADBcMQswCQYD
# VQQGEwJDQTELMAkGA1UECBMCT04xHjAcBgNVBAoTFUdvdmVybm1lbnQgb2YgT250
# YXJpbzEPMA0GA1UECxMGR08tUEtJMQ8wDQYDVQQLEwZPUFAtQ0EwHhcNMTcwNzEx
# MTcxNjI2WhcNMTkwNzExMTc0NjI2WjCBlDELMAkGA1UEBhMCQ0ExCzAJBgNVBAgT
# Am9uMR4wHAYDVQQKExVHb3Zlcm5tZW50IG9mIE9udGFyaW8xDzANBgNVBAsTBkdP
# LVBLSTEPMA0GA1UECxMGT1BQLUNBMRcwFQYDVQQLEw5TZWN1cmUgRGV2aWNlczEd
# MBsGA1UEAxMUT1BQIENvZGUgU2lnbmluZyAoSCkwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQCxg/JGBSH+cvILnx7FCP8B5iZ7b3dJ6EdKVXafY95iIA+q
# bK4h4WnHyfWTV6eTY0CF7fVUdc5TYhcE8aJ65+7+TXUBwyw9zOQLvua12AHNeBPP
# TLX3swIuYj3Afi4sv3d1QcTQFbuWiSGkvMkND6EikjpL5uc/hRy9gnmV+Z6xgFQR
# qlsWdzvB8e+05GvLg87J4iJiKZGvw7MrKFkbRvY1+fD3zHYSWHXD+HdRSCZOMtE9
# 5yOi5m5bHhOxeTRFSdRhMDryF0UNScKK085ijl5pCgtP2JFrluxI8QPfkd4Pcua/
# 0RuAiE+5IxrDqvgYYs6oVYrKfB0Vl8M8D54cOmPdAgMBAAGjggMMMIIDCDALBgNV
# HQ8EBAMCB4AwHgYDVR0lBBcwFQYIKwYBBQUHAwMGCWCGSAGG+msoATAgBgNVHSAE
# GTAXMAgGBmB8CGVkATALBglgfAhlZAEBAgIwQAYDVR0RBDkwN6A1BgorBgEEAYI3
# FAIDoCcMJUFuZGVyc0NIQSAtIGNoYXJsZXMuai5hbmRlcnNvbkBvcHAuY2EwggHg
# BgNVHR8EggHXMIIB0zCCAR+gggEboIIBF6RvMG0xCzAJBgNVBAYTAkNBMQswCQYD
# VQQIEwJPTjEeMBwGA1UEChMVR292ZXJubWVudCBvZiBPbnRhcmlvMQ8wDQYDVQQL
# EwZHTy1QS0kxDzANBgNVBAsTBk9QUC1DQTEPMA0GA1UEAxMGQ1JMNTg0hnVsZGFw
# Oi8veC5qdXNjZXJ0aWZ5LmNhL2NuPUNSTDU4NCxvdT1PUFAtQ0Esb3U9R08tUEtJ
# LG89R292ZXJubWVudCUyMG9mJTIwT250YXJpbyxzdD1PTixjPUNBP2NlcnRpZmlj
# YXRlUmV2b2NhdGlvbkxpc3SGLWh0dHA6Ly9wa2l3ZWIuanVzY2VydGlmeS5jYS9D
# UkwvcF9DUkxjNTg0LmNybDCBraCBqqCBp4Z7bGRhcDovL3guanVzY2VydGlmeS5j
# YS9jbj1XaW5Db21iaW5lZDEsb3U9T1BQLUNBLG91PUdPLVBLSSxvPUdvdmVybm1l
# bnQlMjBvZiUyME9udGFyaW8sc3Q9T04sYz1DQT9jZXJ0aWZpY2F0ZVJldm9jYXRp
# b25MaXN0hihodHRwOi8vcGtpd2ViLmp1c2NlcnRpZnkuY2EvQ1JML0NSTDEuY3Js
# MCsGA1UdEAQkMCKADzIwMTcwNzExMTcxNjI2WoEPMjAxODEyMDQxNzQ2MjZaMB8G
# A1UdIwQYMBaAFImOCYjtXVNfPKIAT7esJGTzMk8aMB0GA1UdDgQWBBTJgkhRfL9p
# Eeb0v7UYiifs5oHhqTAJBgNVHRMEAjAAMBkGCSqGSIb2fQdBAAQMMAobBFY4LjED
# AgSwMA0GCSqGSIb3DQEBCwUAA4IBAQBJWIG/KDKBgubr9ML0KfossYv1ws70mGUP
# kQLaBO3BT/M3nqm/W+KPvxU/8aYpz4tJaL2z6X63pphz9r+cR7FcOnC5ataxtajG
# Em7fI3O4n0rDD5OYaXhr6RgzCM+zCWwuxzpVIWI9NKHuT/qngn4feOi9/dG9G9EU
# CYCv5U4urX9Y6bQzle3ojoU7kshKYp3rWPQ0xMWDbjLzgoEEtq8El4UVjd7/LGtx
# fTaP0CJ4rpXT/fzedc18Z6ZEVkwhUChWDe6tml06GFDGO7dLT/ECGzco4MRb4eI/
# AIOBald8g53zPSyUWijc8TihkJD/GrVAh6TVk6fkDrtziwR883x4MYICBTCCAgEC
# AQEwZDBcMQswCQYDVQQGEwJDQTELMAkGA1UECBMCT04xHjAcBgNVBAoTFUdvdmVy
# bm1lbnQgb2YgT250YXJpbzEPMA0GA1UECxMGR08tUEtJMQ8wDQYDVQQLEwZPUFAt
# Q0ECBFiKv/cwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFNakwry1ZqCudzoj6E/VT0hD4fb8MA0G
# CSqGSIb3DQEBAQUABIIBADdDUN7hpr6f1SfJiZZXfiDiUMjfJA8QMVTMtRpv3tyl
# nnVDyLdJDhHJmTTu1LXr8h1B8QiSmFGigoUAwGJTdGt4sMzgzamfD/fu9ehR9CtF
# iJrrOyHgSIn0MGB4zSr+cvta88sSU/OVc8ESUSAwgXPV2IeP4ELePF7fx41AinMV
# +cF1cX+o5EET7o9eb+EMo4vM3qdVQYBDtQvjhEB89w9x6+zD3XoecFo11zf3htDQ
# FrxxJR7/3/UfeIk9zjwBgOtHNRiun8F+3vtyfys43Yhir9Qt7GoW/ngmj9czJ6BJ
# ss4yjPi5vuokfqYVp6uqpbRNaPi0OSCGhcoz3+X/g38=
# SIG # End signature block
