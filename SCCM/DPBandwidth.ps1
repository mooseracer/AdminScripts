#This script is used to set the correct bandwidth throttling for all DP depending on the ping response  
#Adapted from: http://it-by-doing.blogspot.ca/2013/05/automatic-bandwidth-throttling-sccm.html

Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1" #where you have CM12 installed  

[string] $PrimarySiteCode = "XYZ" #your site code here  
$MP = "SCCM" #Primary site server that you want to exclude  
$MPFQDN = "SCCM.CorpName.xyz" #Primary site server that you want to exclude FQDN  

[int] $BandWidthPercentHigh = 50  
[int] $BandWidthPercentMedium = 25  
[int] $BandWidthPercentLow = 10  
[int] $BandWidthPercentSatellite = 3
[int] $BandWidthPercentSatelliteSlow = 1

[int] $PingHigh = 20 #ms  
[int] $PingMedium = 70 #ms  
[int] $PingLow = 300 #ms  
[int] $PingSatellite = 1000 #ms  
[int] $PingNoResponse = -1  
[int] $PingSize = 1024  
$SiteDrive = $PrimarySiteCode + ":"

#$smtpServer = "myserver-mailgw.my.server.root" #SMTP server name  
#$EmailFrom = "sccm12server@yourdomain.com" #from email address  
#$EmailReplyTo = "sccm12server@yourdomain.com" #reply to  
#$EmailTo = "admin@yourdomain.com" #To, only one address implemented 

Function ChangeBandwidthThrottling  
{  
param(  
[String]$ServerName,  
[String]$SiteCode,  
[int]$Percent  
)  
  
# Set the schedules first!  
#Array containing 24 elements, one for each hour of the day. A value of true indicates that the address (sender) embedding SMS_SiteControlDaySchedule can be used as a backup.  
$UsageAsBackup = @($true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true)  
#Array containing 24 elements, one for each hour of the day. This property specifies the type of usage for each hour.  
# 1 means all Priorities, 2 means all but low, 3 is high only, 4 means none  
$HourUsageSchedule = @(1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1)  
#Set RateLimitingSchedule, array for every hour of the day, percentage of how much bandwidth can be used, min 1, max 100  
$RateLimitingSchedule = @($Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent,$Percent)  
  
$SMS_SCI_ADDRESS = "SMS_SCI_ADDRESS"  
$class_SMS_SCI_ADDRESS = [wmiclass]""  
$class_SMS_SCI_ADDRESS.psbase.Path ="ROOT\SMS\Site_$($SiteCode):$($SMS_SCI_ADDRESS)"  
  
$SMS_SCI_ADDRESS = $class_SMS_SCI_ADDRESS.CreateInstance()  
  
# Set the UsageSchedule  
$SMS_SiteControlDaySchedule      = "SMS_SiteControlDaySchedule"  
$SMS_SiteControlDaySchedule_class   = [wmiclass]""  
$SMS_SiteControlDaySchedule_class.psbase.Path = "ROOT\SMS\Site_$($SiteCode):$($SMS_SiteControlDaySchedule)"  
$SMS_SiteControlDaySchedule          = $SMS_SiteControlDaySchedule_class.createInstance()  
$SMS_SiteControlDaySchedule.Backup  = $UsageAsBackup  
$SMS_SiteControlDaySchedule.HourUsage = $HourUsageSchedule  
$SMS_SiteControlDaySchedule.Update  = $true  
$SMS_SCI_ADDRESS.UsageSchedule    = @($SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule)  
  
$SMS_SCI_ADDRESS.RateLimitingSchedule = $RateLimitingSchedule  
  
$SMS_SCI_ADDRESS.AddressPriorityOrder = "0"  
$SMS_SCI_ADDRESS.AddressType     = "MS_LAN"  
$SMS_SCI_ADDRESS.DesSiteCode     = "$($ServerName)"  
$SMS_SCI_ADDRESS.DestinationType   = "1"  
$SMS_SCI_ADDRESS.SiteCode       = "$($SiteCode)"  
$SMS_SCI_ADDRESS.UnlimitedRateForAll = $false  
  
# Set the embedded Properties  
$embeddedpropertyList = $null  
$embeddedproperty_class = [wmiclass]""  
$embeddedproperty_class.psbase.Path = "ROOT\SMS\Site_$($SiteCode):SMS_EmbeddedPropertyList"  
$embeddedpropertyList                     = $embeddedproperty_class.createInstance()  
$embeddedpropertyList.PropertyListName      = "Pulse Mode" 

if($Percent -eq $BandWidthPercentSatellite)
{
   $embeddedpropertyList.Values  = @(1,15,3) #second value is size of data block in KB, third is delay between data blocks in seconds
}
elseif($Percent -eq $BandWidthPercentSatelliteSlow)
{
   $embeddedpropertyList.Values  = @(1,15,9) #second value is size of data block in KB, third is delay between data blocks in seconds
}
else
{
   $embeddedpropertyList.Values  = @(0,15,3) #second value is size of data block in KB, third is delay between data blocks in seconds
}


$SMS_SCI_ADDRESS.PropLists += $embeddedpropertyList  
  
$embeddedproperty = $null    
$embeddedproperty_class = [wmiclass]""  
$embeddedproperty_class.psbase.Path = "ROOT\SMS\Site_$($SiteCode):SMS_EmbeddedProperty"  
$embeddedproperty                     = $embeddedproperty_class.createInstance()  
$embeddedproperty.PropertyName      = "Connection Point"  
$embeddedproperty.Value           = "0"  
$embeddedproperty.Value1          = "$($ServerName)"  
$embeddedproperty.Value2          = "SMS_DP$"            
$SMS_SCI_ADDRESS.Props += $embeddedproperty  
  
$embeddedproperty = $null  
$embeddedproperty_class = [wmiclass]""  
$embeddedproperty_class.psbase.Path = "ROOT\SMS\Site_$($SiteCode):SMS_EmbeddedProperty"  
$embeddedproperty                     = $embeddedproperty_class.createInstance()  
$embeddedproperty.PropertyName      = "LAN Login"  
$embeddedproperty.Value           = "0"  
$embeddedproperty.Value1          = ""  
$embeddedproperty.Value2          = ""            
$SMS_SCI_ADDRESS.Props += $embeddedproperty  
  
  
$SMS_SCI_ADDRESS.Put() | Out-Null  
  
  
}  
  
Function NewPing{  
param ([string]$Server)  
  
[int] $response = -1  
  
  Try  
  {  
    $PingServer = Test-Connection -count 3 $Server -BufferSize $PingSize -ErrorAction SilentlyContinue
    if($PingServer -ne $NULL )  
    {      
      #Runs in ISE  
      $Avg = ($PingServer | Measure-Object ResponseTime -Average)  
      $response = [System.Math]::Round($Avg.average)  
      
    }  
  }  
  Catch  
  {  
    return $response    
  }  
  Finally  
  {  
  }  
  return $response  
} 
  
Function Speed  
{  
param ([string]$Server)  
  
[int]$Response = 0  
[int]$Percent = 0  
  
  $Response = NewPing($Server)  
  
   if($Response -eq $PingNoResponse)
   {#no response
       #sendMail -Text "Tried to ping server $Server, but got no response, please investigate"
       #Write-EventLog -LogName SCCMAdmins -Source SCCMBT -Message "Tried to ping server $Server, but got no response, please investigate" -EventId 1 -EntryType Error
       Write-Host "Tried to ping server $Server, but got no response, please investigate"
       #ChangeBandwidthThrottling -ServerName $Server -SiteCode $PrimarySiteCode -Percent $BandWidthPercentSatelliteSlow
       #Write-Host "Setting bandwidth throttling to: 1KB/30sec (pulse mode) on $Server, response is $Response ms."
   }
   else
   {
       if ($Response -le $PingHigh)
       { #Fast
           $Percent = $BandWidthPercentHigh
           $Message = "Setting bandwidth throttling to: $Percent percent on $Server, response is $Response ms."
       }
       elseif($Response -le $PingMedium)
       {
           $Percent = $BandWidthPercentMedium
           $Message = "Setting bandwidth throttling to: $Percent percent on $Server, response is $Response ms."
       }
       elseif($Response -le $PingLow)
       {
           $Percent = $BandWidthPercentLow
           $Message = "Setting bandwidth throttling to: $Percent percent on $Server, response is $Response ms."
       }
       elseif($Response -le $PingSatellite)
       {
           $Percent = $BandWidthPercentSatellite
           $Message = "Setting bandwidth throttling to: 15KB/3sec on $Server, response is $Response ms."
       }        
       else
       { #Slow
           $Percent = $BandWidthPercentSatelliteSlow
           $Message = "Setting bandwidth throttling to: 15KB/9sec on $Server, response is $Response ms."
       }
       ChangeBandwidthThrottling -ServerName $Server -SiteCode $PrimarySiteCode -Percent $Percent
       Write-Host $Message
       #Write-EventLog -LogName SCCMAdmins -Source SCCMBT -Message $Message -EventId 0 -EntryType information
   }

}  
  
 function sendMail{  
 param ([string]$Text)  
   
  
   #Creating a Mail object  
   $msg = new-object Net.Mail.MailMessage  
  
   #Creating SMTP server object  
   $smtp = new-object Net.Mail.SmtpClient($smtpServer)  
  
   #Email structure  
   $msg.From = $EmailFrom  
   $msg.ReplyTo = $EmailReplyTo   
   $msg.To.Add($EmailTo)  
   $msg.subject = $Text  
   $msg.body = $Text  
  
   #Sending email  
   $smtp.Send($msg)  
   
}  
  
  
  
#***************************************************************************************************************************************  
#***************************************************************************************************************************************  
#***************************************************************************************************************************************  
#*************************** Script starts here ************************************************************  
   
  
Set-Location $siteDrive  

Get-CMDistributionPoint | Select-Object NetworkOSPath | Foreach-Object {  
    if($_.NetworkOSPath -ne "\\$MPFQDN")  
    {  
      Speed ($_.NetworkOSPath).Split("\")[-1]
    }
}  
