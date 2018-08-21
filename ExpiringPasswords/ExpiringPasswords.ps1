<#
Notifies users whose domain passwords are expiring. Provides instructions for changing the password.

Emails are sent using the two .xslt templates, depending on whether user has an AirWatch account or not.

Emailed users are tracked in NotifiedUsers.txt; entries over 6 days old are purged.

C Anderson / October 2014

#>

Param([switch]$VerboseLog)

#-------------------------------------------------
# Send-HTMLFormattedEmail
# http://poshcode.org/1035
#-------------------------------------------------
# Usage:	Send-HTMLFormattedEmail -?
#-------------------------------------------------
function Send-HTMLFormattedEmail {
	<# 
	.Synopsis
    	Used to send an HTML Formatted Email.
    .Description
    	Used to send an HTML Formatted Email that is based on an XSLT template.
	.Parameter To
		Email address or addresses for whom the message is being sent to.
		Addresses should be seperated using ;.
	.Parameter ToDisName
		Display name for whom the message is being sent to.
	.Parameter CC
		Email address if you want CC a recipient.
		Addresses should be seperated using ;.
	.Parameter BCC
		Email address if you want BCC a recipient.
		Addresses should be seperated using ;.
	.Parameter From
		Email address for whom the message comes from.
	.Parameter FromDisName
		Display name for whom the message comes from.
	.Parameter Subject
		The subject of the email address.
	.Parameter Content
		The content of the message (to be inserted into the XSL Template).
	.Parameter Relay
		FQDN or IP of the SMTP relay to send the message to.
	.XSLPath
		The full path to the XSL template that is to be used.
	#>
    param(
		[Parameter(Mandatory=$True)][String]$To,
		[Parameter(Mandatory=$True)][String]$ToDisName,
		[String]$CC,
		[String]$BCC,
		[Parameter(Mandatory=$True)][String]$From,
		[Parameter(Mandatory=$True)][String]$FromDisName,
		[Parameter(Mandatory=$True)][String]$Subject,
		[Parameter(Mandatory=$True)][String]$Content,
		[Parameter(Mandatory=$True)][String]$Relay,
		[Parameter(Mandatory=$True)][String]$XSLPath
        )
    
    try {
        #Load Cpi.Net.SecureMail
        $dllpath = 'D:\Reports\ExpiringPasswords\Cpi.Net.SecureMail.dll'
        [Reflection.Assembly]::LoadFile($dllpath) | Out-Null

        #Look up the Signing Certificate
        $cert = (dir Cert:\localmachine\my | Sort-Object -Descending -Property NotAfter)[0]

        # Load XSL Argument List
        $XSLArg = New-Object System.Xml.Xsl.XsltArgumentList
        $XSLArg.Clear() 
        $XSLArg.AddParam("To", $Null, $ToDisName)
        $XSLArg.AddParam("Content", $Null, $Content)

        # Load Documents
        $BaseXMLDoc = New-Object System.Xml.XmlDocument
        $BaseXMLDoc.LoadXml("<root/>")

        $XSLTrans = New-Object System.Xml.Xsl.XslCompiledTransform
        $XSLTrans.Load($XSLPath)

        #Perform XSL Transform
        $FinalXMLDoc = New-Object System.Xml.XmlDocument
        $MemStream = New-Object System.IO.MemoryStream
     
        $XMLWriter = [System.Xml.XmlWriter]::Create($MemStream)
        $XSLTrans.Transform($BaseXMLDoc, $XSLArg, $XMLWriter)

        $XMLWriter.Flush()
        $MemStream.Position = 0
     
        # Load the results
        $FinalXMLDoc.Load($MemStream) 
        $Body = $FinalXMLDoc.Get_OuterXML()

		# Create Message Object
        $Message = New-Object Cpi.Net.SecureMail.SecureMailMessage
		
		# Now Populate the Message Object.
        $Message.Subject = $Subject
        $Message.Body = $Body
        $Message.IsBodyHTML = $True
		
		# Add From
        $MessFrom = New-Object Cpi.Net.SecureMail.SecureMailAddress $From, $FromDisName, $null, $cert
		$Message.From = $MessFrom

		# Add To
		$To = $To.Split(";") # Make an array of addresses.
		$To | foreach {$Message.To.Add((New-Object Cpi.Net.SecureMail.SecureMailAddress $_.Trim()))} # Add them to the message object.
		
		# Add CC
		if ($CC){
			$CC = $CC.Split(";") # Make an array of addresses.
			$CC | foreach {$Message.CC.Add((New-Object Cpi.Net.SecureMail.SecureMailAddress $_.Trim()))} # Add them to the message object.
			}

		# Add BCC
		if ($BCC){
			$BCC = $BCC.Split(";") # Make an array of addresses.
			$BCC | foreach {$Message.BCC.Add((New-Object Cpi.Net.SecureMail.SecureMailAddress $_.Trim()))} # Add them to the message object.
			}

        # Digitally Sign the Message
        $Message.IsEncrypted = $false
        $Message.IsSigned = $true
     
        # Create SMTP Client
        $Client = New-Object System.Net.Mail.SmtpClient $Relay

        # Send The Message
        $Client.Send($Message)
    }  
    catch {
		throw $_
    }   
}

#**** MAIN ****

Import-Module ActiveDirectory


#Admin variables
$DaysWarning = 5
$server = 'mycorp.com' #Any/all domain controllers
$workingDir = '\\server\ExpiringPasswords'
$NotifiedUsersPath = "$workingDir\NotifiedUsers.txt"
$errorLog = "$workingDir\errors.log"
If ($VerboseLog) { $errorLog = "$workingDir\errorsVerbose.log" }
If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Startup" | Out-File $errorLog -Append }

#Maximum password age
$domain = [ADSI]"WinNT://$env:userdomain"
$MaxPasswordAge = ($domain.MaxPasswordAge.Value)/86400

If ($MaxPasswordAge -eq 0 -or $MaxPasswordAge -eq $null) { $MaxPasswordAge = 60 }
If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Max password age: $MaxPasswordAge" | Out-File $errorLog -Append }

#Clean up $NotifiedUsers of anyone added over 6 days ago
$NewNotifiedUsers = @()
$NotifiedUsers = Get-Content $NotifiedUsersPath
Foreach ($entry in $NotifiedUsers) {
    If ($entry -eq "" -or $entry -eq $null) {
        Continue
    }
    $sentDate = Get-Date -UFormat ($entry.Split(",")[-1])
    #If it's within the last 6 days keep the entry
    If ((Get-Date).AddDays(-6) -le $sentDate) {
        $NewNotifiedUsers += $entry
    }
}
$NewNotifiedUsers | Out-File $NotifiedUsersPath -Force
$NotifiedUsers = $NewNotifiedUsers
$emailedUsers = 0

#If PasswordLastSet is this between these dates then the user is getting an expiration notification
$PasswordWarning = (Get-Date).AddDays(-1 * ($MaxPasswordAge - $DaysWarning))
$PasswordExpired = (Get-Date).AddDays(-1 * ($MaxPasswordAge))
If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Password warning: $PasswordWarning" | Out-File $errorLog -Append }
If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Password expired: $PasswordExpired" | Out-File $errorLog -Append }


#Get a list of users that have an expiring password
#Regular users
$searchBase = 'ou=End-Users,ou=Users,ou=MyCorp,DC=MyCorp,DC=com'
$users = Get-ADUser -Server $server -SearchBase $searchBase -Properties PasswordLastSet,EmailAddress `
     -Filter {PasswordLastSet -le $PasswordWarning -and PasswordLastSet -gt $PasswordExpired}

#For testing:
#$users = Get-Aduser -server $server -SearchBase $searchBase -Properties PasswordLastSet,EmailAddress -Filter {SamAccountName -like '*ANDERSCHA*'}
If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) AD users count: $($users | Measure-Object | Select -ExpandProperty Count)" | Out-File $errorLog -Append }

#******** BES ********
#Query the BES database for email addresses
try {
    $BES12Users = invoke-sql -sqlCommand 'SELECT email_address FROM [bes12Prod].[dbo].[obj_user] WHERE email_address IS NOT NULL'
    If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) BES12 Users Count: $($BES12Users | Measure-Object | Select -ExpandProperty Count)" | Out-File $errorLog -Append }
} catch {
    "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Error connecting to BES SQL - $($Error[0].Exception)" | OutFile $errorLog -Append
}
If ($BES12Users -ne $null -and $BES12Users -ne "") { $BES12list = $true }
#*********************


#******** AirWatch ********
#Airwatch REST API key:
$APIkey = 'EXAMPLEKEYmpTx8mFbq7WvIYh95dY0108jwfjMc5g='
$lookupLimit = 10000

#To create an encrypted password (execute as the service account): ConvertFrom-SecureString -SecureString (ConvertTo-SecureString -String $String -AsPlainText -Force) | Out-File .\Cpi.dat
#Decrypt the password and store in a PSCredential
$password = ConvertTo-SecureString -String (Get-Content "$workingDir\Cpi.dat")
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "MyCorp\SERVICEACCT",$password

#Query AirWatch for all activated devices. Email addresses are under $AWdeviceList.Devices.UserEmailAddress
Try {
    $AWdeviceList = Invoke-RestMethod -uri "https://awconsole.mycorp.com/api/v1/mdm/devices/search?pagesize=$lookupLimit" -Headers @{"aw-tenant-code"="$APIkey"} -ContentType 'application/json; charset=utf8' -Credential $creds -ErrorAction Continue
} Catch {
    $AWlist = $false
    $Error[0] | Out-File $errorLog -Append
}
#Json result became too large, so handle it like this. https://stackoverflow.com/questions/16854057/convertfrom-json-max-length
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")        
$jsonserial= New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer 
$jsonserial.MaxJsonLength = [System.Int32]::MaxValue
$AWdeviceList = $jsonserial.DeserializeObject($AWdeviceList)

If ($AWdeviceList -ne $null -and $AWdeviceList -ne "") { $AWlist = $true }
If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) AirWatch Device Count: $($AWdeviceList.Devices.Count)" | Out-File $errorLog -Append }
#**************************


#Loop through the users and send them an email notification if they haven't had one yet
Foreach ($user in $users) {
    #Reset XSLT
    $XSLT = $null
    #Log errors
    Trap {
        "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) $($user.SamAccountName) - $($Error[0])" | Out-File $errorLog -Append
        Continue
    }
    #Skip empty email addresses
    If ($user.EmailAddress -eq "" -or $user.EmailAddress -eq $null) {
        Continue
    }
    #Skip if $user is in $NotifiedUsers
    If ($NotifiedUsers -like "*$($user.EmailAddress)*") {
        Continue
    }
    #Expiry Date calculation
    $ExpiryDate = (Get-Date $user.PasswordLastSet).AddDays($MaxPasswordAge)
    $days = (New-TimeSpan -End $ExpiryDate).Days
    If ($days -eq 1) { $daysWord = "day" }
    Else { $daysWord = "days" }

    #Check for AirWatch account, use a device template
    If ($AWlist) {
        If ($AWdeviceList.Devices.UserEmailAddress -contains $user.EmailAddress) {       
            #Platform differentiation
            <#
            If (($AWdeviceList.Devices | ? {$_.UserEmailAddress -eq $user.EmailAddress} | Select -ExpandProperty Platform -First 1) -eq 'Apple') {
                $XSLT = "$workingDir\EmailTemplateApple.xslt"
            }
            Else {
                $XSLT = "$workingDir\EmailTemplateAndroid.xslt"
            }
            #>
            $XSLT = "$workingDir\EmailTemplateAndroid.xslt"
        }
    }
       
    #Fall back to device-less template
    If (-not $XSLT) {
            $XSLT = "$workingDir\EmailTemplate.xslt"
    }

    If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Emailing $($user.EmailAddress) $($XSLT.Split("\")[-1]), expires on $ExpiryDate" | Out-File $errorLog -Append }

    #Try sending the email (twice).
    Try {
        $Error.Clear()
        Send-HTMLFormattedEmail `
            -To $user.EmailAddress `
            -ToDisName "$($user.GivenName) $($user.Surname)" `
            -From 'Tech.Support@myCorp.com' `
            -FromDisName 'Tech Support' `
            -Subject "$($user.SamAccountName) - Password Expiring on $(Get-Date $ExpiryDate -Format dd-MMM-yyyy)" `
            -Relay 'smtp.mycorp.com' `
            -XSLPath $XSLT `
            -Content "Your password for MyCorp\$($user.SamAccountName) will expire in $days $daysWord on $(Get-Date $ExpiryDate -Format "dddd, MMMM dd")."
    } Catch {
        If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) $($user.EmailAddress) - $($Error[0])" | Out-File $errorLog -Append }
        $Error.Clear()
        #Sleep and try one more time.
        Start-Sleep -s 5
        Send-HTMLFormattedEmail `
            -To $user.EmailAddress `
            -ToDisName "$($user.GivenName) $($user.Surname)" `
            -From 'Tech.Support@mycorp.com' `
            -FromDisName 'Tech Support' `
            -Subject "$($user.SamAccountName) - Password Expiring on $(Get-Date $ExpiryDate -Format dd-MMM-yyyy)" `
            -Relay 'smtp.mycorp.com' `
            -XSLPath $XSLT `
            -Content "Your password for MyCorp\$($user.SamAccountName) will expire in $days $daysWord on $(Get-Date $ExpiryDate -Format "dddd, MMMM dd")."
        If (!$?) { If ($VerboseLog) { "($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) $($user.EmailAddress) - $($Error[0])" | Out-File $errorLog -Append } }
    }
    If (!$Error) {
        "$($user.EmailAddress),$(Get-Date)" | Out-File $NotifiedUsersPath -Append -Force
        $emailedUsers++
    }

    #Slow down the spam.
    Start-Sleep -s 5
}

"($(Get-Date -Format "yyyy-MM-dd HH:mm:ss")) Completed processing $EmailedUsers users" | Out-File $errorLog -Append

# SIG # Begin signature block
# MIIJHAYJKoZIhvcNAQcCoIIJDTCCCQkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUj7ckwJaLv8hDbIvA5viAE++q
# cPugggaBMIIGfTCCBWWgAwIBAgIEWIq/9zANBgkqhkiG9w0BAQsFADBcMQswCQYD
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHByW97g728mhZc9FGQwdemDH3RdMA0G
# CSqGSIb3DQEBAQUABIIBAJLJnZo1AsTx+otvzgWk7US7LMZAE1qecJ5EdbV8NEc+
# iV1s/qlwwnAFs9KsPANrDEkpci48RHAmTHQdIIaJYE9B1el3O83xhVLnK+cTKRRo
# vBssD8pM7htzmx3wW3pjiGLNfGeG8xbUSXTJpK7PI9ikjdhimIMqhZ3UGgdCm+tq
# DdBEtlERZTN6NjfMtBB3TRjlDGfAfWxoapOWLS+O/6NIW0FGWWvVAu9kAAjFGR+o
# lxiZNNlDFglepLn+9QtJQvueOeRzzRUavy/DxAUI6SfgDNq+s5dIGee7C+3qzWSf
# P3vJeiGQiMLP7nhGWp4Jw9+oLA0flqcXXh08l+8t5SE=
# SIG # End signature block
