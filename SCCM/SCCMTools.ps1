#Unless attributed otherwise all functions authored by Charles Anderson
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
Function Add-ATDeviceToSCCMCollection {
<#
    .SYNOPSIS
    Adds a computer to an SCCM collection.
    
    .DESCRIPTION
    Adding a computer to an SCCM collection is typically done to install a specific application.
    The actual download and installation process is entirely handled by SCCM. This script only
    adds the computer to the collection and then triggers a policy retrieval & evaluation cycle
    on the computer's SCCM client.
    
    Multiple computers may be added at once, but only one collection name at a time is supported.

    The SCCM Admin Console is expected to be installed in its default directory.
    
    .EXAMPLE
    PS C:\> Add-ATDeviceToSCCMCollection -ComputerName WRKSTN0001 -CollectionName Adobe
    
    Description
    -----------    
    This will add the computer named 'WRKSTN0001' to the SCCM collection named 'Adobe' and
    tell the SCCM client on WRKSTN0001 to check for its new policy.
        
    Sample output:
    WRKSTN0001 was successfully added to collection 'Adobe'
    SCCM policy retrieval triggered on WRKSTN0001.
    
    .EXAMPLE
    PS C:\> $listOfComputerNames = Get-Content c:\names.txt
    PS C:\> $listOfComputerNames | Add-ATDeviceToSCCMCollection -CollectionName Adobe
    
    Description
    -----------
    The contents of c:\names.txt are stored in $listofComputerNames. The text file should have
    one name per line. They will each be added to the SCCM collection named 'Adobe'. Each
    computer will then be contacted to update its SCCM policy.
    
    #>

    Param(
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        [string[]]
        $ComputerName,

        [Parameter(Position=1,Mandatory=$true)]
        [string]
        $CollectionName
    )    

    Begin {
        $SiteServer = 'SCCM.CorpName.xyz'                               #SCCM management point server FQDN
        $SiteCode = 'XYZ'                                               #SCCM site code

        Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
        If ($ComputerName) {$ComputerName = $ComputerName.ToUpper()}
        $RunPolicy = @()

        If (! [bool](Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue)) {
            Try {
                New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $SiteServer -ErrorAction Stop| Out-Null
            } Catch [UnauthorizedAccessException] {
                    Write-Host "Access denied.`nUser " -NoNewline -ForegroundColor Red
                    Write-Host $env:username -NoNewline -ForegroundColor Yellow
                    Write-Host " does not have sufficient permissions within SCCM." -ForegroundColor Red
                Return
            } Catch {
                Write-Host "Error connecting to $SiteServer`:" -ForegroundColor Yellow
                Write-Error $Error[0]
                Return
            }
        }
        
        $CurrentLocation = Get-Location
        Set-Location "$SiteCode`:"
    }

    Process {
        Foreach ($Computer in $ComputerName) {
            $ResourceID = (Get-CMDevice -Name $Computer).ResourceID
            If ($ResourceID -eq "" -or $ResourceID -eq $null) {
                Write-Host "$Computer is not in SCCM" -ForegroundColor Red
                Continue
            }

            Try {
                Add-CMDeviceCollectionDirectMembershipRule  -CollectionName $CollectionName -ResourceId $ResourceID -ErrorAction SilentlyContinue | Out-Null
            } Catch [ArgumentException] {
                If ($_.Exception.Message -like '*already exists*') {
                    Write-Host "$Computer is already a member of '$CollectionName'" -ForegroundColor Green
                    Continue
                }
            } Catch [System.Management.Automation.ItemNotFoundException] {
                If ($_.Exception.Message -like '*No object corresponds*') {
                    Write-Host "'$CollectionName' is not a valid SCCM collection name." -ForegroundColor Red
                    Continue
                }
            } Catch {
                Write-Host "Error adding $Computer to $CollectionName`:" -ForegroundColor Yellow
                Write-Host $Error[0]
                Continue
            }

            If ((Get-CMDeviceCollectionDirectMembershipRule -CollectionName $CollectionName -ResourceId $ResourceID).RuleName -eq $Computer) {
                Write-Host "$Computer was successfully added to collection '$CollectionName'" -ForegroundColor Green
                $RunPolicy += $Computer
            }
            Else {
                Write-Host "$Computer was not added to '$CollectionName'" -ForegroundColor Red
                Write-Host $Error[0]
                Continue
            }
        }
    }
    End {
        Set-Location $CurrentLocation

        #Trigger policy checks on each computer
        #Sleep to give SCCM a chance to process the new collection member(s)
        Write-Host "Sleeping for 30s... Ctrl-C to skip Machine Policy cycle."
        Start-Sleep -Seconds 1
        Foreach ($Computer in $RunPolicy) {
            #Test connection
            If (! (Test-ATConnection $Computer)) {
                Write-Host "$Computer is currently unreachable." -ForegroundColor Yellow
                Continue
            }
            #Trigger a Machine Policy Retrieval & Evaluation cycle on $Computer's SCCM client
            $SMSCli = [wmiclass] "\\$Computer\root\ccm:SMS_Client"
            If ($SMSCli) {
                $check = $SMSCli.RequestMachinePolicy()
                $check = $SMSCli.EvaluateMachinePolicy()
                If ($?) {
                    Write-Host "SCCM policy retrieval triggered on $Computer."
                }
            }
        }
    }
}


#https://gallery.technet.microsoft.com/scriptcenter/Find-the-Status-of-an-SCCM-e86cc346
Function Get-ATSCCMAppDeloymentStatus {
    <#
    .SYNOPSIS
        This script checks status of a deployed application to members of a SCCM collection or a single SCCM client
    .NOTES
        Requires the SQL PSCX modules here https://sqlpsx.codeplex.com/documentation
    .EXAMPLE
        PS> Get-CmAppDeploymentStatus.ps1 -CollectionName 'My Collection' -ApplicationName MyApplication
        This example enumerates all collection members in the collection 'My Collection' then evaluates each of them
        to see what the status of the application MyApplication is.
    .PARAMETER CollectionName
        The name of the SCCM collection you'd like to query members in
    .PARAMETER Computername
        The name of one or more PCs to check application deployment status
    .PARAMETER ApplicationName
        The name of the application to check the status of
    .PARAMETER SiteServer
        Your SCCM site server
    .PARAMETER SiteCode
        The 3 character SCCM site code
    #>
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [Parameter(ParameterSetName = 'Collection', Mandatory)]
        [string]$CollectionName,
        [Parameter(ParameterSetName = 'Computer', Mandatory)]
        [string[]]$Computername,
        [string]$ApplicationName,
        [string]$SiteServer = 'MYSITESERVER',
        [string]$SiteCode = 'CON'
    )

    begin {
        Set-StrictMode -Version Latest
        
        function Get-CmCollectionMember ($Collection) {
            try {
                $Ns = "ROOT\sms\site_$SiteCode"
                $Col = Get-CimInstance -ComputerName $SiteServer -Class 'SMS_Collection' -Namespace $Ns -Filter "Name = '$Collection'"
                $ColId = $Col.CollectionID;
                Get-CimInstance -Computername $SiteServer -Namespace $Ns -Class "SMS_CM_RES_COLL_$ColId"
            } catch {
                Write-Error $_.Exception.Message
            }
        }
        
        function Get-CmClientAppDeploymentStatus ($Computername,$ApplicationName) {
            $EvalStates = @{
                0 = 'No state information is available';
                1 = 'Application is enforced to desired/resolved state';
                2 = 'Application is not required on the client';
                3 = 'Application is available for enforcement (install or uninstall based on resolved state). Content may/may not have been downloaded';
                4 = 'Application last failed to enforce (install/uninstall)';
                5 = 'Application is currently waiting for content download to complete';
                6 = 'Application is currently waiting for content download to complete';
                7 = 'Application is currently waiting for its dependencies to download';
                8 = 'Application is currently waiting for a service (maintenance) window';
                9 = 'Application is currently waiting for a previously pending reboot';
                10 = 'Application is currently waiting for serialized enforcement';
                11 = 'Application is currently enforcing dependencies';
                12 = 'Application is currently enforcing';
                13 = 'Application install/uninstall enforced and soft reboot is pending';
                14 = 'Application installed/uninstalled and hard reboot is pending';
                15 = 'Update is available but pending installation';
                16 = 'Application failed to evaluate';
                17 = 'Application is currently waiting for an active user session to enforce';
                18 = 'Application is currently waiting for all users to logoff';
                19 = 'Application is currently waiting for a user logon';
                20 = 'Application in progress, waiting for retry';
                21 = 'Application is waiting for presentation mode to be switched off';
                22 = 'Application is pre-downloading content (downloading outside of install job)';
                23 = 'Application is pre-downloading dependent content (downloading outside of install job)';
                24 = 'Application download failed (downloading during install job)';
                25 = 'Application pre-downloading failed (downloading outside of install job)';
                26 = 'Download success (downloading during install job)';
                27 = 'Post-enforce evaluation';
                28 = 'Waiting for network connectivity';
            }
            
            $Params = @{
                'Computername' = $Computername
                'Namespace' = 'root\ccm\clientsdk'
                'Class' = 'CCM_Application'
            }
            if ($ApplicationName) {
                Get-WmiObject @Params | Where-Object { $_.FullName -eq $ApplicationName } | Select-Object PSComputerName, Name, InstallState, ErrorCode, @{ n = 'EvalState'; e = { $EvalStates[[int]$_.EvaluationState] } }, @{ label = 'ApplicationMadeAvailable'; expression = { $_.ConvertToDateTime($_.StartTime) } }
            } else {
                Get-WmiObject @Params | Select-Object PSComputerName, Name, InstallState, ErrorCode, @{ n = 'EvalState'; e = { $EvalStates[[int]$_.EvaluationState] } }, @{ label = 'ApplicationMadeAvailable'; expression = { $_.ConvertToDateTime($_.StartTime) } }
            }
        }
        
        function Test-Ping ($ComputerName) {
            try {
                $oPing = new-object system.net.networkinformation.ping;
                if (($oPing.Send($ComputerName, 200).Status -eq 'TimedOut')) {
                    $false
                } else {
                    $true	
                }
            } catch [System.Exception] {
                $false
            }
        }
    }

    process {
        if ($CollectionName) {
            $Clients = (Get-CmCollectionMember -Collection $CollectionName).Name
        } else {
            $Clients = $Computername
        }
        Write-Verbose "Will query '$($Clients.Count)' clients"
        foreach ($Client in $Clients) {
            try {
                if (!(Test-Ping -ComputerName $Client)) {
                    throw "$Client is offline"
                } else {
                    $Params = @{ 'Computername' = $Client }
                    if ($ApplicationName) {
                        $Params.ApplicationName = $ApplicationName
                    }
                    Get-CmClientAppDeploymentStatus @Params
                }
            } catch {
                Write-Warning $_.Exception.Message
            }
        }
    }
}