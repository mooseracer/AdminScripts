#Unless attributed otherwise all functions authored by Charles Anderson

Function Test-ATConnection {
<#
.SYNOPSIS
Tests connectivity to a given Windows hostname or IP address.

.DESCRIPTION
A ping test is run and then the C$ admin share is tested. This test will fail if your user account doesn't have permission to access C$,
or if DNS is returning the IP of a different hostname.


.EXAMPLE
PS C:\> If (Test-ATConnection WRKSTN0001) { #Do something }

.PARAMETER ComputerName
The hostname or IP address to test.
#>
    param ($ComputerName)

    #Ping test
    If (!(Test-Connection $ComputerName -Count 1 -ErrorAction SilentlyContinue)) { Return $false }
    Return (Test-Path \\$ComputerName\C$)
}


Function Get-ATUser {
<#
.SYNOPSIS
Displays common attributes of a domain user account. Its LockedOut status will be checked on every
domain controller. If it was locked out on any it will be unlocked and reported.

If it was locked, the Locked Out report on \\servername\Locked Out\LockoutReport.txt is
parsed to see if there're any entries for the user.

SCCM is also queried to see which computers the user has last logged on to. Compare with Get-ATComputer
to see a computer's currently logged on user.

.EXAMPLE
PS C:\> Get-ATUser SMITHB

This command will query the domain for SMITHB. Sample output:

SMITHB
====================
Display Name        : Smith, Brent (XYZ)
Email Address       : Brent.Smith@CorpName.xyz
Description         : 
Title               : Test User
Office              : Sales
Y: drive            : SERVERNAME\SMITHB
P: drive            : SERVERNAME\SALES
Last Logged On To   : WRKSTN0001 WRKSTN0004
Password Expired    : False
Password Last Set   : 09/23/2014 09:54:27
Locked Out          : False

#>
    Param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string]
        $username
    )
  
    $domain = "CorpName.xyz"                                        #Domain FQDN
    $SiteServer = 'SCCM.CorpName.xyz'                               #SCCM management point server FQDN
    $SiteCode = 'XYZ'                                               #SCCM site code
    $reportFile = '\\servername\Locked Out\LockoutReport.txt'       #This domain writes user lockout reports to a custom text file
    
    <#
    Sample LockoutReport.txt:

DOMAINCONTROLLER1

UserName                   WorkstationName            TimeGenerated            
--------                   ---------------            -------------            
USER001                    WRKSTN0001                 1/2/2018 10:04:21 AM     
USER002                    EXCHANGE1                  1/2/2018 9:47:47 AM      
USER003                    EXCHANGE2                  1/2/2018 9:47:44 AM      
USER004                    WRKSTN0004                 1/2/2018 9:26:57 AM      

DOMAINCONTROLLER2

UserName                   WorkstationName            TimeGenerated            
--------                   ---------------            -------------            
USER005                    WRKSTN0003                 1/2/2018 8:40:31 AM       

    #>
    Import-Module "ActiveDirectory"

    #Enumerate writeable domain controllers
    $DCs = Get-ADDomain -server $domain | Select-Object -ExpandProperty ReplicaDirectoryServers
    $writeableDCs = @()
    Foreach ($DC in $DCs) {
        If (Get-ADDomainController -Identity $DC | Where-Object {$_.IsReadOnly -eq $false}) {
            $writeableDCs += $DC
        }
    }

    $result = Get-ADUser $username -Server $domain -Properties * -ErrorAction SilentlyContinue
    If (!$?) {
        Write-Host $Error[0]
        Return
    }

    #Heading
    Write-Host "`n"
    Write-Host $result.SamAccountName.ToUpper() -ForegroundColor Green
    Write-Host "========================" -ForegroundColor Green
    Write-Host "Display Name`t`t: $($result.DisplayName)"
    Write-Host "Email Address`t`t: $($result.EmailAddress)"
    Write-Host "Description`t`t: $($result.Description)"
    Write-Host "Title`t`t`t: $($result.Title)"
    Write-Host "Office`t`t`t: $($result.Office)"
    
    #This domain has custom AD attributes for mapping network drives.
    #Matching attributes also exist for drive#Letter, drive#Path.
    #For each drive#, the user's logon script runs: NET USE "drive#Letter": \\"drive#Server"\"drive#Path"
    $driveServers = @("drive1Server",
        "drive2Server",
        "drive3Server",
        "drive4Server",
        "drive5Server",
        "drive6Server",
        "drive7Server",
        "drive8Server")

    #Display Y: and P: drives
    $driveServers | % {
        If ($result.($_) -ne "" -and $result.($_) -ne $null) {
            #Check to see if this one is Y:
            If ($result.($_ -replace "Server", "Letter") -eq "Y") {
                $YServer = $result.($_)
                $Ydrive = $result.($_ -replace "Server", "Path")
                Return
            }
            If ($result.($_ -replace "Server", "Letter") -eq "P") {
                $PServer = $result.($_)
                $Pdrive = $result.($_ -replace "Server", "Path")
                Return
            }
        }
    }
    If ($Ydrive -ne $null -and $Ydrive -ne "") {
        Write-Host "Y: drive`t`t: $Yserver\$Ydrive"
    }
    If ($Pdrive -ne $null -and $Pdrive -ne "") {
        Write-Host "P: drive`t`t: $Pserver\$Pdrive"
    }

    #Last Known Computers from SCCM
    $SCCMquery = Get-WmiObject -ComputerName $SiteServer -Namespace  "ROOT\SMS\site_$SiteCode" -Query "SELECT Name, LastLogonUserName from sms_r_system WHERE LastLogonUserName = '$($username)'"
    If ($SCCMquery) {
        Write-Host "Last Logged On To`t: " -NoNewline
        $SCCMquery | % { Write-Host "$($_.Name) " -NoNewline }
        Write-Host "`r"
    }

    #Enabled
    If ($result.Enabled -eq $false) {
        Write-Host "Enabled`t`t`t: $($result.Enabled)" -ForegroundColor Red
    }
    If ($result.PasswordExpired -eq $true) { $color = 'Red' } Else { $color = 'Green' }
    
    #Password
    Write-Host "Password Expired`t: $($result.PasswordExpired)" -ForegroundColor $color
    Write-Host "Password Last Set`t: $($result.PasswordLastSet)" -ForegroundColor $color

    #Locked Out
    $waslocked = $false
    $unlockedFrom = @()
    $DCs | ForEach-Object {
        $lockedout = Get-ADUser $username -server $_ -Properties LockedOut | Select-Object -ExpandProperty LockedOut
        If ($lockedout) {
            Unlock-ADAccount $username -Server $_
            $waslocked = $true
            $unlockedFrom += $_
        }
    }
    If ($waslocked) { $Color = 'Red' } Else { $Color = 'Green' }
    Write-Host "Locked Out`t`t: $($result.LockedOut)" -ForegroundColor $Color
    If ($waslocked) {
        Write-Host "`tUnlocked $username on:"-ForegroundColor Yellow
        $unlockedFrom | ForEach-Object {
            Write-Host "`t`t$_" -ForegroundColor Yellow
        }
        #Parse $reportFile for source of lockout
        $report = Get-Content $reportFile -ErrorAction SilentlyContinue
        $source = @()
        If ($report -ne $null -and $report -ne "") {
            ($report | select-string $username) | ForEach-Object {
                #RegEx pattern match: username + whitespace + computername (anything) + whitespace + date format [#]#/[#]#/####
                $_ -match ("$username" + '\s+(.+)\s+\d{1,2}[\/]\d{1,2}[\/]\d{4}') | ForEach-Object {
                    $source += $Matches[1]
                }
            }
            If ($source -ne $null -and $source -ne "") {
                Write-Host "`tLockout was generated by: " -ForegroundColor Yellow -NoNewline
                $source | ForEach-Object {
                    Write-Host "$_ " -ForegroundColor Yellow -NoNewline
                }
                Write-Host "`r"
            }
        }
    }
}

Function Get-ATComputer {
<#
.SYNOPSIS
Displays common attributes of a computer object. 

.EXAMPLE
PS C:\> Get-ATComputer WRKSTN0001

This command will query SCCM for WRKSTN0001. Sample output:

WRKSTN0001
========================
Currently Online        : False
Currently Logged On     :
Last Logged On Username : SMITHB
Last Logged On Timestamp: 06-Sep-2015 01:42:09
IP addresses:           : 10.0.1.159
Last seen on domain     : 06-Sep-2015 09:42:11
Local admin password    : bOA#qz!Spb52


Currently Online - The result of the command 'Test-ATConnection $ComputerName'. Uses PING and SMB to determine if the computer is reachable, and that the IP does in fact match the hostname queried.
Currently Logged On - The username logged in to the computer, if any.
Last Logged On Username - The username most recently reported to SCCM.
Last Logged On Timestamp - The logon time of the above username.
IP addresses - The IPv4 addresses associated with any network adapters that were reported to SCCM. IPv6 and the autoconfiguration 169.254.x.x IP are filtered out.
Last seen on domain - This is the timestamp of the 'Modified' attribute returned by Active Directory for this computer object.
Local admin password - Microsoft's LAPS utility will store this in the ms-Mcs-AdmPwd attribute and periodically change it.

#>
    Param(
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        [string[]]
        $ComputerName
    )

    Begin {
        Import-Module "ActiveDirectory"
        $domain = "CorpName.xyz"                                        #Domain FQDN
        $SiteServer = 'SCCM.CorpName.xyz'                               #SCCM management point server FQDN
        $SiteCode = 'XYZ'  
    }

    Process {
        #Last Known Computers from SCCM
        Foreach ($Computer in $ComputerName) {
            $Computer = $Computer.ToUpper()
            $SCCMquery = "SELECT Name,LastLogonUserName,LastLogonTimestamp,IPAddresses,OperatingSystemNameandVersion,Build from sms_r_system WHERE Name = '$($Computer)'"
            $SCCMresults = Get-WmiObject -ComputerName $SiteServer -Namespace  "ROOT\SMS\site_$SiteCode" -Query $SCCMquery
            $ADComputer = Get-ADComputer -Identity $Computer -Server $domain -Properties Modified,ms-Mcs-AdmPwd
            $Modified = $ADComputer | Select-Object -ExpandProperty Modified
            If ($Modified) {
                $Modified = Get-Date $Modified -Format "dd-MMM-yyyy hh:mm:ss"
            }

            $AdmPwd = $ADComputer | Select-Object -ExpandProperty ms-Mcs-AdmPwd
            
            Foreach ($SCCMresult in $SCCMresults) {
                #Convert timestamp to a more readable date
                If ($SCCMresult.LastLogonTimestamp -ne "" -and $SCCMresult.LastLogonTimestamp -ne $null) {
                    $LastLogonTimestamp = [datetime]::ParseExact(($SCCMresult.LastLogonTimestamp).Split(".")[0], "yyyyMMddHHmmss",$null)
                    $LastLogonTimestamp = Get-Date $LastLogonTimestamp -Format "dd-MMM-yyyy hh:mm:ss"
                }

                If ($SCCMresult.LastLogonUserName -ne "" -and $SCCMresult.LastLogonUserName -ne $null) {
                    $LastLogonUserName = ($SCCMresult.LastLogonUserName).ToUpper()
                }

                #Operating System
                $OS = $SCCMresult.OperatingSystemNameandVersion
                $ver = $OS.Split(" ")[-1]
                $OS = $OS.Substring(0,$OS.Length - $ver.Length) + $SCCMresult.Build

                #Only report IPv4 addresses
                $IPv4 = @()
                $SCCMresult.IPAddresses | ForEach-Object { 
                    $_ -match "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" | ForEach-Object {
                        If ($_) {
                            If ($matches[1] -notlike "169.*") {
                                $IPv4 += $matches[1]
                            }
                        }
                    }
                }

                #Online
                [boolean]$online = Test-ATConnection $Computer
                $colour = 'red'

                #Get currently logged on user
                If ($online) {
                    $colour = 'green'
                    $username = Get-WmiObject Win32_ComputerSystem -ComputerName $Computer | Select-Object -ExpandProperty Username
                    If ($username) { $username = $username.ToUpper().Split("\")[-1] }
                }
                Else { $username = $null }

                #Heading
                Write-Host "`n"
                Write-Host "$($SCCMresult.Name.ToUpper())" -ForegroundColor Green
                Write-Host "========================" -ForegroundColor Green
                Write-Host "Currently Online`t: $online" -ForegroundColor $colour
                Write-Host "Currently Logged On`t: $username"
                Write-Host "Last Logged On Username`t: $LastLogonUserName" 
                Write-Host "Last Logged On Timestamp: $LastLogonTimestamp"
                Write-Host "Operating System`t: $OS"
                Write-Host "IP addresses`t`t: $IPv4"
                Write-Host "Last seen on domain`t: $Modified"
                If ($AdmPwd) {
                    Write-Host "Local admin password`t: $AdmPwd"
                }
                Write-Host "`r"
            }
        }
    }
}


Function Install-ATSCCMclient {
<#
  .SYNOPSIS
  Copies the SCCM client setup files to a workstation and then installs it.
  
  .DESCRIPTION
  The Install-ATSCCMclient function will copy ccmsetup.exe from <server> to the specified computer.
  It will then remotely run ccmsetup.exe. Installation may take up to several hours depending on location.

  Several pre-installation tasks are run to help ensure success:
  -BITS throttling is disabled to allow for the fastest possible download of the SCCM client
  -Currently running ccmsetup or ccmexec processes are terminated
  -C:\Windows\CCM is deleted
  -The SCCM client's registration certificates are deleted
  -Previous ccmsetup.log is grep'd for error codes

  The installation command used:
  c:\windows\ccmsetup\ccmsetup.exe /forceinstall /MP:<server> SMSSITECODE=<code>


  .EXAMPLE
  PS C:\> Install-ATSCCMclient -ComputerName WRKSTN0001

  Description
  -----------

  This command will copy ccmsetup.exe and client.msi from <server> to WORKSTN0001 and then run ccmsetup.exe remotely.

  .PARAMETER ComputerName
  The computer name to install the SCCM client on.
 #>
 
    Param (
        [Parameter(Mandatory=$True,ValueFromPipeline=$True)]
        [String]
        $ComputerName
    )

    $SiteServer = 'SCCM.CorpName.xyz'                               #SCCM management point server FQDN
    $SiteCode = 'XYZ'     

    #Connection test and DNS verification
    If (!(Test-ATConnection $ComputerName)) { Return "$ComputerName is unreachable" }
    
    #Attempt to establish a remote PowerShell session
    try {
        Write-Host "Connecting to $ComputerName... " -NoNewline
        $PSSessionOptions = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 60000 -IdleTimeout 60000 -CancelTimeout 10000
        $session = New-PSSession -ComputerName $ComputerName -SessionOption $PSSessionOptions -ErrorAction Stop
    }
    catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
        If ((Get-Service WinRM -ComputerName $ComputerName).Status -ne 'Started') {
            Write-Host "`n"
            Write-Host "Unable to remotely connect with PowerShell because the WinRM service is not started. Attempting to start WinRM..." -ForegroundColor Yellow
            Get-Service WinRM -ComputerName $ComputerName | Start-Service
            If ($?) {
                Write-Host "WinRM service started, trying again..." -ForegroundColor Yellow
                If ((Invoke-Command -ComputerName $ComputerName -ScriptBlock { Test-Path C: })) {
                    Install-ATSCCMclient $ComputerName
                    Return
                }
                Else {
                    Write-Host "Unable to remotely connect with PowerShell." -ForegroundColor Yellow
                    Return
                }
            }
            Else {
                Write-Host "Failed to start WinRM service. Unable to proceed with SCCM client installation." -ForegroundColor Yellow
                Return
            }
        }
        Else {
            Write-Host "Unable to remotely connect with PowerShell." -ForegroundColor Yellow
            Write-Host $Error[0]
            Return
        }
    }
    catch {
        Write-Host $Error[0]
        Return
    }

    trap [System.Management.Automation.PSInvalidOperationException] {
        Return
    }


    #Kill existing CCM
    Write-Host "Terminating SCCM processes... " -nonewline
    Invoke-Command -Session $session { Get-Process ccm* | Stop-Process -Force }
    Invoke-Command -Session $session { Remove-Item C:\windows\ccm -Recurse -Force -ErrorAction SilentlyContinue }
    Invoke-Command -Session $session { Remove-Item C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\19c5cf9c* -Force -ErrorAction SilentlyContinue }

    #Disable BITS throttling 
    Invoke-Command -Session $session {
        $throttling = Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\BITS | Select-Object -ExpandProperty EnableBitsmaxbandwidth
        If ($throttling = 1) {
            Write-Host "Disabling BITS throttling... " -nonewline 
            Set-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\BITS -Name EnableBitsMaxBandwidth -Value 0
            Get-Service BITS | Restart-Service -Force
        }
    }
    
    #Check ccmsetup.log
    $ccmsetup = "\\$ComputerName\c$\windows\ccmsetup\logs\ccmsetup.log"
    $ccmsetupLog = Get-Content $ccmsetup -ErrorAction SilentlyContinue
    
    #grep ccmsetup.log for error 1603, which means wipe c:\windows\temp
    If (($ccmsetupLog | Select-String "ExitCode: 1603")) {
        Write-Host "ccmsetup.exe previously failed with error 1603. Purging C:\Windows\Temp... " -NoNewline
        Invoke-Command -Session $session { Remove-Item C:\Windows\Temp\* -Recurse -ErrorAction SilentlyContinue }
    }

    #grep ccmsetup.log for 0x80041013, which means wipe WMI's root\ccm and install without /forceinstall
    If (($ccmsetupLog | Select-String "0x80041013")) {
        Write-Host "ccmsetup.exe previously failed with error 0x80041013. Deleting root\ccm from WMI... " -NoNewline
        Invoke-Command -Session $session { Get-WmiObject -query "SELECT * FROM __Namespace WHERE Name='CCM'" -Namespace "root" | Remove-WmiObject }
        $noReinstall = $true
    }


    #Install CCM
    Write-Host "Copying ccmsetup.exe to $ComputerName... " -NoNewline
    If (!(Test-Path \\$ComputerName\C$\Windows\ccmsetup -PathType Container)) {
        New-Item -Path \\$ComputerName\C$\Windows\ccmsetup -ItemType Directory
    }
    Copy-Item '\\SCCM\Packages\SCCM_OP2\ccmsetup.exe' \\$ComputerName\C$\Windows\ccmsetup -force -Confirm:$false
    Write-Host "Executing... " -NoNewline 
    $arguments = "& c:\windows\ccmsetup\ccmsetup.exe /forceinstall /MP:$SiteServer SMSSITECODE=$SiteCode"
    If ($noReinstall) { $arguments = "& c:\windows\ccmsetup\ccmsetup.exe /MP:$SiteServer SMSSITECODE=$SiteCode" }

    Invoke-Command -Session $session -ScriptBlock $arguments
    Write-Host "ccmsetup.exe is currently running.`nInstallation usually completes in 5-10 minutes, monitor $ccmsetup for progress."
    Remove-PSSession -Session $session
    Return "SCCM client reinstallation triggered."
}



Function Get-ATDiskSpace {
    <#
    .SYNOPSIS
    Displays a simple disk space report for the provided computer name(s). Optionally exports to CSV if a path is provided.
    
    .EXAMPLE
    PS C:\> Get-ATDiskSpace SERVERNAME01,WRKSTN000002
    Computer                                     Drive                                        TotalSize (GB)                              FreeSpace (GB)
    --------                                     -----                                        --------------                              --------------
    SERVERNAME01                                 C:                                           99.66                                       80.56
    SERVERNAME01                                 E:                                           900.00                                      98.02
    SERVERNAME01                                 F:                                           1,073.99                                    225.89
    WRKSTN000002                                 C:                                           99.66                                       81.69
    WRKSTN000002                                 E:                                           900.00                                      344.24
    WRKSTN000002                                 F:                                           900.00                                      581.89
    
    
    .EXAMPLE
    PS C:\> @("SERVERNAME01","WRKSTN000002") | Get-ATDiskSpace -Path C:\DiskReport.csv
    #>
    
        [CmdletBinding()]
        Param(
            [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
            [string[]]
            $ComputerName,
    
            [Parameter(Position=1,Mandatory=$false,ValueFromPipeline=$false)]
            [string]
            $Path
        )
    
        Begin {
            $results = @()
    
            If ($Path -ne '' -and $Path -ne $null) {
                $ExportCSV = $true
            }
            Else {
                $ExportCSV = $false
            }
        }
    
        Process {
            Foreach ($Computer in $ComputerName) {
                $Computer = $Computer.ToUpper()
                Try {
                    $disks = Get-WmiObject win32_logicaldisk -Filter 'Description="Local Fixed Disk"' -ComputerName $Computer -ErrorAction Stop
                }
                Catch {
                    $err = $Error[0].Exception
                    Write-Host "Error enumerating drives on $Computer`: $($err.Message)" -ForegroundColor Red
                    Continue
                }
                If (!$ExportCSV) {
                    $disks | Select-Object -Property `
                        @{N='Computer';E={$Computer}},
                        @{N='Drive';E={$_.DeviceID}},
                        @{N='TotalSize (GB)';E={[double]("{0:N2}" -f (($_.Size)/1GB))}},
                        @{N='FreeSpace (GB)';E={[double]("{0:N2}" -f (($_.FreeSpace)/1GB))}}
                }
                Else {
                    $results += $disks | Select-Object -Property `
                        @{N='Computer';E={$Computer}},
                        @{N='Drive';E={$_.DeviceID}},
                        @{N='TotalSize (GB)';E={[double]("{0:N2}" -f (($_.Size)/1GB))}},
                        @{N='FreeSpace (GB)';E={[double]("{0:N2}" -f (($_.FreeSpace)/1GB))}}
                }
            }
        }
    
        End {
            If ($results) {
                $results
                $results | Export-CSV $Path -NoTypeInformation
                If ($?) {
                    "`nResults exported to $Path"
                }
            }
        }
    }

#Deletes and recreates the machine self-signed RDP certificate, then restarts termservice.
Function AT-RegenRDPcert {
    param([string]$ComputerName)

    $cmd = {
        dir C:\programdata\Microsoft\Crypto\RSA\MachineKeys\f686* | remove-item -force
        dir 'Cert:\LocalMachine\Remote Desktop' | remove-item -Force

        $hash = New-SelfSignedCertificate -CertStoreLocation 'Cert:\localmachine\my' -dnsname "$env:COMPUTERNAME.mycorp.com" | select -ExpandProperty Thumbprint

        $SourceStoreScope = 'LocalMachine'
        $SourceStorename = 'My'

        $SourceStore = New-Object  -TypeName System.Security.Cryptography.X509Certificates.X509Store  -ArgumentList $SourceStorename, $SourceStoreScope
        $SourceStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
        $cert = $SourceStore.Certificates | Where-Object -FilterScript {
            $_.Thumbprint -eq $hash
        }

        $DestStoreScope = 'LocalMachine'
        $DestStoreName = 'Remote Desktop'

        $DestStore = New-Object  -TypeName System.Security.Cryptography.X509Certificates.X509Store  -ArgumentList $DestStoreName, $DestStoreScope
        $DestStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $DestStore.Add($cert)

        $SourceStore.Close()
        $DestStore.Close()


        Get-WmiObject -class "win32_tsgeneralsetting" -namespace root\cimv2\terminalservices -Filter 'TerminalName="RDP-Tcp"' | Set-WmiInstance -Arguments @{SSLCertificateSHA1Hash=$hash}

        Get-Service termservice | Restart-Service -Force
    }

    Invoke-Command -ComputerName $ComputerName -ScriptBlock $cmd
}



Function Add-ATSQLDatabaseToAG {
<#
.SYNOPSIS
Adds a database to the SQL AlwaysOn Availability Group.
This consists of:
    - setting the Recovery Model to 'Full'
    - having recent backup files (.bak and .trn)
    - breaking any existing Availability Group sync
    - restoring the backups to the secondary node(s) with NORECOVERY and with the correct file paths
    - creating the Availability Group sync

For new databases coming from other servers, first place their backups in <BackupFolder>\<database name>\
They will be used to create the initial database on the primary replica.

Requires the SqlServer powershell module:
https://docs.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sql-server-2017

C Anderson / May 2018


.PARAMETER Database
The name of the database to add. The names of the SQL backup, data and log folders for this database must all exactly match the database name.

.PARAMETER SQL_DATA
The path to store the data file(s) in the database's file group.

.PARAMETER SQL_LOGS
The path to store the log file(s) in the database's file group.

.PARAMETER AvailabilityGroupName
The DNS name for the SQL cluster. Must be reachable by the PSProvider at SQLSERVER:\sql\$AvailabilityGroupName\DEFAULT; modify
this cmdlet if you're using a non-default instance name.

.PARAMETER BackupFolder
A UNC path to where the database's backup files are stored.


.EXAMPLE
PS C:\> Add-ATAddSQLDatabaseToAG -Database "testDB" -SQL_DATA "H:\SQL_DATA3\testDB" -SQL_TLOGS "H:\SQL_TLOGS3\testDB"

This command will look for the most recent .BAK and .TRNs from \\SQLAAG\SQLbackups\testDB.
If the primary SQL replica doesn't have the testDB database, it will be restored to the primary first and
new backups will be taken before restoring them on any secondary replicas. Finally, testDB is synchronized
to the Availability Group.

Sample output
-------------

Primary node: SQL01
Secondary node(s): SQL02
Backups found: \\SQL01\SQLbackups\testDB\testDB_2018-05-24 00-00-00.bak \\SQL01\SQLbackups\testDB\testDB_2018-05-24 00-10-00.trn
Removing testDB from SQLAAG.mycorp.com...

LogicalFileName PhysicalFileName                   
--------------- ----------------                   
testDB          H:\SQL_DATA3\testDB\testDB.mdf     
testDB_log      H:\SQL_TLOGS3\testDB\testDB_log.ldf


Restoring testDB to SQL02 with NORECOVERY...
Adding testDB to SQLAAG.mycorp.com...

Name   SynchronizationState IsSuspended IsJoined
----   -------------------- ----------- --------
testDB Synchronized         False       True
#>


    #User variables
    param(      
        [Parameter(Position=0,Mandatory=$true)]
        [string]$Database,
        
        [Parameter(Position=1)]
        [string]$SQL_DATA = "D:\SQL_DATA1\$Database",
        
        [Parameter(Position=2)]
        [string]$SQL_TLOGS = "E:\SQL_TLOGS1\$Database",              

        [string]$AvailabilityGroupName = 'SQLAAG.mycorp.com',
        [string]$BackupFolder = "\\$AvailabilityGroupName\SQLbackups\$Database"
    )

    #Return the paths of the most recent set of SQL backup files (one .BAK plus any subsequent .TRNs)
    Function Get-SQLBackups {
        param(
            [string]$DatabaseName,
            [string]$BackupPath = "\\SQLAAG.mycorp.com\SQLbackups\$DatabaseName"
        )

        If (!(Test-Path $BackupPath)) { Return $null }
        $BackupFiles = @()
        $BackupFiles += dir $BackupPath *.bak | Sort LastWriteTime -Descending | Select -First 1
        $BackupFiles += dir $BackupPath *.trn | ? {$_.LastWriteTime -gt $BackupFiles.LastWriteTime}
        Return $BackupFiles.FullName
    }


    #Determine the primary vs secondary replicas
    Import-Module SqlServer
    $AvailabilityGroup = dir "SQLSERVER:\sql\$AvailabilityGroupName\DEFAULT\AvailabilityGroups"
    $primaryNode = $AvailabilityGroup.PrimaryReplicaServerName
    $secondaryNodes = $AvailabilityGroup.AvailabilityReplicas.Name -notlike "*$primaryNode*"
    Write-Host "Primary node: $primaryNode"
    Write-Host "Secondary node(s): $secondaryNodes"


    #Is this database new to the primary? Add it.
    If (!(Get-Sqldatabase -ServerInstance $primaryNode -Name $Database -ErrorAction SilentlyContinue)) {
        "$Database not found on $primaryNode. Adding..."
        $backupPaths = Get-SQLBackups -DatabaseName $Database -BackupPath $backupFolder
        $bak = $backupPaths | Select-String ".bak"
        "Full backup found: $bak"

        #Get logical filenames from backup
        $filelist = Invoke-Sqlcmd -ServerInstance $primaryNode -Database master -query "RESTORE FILELISTONLY FROM DISK = N'$bak'"

        #Ensure folder structure is in place
        Invoke-Command -ComputerName $primaryNode -ArgumentList $SQL_DATA,$SQL_TLOGS -ScriptBlock `
            {param($SQL_DATA,$SQL_TLOGS); If (!(Test-Path "$SQL_DATA")) { mkdir "$SQL_DATA" }; If (!(Test-Path "$SQL_TLOGS")) { mkdir "$SQL_TLOGS" }}

        #Enumerate database files (.mdf, any .ndfs, .ldf) and remap them to new paths under $SQL_DATA and $SQL_TLOGS
        $DatabaseFiles = @()
        $filelist | ? {$_.Type -ne "L"} | % {
            $newPath = $SQL_DATA + "\" + $_.PhysicalName.Split("\")[-1]
            $DatabaseFiles += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($_.LogicalName,$newPath)
        }
        $DatabaseLogFiles = @()
        $filelist | ? {$_.Type -eq "L"} | % {
            $newPath = $SQL_TLOGS + "\" + $_.PhysicalName.Split("\")[-1]
            $DatabaseLogFiles += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($_.LogicalName,$newPath)
        }
        $DatabaseAllFiles = $DatabaseFiles + $DatabaseLogFiles
        $DatabaseAllFiles | FT

        #Restore .BAK
        Write-Host "Restoring $Database to $primaryNode..."
        Try {
            Restore-SqlDatabase -ServerInstance $primaryNode -Database $Database -BackupFile ($backupPaths | Select-String ".bak") -RelocateFile $DatabaseAllFiles -NoRecovery -ReplaceDatabase -ErrorAction Stop
            #Restore .TRNs
            $backupPaths | Select-String ".trn" | % {
                Restore-SqlDatabase -ServerInstance $primaryNode -Database $Database -BackupFile $_ -NoRecovery -ErrorAction Stop
            }
            #Restore with recovery
            Invoke-Sqlcmd -ServerInstance $primaryNode -Database master -Query "RESTORE DATABASE $Database WITH RECOVERY"
        } Catch {Write-Host $Error[0] -ForegroundColor Red; Return}

        #Check the recovery model of the database. Set to Full.
        Try {
            $DatabaseObject = Get-SqlDatabase -ServerInstance $primaryNode -Name $Database -ErrorAction Stop
        } Catch {Write-Host $Error[0] -ForegroundColor Red; Return}

        If ($DatabaseObject.RecoveryModel -ne 'Full') {
            Write-Host "Setting RecoveryModel of $Database to 'Full'..."
            $DatabaseObject.RecoveryModel = 'Full'
            $DatabaseObject.Alter();
        }

        #Take new backups (in case of compatibility upgrade, recovery model change, etc.
        Write-Host "Taking new backups of $Database on $primaryNode..."
        Backup-SqlDatabase -ServerInstance $primaryNode -Database $Database -BackupFile "$backupFolder\$Database`_$(Get-Date -Format "yyyy-MM-dd hh-mm-ss").bak"
        Backup-SqlDatabase -ServerInstance $primaryNode -Database $Database -BackupAction Log -BackupFile "$backupFolder\$Database`_$(Get-Date -Format "yyyy-MM-dd hh-mm-ss").trn"
    }


    #Check the recovery model of the database. Set to Full.
    Try {
        $DatabaseObject = Get-SqlDatabase -ServerInstance $primaryNode -Name $Database -ErrorAction Stop
    } Catch {Write-Host $Error[0] -ForegroundColor Red; Return}

    If ($DatabaseObject.RecoveryModel -ne 'Full') {
        Write-Host "Setting RecoveryModel of $Database to 'Full'..."
        $DatabaseObject.RecoveryModel = 'Full'
        $DatabaseObject.Alter();
    }


    #Get the paths of the most recent backups. Create new backups if one doesn't exist.
    $backupFolder = "\\$primaryNode\SQLbackups\$Database"
    $backupPaths = Get-SQLBackups -DatabaseName $Database -BackupPath $backupFolder
    If (!($backupPaths -like "*.bak")) {
        Write-Host "No SQL backups found in \\$primaryNode\SQLbackups\$Database"
        Write-Host "Taking a full backup of $Database..."
        If (!(Test-Path $backupFolder)) {
            New-Item -Path $backupFolder -ItemType Directory -Force
        }
        Backup-SqlDatabase -ServerInstance $primaryNode -Database $Database -BackupFile "$backupFolder\$Database`_$(Get-Date -Format "yyyy-MM-dd hh-mm-ss").bak"
        Backup-SqlDatabase -ServerInstance $primaryNode -Database $Database -BackupAction Log -BackupFile "$backupFolder\$Database`_$(Get-Date -Format "yyyy-MM-dd hh-mm-ss").trn"
        $backupPaths = Get-SQLBackups -DatabaseName $Database -BackupPath $backupFolder
    }
    If (!($backupPaths -like "*.bak")) {Return "Failed to detect or create database backups."}
    Else {Write-Host "Backups found: $backupPaths"}


    #Break AvailabilityGroup sync
    $DatabaseSync = dir "SQLSERVER:\sql\$AvailabilityGroupName\DEFAULT\AvailabilityGroups\SQLAAG\AvailabilityDatabases" | ? {$_.Name -eq $Database}
    If ($DatabaseSync.IsJoined) {
        Write-Host "Removing $Database from $AvailabilityGroupName..."
        Suspend-SqlAvailabilityDatabase -InputObject $DatabaseSync -ErrorAction SilentlyContinue
        Remove-SqlAvailabilityDatabase -InputObject $DatabaseSync
        Do {
            Start-Sleep -s 3
            $DatabaseSync = dir "SQLSERVER:\sql\$AvailabilityGroupName\DEFAULT\AvailabilityGroups\SQLAAG\AvailabilityDatabases" | ? {$_.Name -eq $Database}
        } While ($DatabaseSync.IsJoined)
    }


    #Restore database on secondary nodes
    Foreach ($node in $secondaryNodes) {
        #Ensure folder structure is in place
        Invoke-Command -ComputerName $node -ArgumentList $SQL_DATA,$SQL_TLOGS -ScriptBlock `
            {param($SQL_DATA,$SQL_TLOGS); If (!(Test-Path "$SQL_DATA")) { mkdir "$SQL_DATA" }; If (!(Test-Path "$SQL_TLOGS")) { mkdir "$SQL_TLOGS" }}
    

        #Enumerate database files (.mdf, any .ndfs, .ldf) and remap them to new paths under $SQL_DATA and $SQL_TLOGS
        $DatabaseFiles = @()
        $DatabaseObject.FileGroups | % {
            $newPath = $SQL_DATA + "\" + $_.Files.FileName.Split("\")[-1]
            $DatabaseFiles += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($_.Files.Name,$newPath)
        }
        $DatabaseLogFiles = @()
        $DatabaseObject.LogFiles | % {
            $newPath = $SQL_TLOGS + "\" + $_.FileName.Split("\")[-1]
            $DatabaseLogFiles += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($_.Name,$newPath)
        }
        $DatabaseAllFiles = $DatabaseFiles + $DatabaseLogFiles
        $DatabaseAllFiles | FT

        #Restore .BAK
        Write-Host "Restoring $Database to $node with NORECOVERY..."
        Try {
            Restore-SqlDatabase -ServerInstance $node -Database $Database -BackupFile ($backupPaths | Select-String ".bak") -RelocateFile $DatabaseAllFiles -NoRecovery -ReplaceDatabase -ErrorAction Stop
            #Restore .TRNs
            $backupPaths | Select-String ".trn" | % {
                Restore-SqlDatabase -ServerInstance $node -Database $Database -BackupFile $_ -NoRecovery -ErrorAction Stop
            }
        } Catch {Write-Host $Error[0] -ForegroundColor Red; Return}
    }


    #Sync database to Availability Group
    Write-Host "Adding $Database to $AvailabilityGroupName..."
    Add-SqlAvailabilityDatabase -Database $Database -Path $AvailabilityGroup.PSPath
    Foreach ($node in $secondaryNodes) {
        Add-SqlAvailabilityDatabase -Database $Database -Path ($AvailabilityGroup.PSPath -replace "SQLAAG.","$node.")
    }
    Do {
        Start-Sleep -s 3
        $DatabaseSync = dir "SQLSERVER:\sql\$AvailabilityGroupName\DEFAULT\AvailabilityGroups\SQLAAG\AvailabilityDatabases" | ? {$_.Name -eq $Database}
    } While ($DatabaseSync.Name -eq $null)
    $DatabaseSync
}