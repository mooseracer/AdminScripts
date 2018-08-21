<#
Configures the File Server Resource Manager (FSRM) role for file screens to block the creation of any
files that match the filters in CryptoBlocker_extensions.txt. Events are written to the Application log
for each file blocked.

File extension blacklist and deployment code adapted from https://fsrm.experiant.ca/

C Anderson / November 2016

#>
################################ Functions ################################
Function New-CBArraySplit {

    param(
        $extArr,
        $depth = 1
    )

    $extArr = $extArr | Sort-Object -Unique

    # Concatenate the input array
    $conStr = $extArr -join ','
    $outArr = @()

    # If the input string breaks the 4Kb limit
    If ($conStr.Length -gt 4096) {
        # Pull the first 4096 characters and split on comma
        $conArr = $conStr.SubString(0,4096).Split(',')
        # Find index of the last guaranteed complete item of the split array in the input array
        $endIndex = [array]::IndexOf($extArr,$conArr[-2])
        # Build shorter array up to that indexNumber and add to output array
        $shortArr = $extArr[0..$endIndex]
        $outArr += [psobject] @{
            index = $depth
            array = $shortArr
        }

        # Then call this function again to split further
        $newArr = $extArr[($endindex + 1)..($extArr.Count -1)]
        $outArr += New-CBArraySplit $newArr -depth ($depth + 1)
        
        return $outArr
    }
    # If the concat string is less than 4096 characters already, just return the input array
    Else {
        return [psobject] @{
            index = $depth
            array = $extArr
        }  
    }
}
################################ End of Functions ################################

$workingDir = "C:\ProgramData\CryptoBlocker"
$monitoredExtensions = Get-Content $workingDir\CryptoBlocker_extensions.txt
$drives = Get-WmiObject Win32_LogicalDisk -Filter 'DriveType = "3"' | Select -ExpandProperty DeviceID
$fileGroupName = "CryptoBlockerGroup"
$fileTemplateName = "CryptoBlockerTemplate"
$fileScreenName = "CryptoBlockerScreen"
$cmdConfFilename = "$workingDir\CryptoBlocker_config.ini"

#FSRM & OS version check
$majorVer = [System.Environment]::OSVersion.Version.Major
$minorVer = [System.Environment]::OSVersion.Version.Minor
Write-Host "Checking File Server Resource Manager.."
Import-Module ServerManager
if ($majorVer -ge 6) {
    $checkFSRM = Get-WindowsFeature -Name FS-Resource-Manager

    if ($minorVer -ge 2 -and $checkFSRM.Installed -ne "True")
    {
        # Server 2012
        Write-Host "FSRM not found.. Installing (2012).."
        Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
        #Give it a minute
        Start-Sleep -s 60
    }
    elseif ($minorVer -ge 1 -and $checkFSRM.Installed -ne "True")
    {
        # Server 2008 R2
        Write-Host "FSRM not found.. Installing (2008 R2).."
        Add-WindowsFeature FS-FileServer, FS-Resource-Manager
        #Give it a minute
        Start-Sleep -s 60
    }
    elseif ($checkFSRM.Installed -ne "True")
    {
        # Server 2008
        Write-Host "FSRM not found.. Installing (2008).."
        &servermanagercmd -Install FS-FileServer FS-Resource-Manager
        #Give it a minute
        Start-Sleep -s 60
    }
}
else {
    # Assume Server 2003
    Write-Host "Other version of Windows detected! Quitting.."
    return
}

#Generate filescrn.exe config file
$filescrnConfig = @'
Notification=C
RunLimitInterval=0
Account=LocalSystem
Command=C:\Windows\system32\WindowsPowershell\V1.0\powershell.exe

'@
$filescrnConfig += "Arguments=-File $workingDir\CryptoBlocker.ps1 [Source Io Owner] [Source File Path]"
$filescrnConfig | Out-File $cmdConfFilename -Encoding unicode -Force


# Split the $monitoredExtensions array into fileGroups of less than 4kb to allow processing by filescrn.exe
$fileGroups = New-CBArraySplit $monitoredExtensions
ForEach ($group in $fileGroups) {
    $group | Add-Member -MemberType NoteProperty -Name fileGroupName -Value "$FileGroupName$($group.index)"
}

# Perform these steps for each of the 4KB limit split fileGroups
ForEach ($group in $fileGroups) {
    Write-Host "Adding/replacing File Group [$($group.fileGroupName)] with monitored file [$($group.array -Join ",")].."
    &filescrn.exe filegroup Delete "/Filegroup:$($group.fileGroupName)" /Quiet
    &filescrn.exe Filegroup Add "/Filegroup:$($group.fileGroupName)" "/Members:$($group.array -Join '|')"
}


Write-Host "Adding/replacing File Screen Template [$fileTemplateName] with Command Notification [$cmdConfFilename].."
&filescrn.exe Template Delete /Template:$fileTemplateName /Quiet
# Build the argument list with all required fileGroups
$screenArgs = 'Template','Add',"/Template:$fileTemplateName","/Add-Notification:C,$cmdConfFilename"
ForEach ($group in $fileGroups) {
    $screenArgs += "/Add-Filegroup:$($group.fileGroupName)"
}
&filescrn.exe $screenArgs

Write-Host "Adding/replacing File Screens.."
$drives | % {
    Write-Host "`tAdding/replacing File Screen for [$_] with Source Template [$fileTemplateName].."
    &filescrn.exe Screen Delete "/Path:$_" /Quiet
    &filescrn.exe Screen Add "/Path:$_" "/SourceTemplate:$fileTemplateName"
}

#Exclude RDFA folders
If (Test-Path "D:\RDFA") { $RDFA = "D:\RDFA" }
ElseIf (Test-Path "E:\RDFA") { $RDFA = "E:\RDFA" }
ElseIf (Test-Path "F:\RDFA") { $RDFA = "F:\RDFA" }
If ($RDFA) {
    $excludeCmd = "Exception Add /Path:$RDFA "
    Foreach ($group in $fileGroups) {
        $excludeCmd += "/a:$($group.fileGroupName) "
    }
    cmd.exe /c "filescrn.exe $excludeCmd"
}

#Create a new Event Log source
New-EventLog -LogName Application -Source CryptoBlocker -ErrorAction SilentlyContinue

#Check for success/failure
$FSRMcheck = & filescrn screen list 2>&1
If ((($FSRMcheck | Select-String "CryptoBlocker").Count) -lt 2) {
    Write-Host "$($env:computername) - CryptoBlocker file screen not detected" -ForegroundColor White -BackgroundColor Red
}

# SIG # Begin signature block
# MIIJHAYJKoZIhvcNAQcCoIIJDTCCCQkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUukiVYhdlU5aWqskG7FLulkge
# Y+WgggaBMIIGfTCCBWWgAwIBAgIEWIq/9zANBgkqhkiG9w0BAQsFADBcMQswCQYD
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFJL4ftLnAEiqvw8r88jWSmI/6+6xMA0G
# CSqGSIb3DQEBAQUABIIBAJPGwSgm/VDsvJNxodgBarBcKCqnM8g8L/kHbd9Yj1lg
# SfFx5/giwhXBvtQi5VbGjlThfitPxt5uV9TG0HqkuIgJVE0likhQYmUa4MueumSE
# V8dIgEjBcWmOIux4UgRXgWBu9wjKKyKxVCipbqhCR52Y+WPdzJp6Znl1CDdmK1IY
# 6iDQnmhOjAql1CZBi89mOP/VGZ/iPQar32pTaeJ/EFX3tvwlrd6mftyIbi+WLt4p
# 3qDiu1i5taYkrK0IZIH+dDqMSuXfyf6+zNj1lk9Y6JYQvpweUFqu2z09fDfqUXTy
# dkZlAB/hkMRLhHcnrsW6fxc8Ups0dc5ztX9UBgv6+JA=
# SIG # End signature block
