######################################################
##         Task-Sequence Change Tracking            ##
######################################################
<# 
.SYNOPSIS
This Powershell-Script is a Chance-Tracking of TaskSequences which get modified. The Execution is base on a Status-Filter-Rule.
We will track who, what and when the TS has been modified.
 
.DESCRIPTION
The Script will Create a Backup of Task-Sequence-XML in a Backup-Root-Location which must specify.The Folder-Structure is based on
the PackageID of the TS. The Backup-File is based on the Task-Sequence-Name + Timestamp
All Activities are written to a Log-File - by default C:\Windows\Logs\TS-Change-Tracking.log. The Name and the Location can be modified.
 
.EXAMPLE
Run the Script must be specified like this in a Status-Filter-Rule
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ep bypass -file C:\Scripts\TS-Change-Tracking.ps1 -User %msgis01 -ID %msgis02 -TSName "%msgis03"
 
.NOTES
Status-Filter-Rule
SiteCode: FCH
Message Type: Audit
Message ID: 30001

.LINK
https://www.microsoft.com
#>

### Invocation Parameters

Param
(
    [Parameter(Mandatory = $true)]
    [String]$User,
    [Parameter(Mandatory = $true)]
    [String]$ID,
    [Parameter(Mandatory = $true)]
    [String]$TSName

)

### Static Parameters

[String]$SiteCode = "XYZ"
[String]$BackupRoot = "C:\scripts\ExportedTaskSequences"
[String]$Date = (get-date).ToString().Replace(':','-').Replace('\','-').Replace('/','-') 


### Logging 

[String]$LogfileName = "TS-Change-Tracking"
[String]$Logfile = "C:\scripts\ExportedTaskSequences\$LogfileName.log"

Function Write-Log
{
   Param ([string]$logstring)
   If (Test-Path $Logfile)
   {
       If ((Get-Item $Logfile).Length -gt 2MB)
       {
       Rename-Item $Logfile $Logfile".bak" -Force
       }
   }
   $WriteLine = (Get-Date).ToString() + " " + $logstring
   Add-content $Logfile -value $WriteLine
}

### Check SCCM-Console

Try
{
    $ConfigMgrModule = ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1')
    Import-Module $ConfigMgrModule
    Write-Log "Found SCCM-Console-Environment"
    Write-Log $ConfigMgrModule
}
Catch
{
    Write-host "Exception Type: $($_.Exception.GetType().FullName)"
    Write-host "Exception Message: $($_.Exception.Message)"
    Write-Host "ERROR! Console not installed or found"
    Write-Host "Script will exit"
    Exit 1
}

Try 
{
    $SMS = gwmi -Namespace 'root\sms' -query "SELECT SiteCode,Machine FROM SMS_ProviderLocation" 
    $SiteCode = $SMS.SiteCode
    $SiteProvider = $SMS.Machine
    Write-Log "SiteCode: $SiteCode"
    Write-Log "SiteServer: $SiteProvider"
}
Catch 
{
    Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
    Write-Log "Exception Message: $($_.Exception.Message)" 
    Write-Log "ERROR! Unable to find in WMI SMS_ProviderLocation. Script will Exit!" 
    Exit 1
}

### Your Main Code ###

Write-Log "TaskSequence-Change found - start tracking and backup:"
Write-Log "Modifying User: $User"
Write-Log "Modified TaskSequenceID: $ID"
Write-Log "Modified TaskSequenceName: $TSName"

If ($BackupRoot -eq "" -or (Test-Path $BackupRoot) -eq $false)
{
    Write-Log "ERROR! No Backup-Root-Location specified or accessable. Unable to continue."
    Write-Log "Backup-Root defined: $BackupRoot"
    Write-Log "Script will quit Now"
    Exit 1
}
Else
{
    Write-Log "Backup-Root defined: $BackupRoot"
}


Write-Log "Check/Verify Backup-Location"

[String]$BackupLocation = "$BackupRoot\$ID"
Try
{
    If (Test-Path $BackupLocation)
    {
    Write-Log "Found Backup-Location: $BackupLocation"
    }
    Else
    {
    Write-Log "Warning! Backup-Location not found. Try to create it."
        
        Try
         {
            New-Item -ItemType Directory -Path $BackupLocation
            Write-Log "Backup-Location created: $BackupLocation"
         }
        Catch
        {
            Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
            Write-Log "Exception Message: $($_.Exception.Message)"
            Write-Log "ERROR! Unable to create Folder. Script will exit"
            Exit 1
        }
    }
}
Catch
{
    Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
    Write-Log "Exception Message: $($_.Exception.Message)"
    Write-Log "Unknown Error"
    Exit 1
}


### Change to CM-Powershell-Drive

Write-Log "Prepare Environment for Backup. Create PS-Drive and Switch for ConfigMgr. Needed in System-Context"
$CMDrive = Get-PSProvider -PSProvider CMSite
If ($CMDrive.Drives.Count -eq 0)
{
    Write-Log "CMSite-Provider does not have a Drive! Try to create it."
    Try
    {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteProvider
        Write-Log "CMSite-Provider-Drive created!"
    }
    Catch
    {
        Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Log "Exception Message: $($_.Exception.Message)"
    }
}

[String]$TSBackupFile = "$BackupLocation\$TSName-$Date.xml"
Write-Log "TaskSequence Backup-File will be located here: $TSBackupFile"

Write-Log "Switching Drive for ConfigMgr-CmdLets"
SL $SiteCode":"

Try
{
    $TSBackup = Get-CMTaskSequence -TaskSequencePackageId $ID
    $TSBackup.Sequence | Out-File -FilePath $TSBackupFile
}
Catch
{
    Write-Log "Exception Type: $($_.Exception.GetType().FullName)"
    Write-Log "Exception Message: $($_.Exception.Message)"
    Write-Log "Unknown Error"
    Exit 1
}

Write-Log "Script-Execution finished!"
Write-Log ""

