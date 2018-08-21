#C Anderson / Oct 2017
#Customizations script to run at the end of the task sequence. Tested on Win10 1703, 1709

#Capture the date this script ran and put in marker files.
$now = Get-Date
$now.DateTime | Out-File "C:\Program Files (x86)\build_date.txt"
$markerfile = "$($now.Year)" + "$($now.Month)" + "$($now.Day)" + ".exe"
echo $null | Out-File "C:\Program Files (x86)\$markerfile"


#Enable WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck


#Enable inbound RDP
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" �Value 0


#Rename local admin account
Rename-LocalUser -Name Administrator -NewName "$($env:COMPUTERNAME)adm" -Confirm:$false


#Apply HKLM registry keys
& REG IMPORT HKLM.reg


#Apply Default User registry keys
& REG LOAD HKU\DU C:\Users\Default\NTUSER.DAT
& REG IMPORT DefaultUser.reg
& REG UNLOAD HKU\DU


#Copy hosts file
Copy .\hosts C:\Windows\System32\drivers\etc\hosts -Force


#Disable "suggested apps" by rerouting Microsoft IP addresses to 0.0.0.0
#https://github.com/bmrf/tron/blob/master/resources/stage_4_repair/disable_windows_telemetry/purge_windows_10_telemetry.bat
& .\nullroutes.bat


#Set default application associations (Win10 1703)
#https://execmgr.net/2017/07/24/field-notes-the-windows-10-1703-default-apps-minefield/
Copy appassoc.xml 'C:\Users\Default\appassoc.xml'
Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\System -Name DefaultAssociationsConfiguration -Value 'C:\Users\Default\appassoc.xml'
New-Item -Path HKLM:\Software\Classes\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723
Set-ItemProperty -Path HKLM:\Software\Classes\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723 -Name NoOpenWith -Value ''
Set-ItemProperty -Path HKLM:\Software\Classes\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723 -Name NoStaticDefaultVerb -Value ''


#Cleanup
If (Test-Path "C:\ComputerName.txt") { Remove-Item C:\ComputerName.txt -Force }


#Scheduled task to delete leftover user profiles. Doesn't work if you just run it from here. Executes later.
#Get-CimInstance Win32_UserProfile | ? {$_.LocalPath -like "*defaultuser0*"} | % { Remove-CimInstance $_ }
$Rescheduled = (Get-Date).Addminutes(60)
& SCHTASKS /CREATE /XML CleanupProfiles.xml /TN CleanupProfiles 
& SCHTASKS /CHANGE /TN CleanupProfiles /SD $($Rescheduled.ToString("dd/MM/yyyy")) /ST "$($Rescheduled.ToString("HH:mm"))" /ED $($Rescheduled.ToString("dd/MM/yyyy")) /ET "$(($Rescheduled.AddDays(1)).ToString("HH:mm"))" /Z
