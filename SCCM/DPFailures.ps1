#Function to add the Distribution Point role for a server. If the server already had it, it removes & re-adds the role.
Function Install-ATSCCMDProle {
    param (
        [parameter(Mandatory = $true)]
        [string[]]$Servers,
        [parameter(Mandatory = $false)]
        [switch]$Unattended
    )

    $SiteCode = 'XYZ'                                               #SCCM site code
    $DPgroup = "All Distribution Points"

    Set-Location $SiteCode
    
    Foreach ($server in $Servers) {
        #Figure out which boundary to re-add the DP to
        #Fetch all the site Boundaries and Boundary Groups (but only once, this is slow)
        if ($boundaries.Length -eq 0) {
            Write-Host "Fetching Boundaries..."
            $boundaries = Get-CMBoundary
        }
        if ($boundaryGroups.Length -eq 0) {
            Write-Host "Fetching Boundary Groups..."
            $boundaryGroups = Get-CmBoundaryGroup
        }

        #Find the Boundary that contains $server
        $boundary = ($boundaries | Where-Object {$_.SiteSystems -eq $server}).Value
    
        #If this was a refresh...
        If ($boundary -ne $null) {
            #Find the matching Boundary Group
            $boundaryGroup = $boundaryGroups | Where-Object {$_.Description -like "$boundary*"}

            #Remove DP role
            Get-CMDistributionPoint -SiteSystemServerName $server | Remove-CMDistributionPoint -Force
        }

        #Otherwise it's a new server and subnet so make a new boundary & boundary group.
        #But only if this was called manually.
        ElseIf (!$Unattended) {
            $ip = (Test-Connection $server -count 1).IPV4Address.IPAddressToString
            #Craft a subnet from the IP. We only have .0 and .128
            If ($ip.Split(".")[-1] -lt 129) {
                $subnet = "$($ip.Split(".")[0])." + "$($ip.Split(".")[1])." + "$($ip.Split(".")[2])." + "0"
            }
            Else {
                $subnet = "$($ip.Split(".")[0])." + "$($ip.Split(".")[1])." + "$($ip.Split(".")[2])." + "128"
            }

            #Prompt for boundary description
            Write-Host "Creating new boundary for $server on $subnet"
            $description = Read-Host "Description (i.e. City-Region-Type)"
        
            #Create boundary & boundary group, add boundary to group
            $boundary = New-CMBoundary -DisplayName $description -Value $subnet -BoundaryType IPSubnet
            $boundaryGroup = New-CMBoundaryGroup -Name $description -Description "$subnet/25"
            Add-CMBoundaryToGroup -BoundaryInputObject $boundary -BoundaryGroupInputObject $boundaryGroup
            Get-CMBoundary -BoundaryName $description

            #Create new site system server
            New-CMSiteSystemServer -ServerName $server -SiteCode $SiteCode
        }

        Set-Location C:
        #Reinstall SCCM client
        Install-ATSCCMclient $server

        #Copy NO_SMS_ON_DRIVE.SMS
        Set-Content \\$server\c$\NO_SMS_ON_DRIVE.SMS -Value $null

        #Delete any SMS shares remaining
        $SMSshares = @('SCCMContentLib$','SMS_DP$','SMSPKGD$','SMSSIG$')
        $SMSshares | % {
            #Check for existing share and delete it if found
            $share = Get-WmiObject -Class Win32_Share -ComputerName $server -Filter "name='$_'"
            If ($share) {
                $wmiOutput = $share.Delete()
            }
        }

        Set-Location $SiteCode
        #Add DP role
        Add-CMDistributionPoint -SiteSystemServerName $server -SiteCode $SiteCode -PrimaryContentLibraryLocation D -MinimumFreeSpaceMB 10000 -EnableValidateContent -CertificateExpirationTimeUtc "Friday, February 12, 2112 9:39:00 PM" -InstallInternetServer -EnableAnonymous -EnableBranchCache
        Start-Sleep -s 20
        Write-Host "Trying to add group $DPgroup... "
        Add-CMDistributionPointToGroup -DistributionPointName $server -DistributionPointGroupName $DPgroup
        While ($? -eq $False) { Write-Host "Trying again... "; Start-Sleep -s 20; Add-CMDistributionPointToGroup -DistributionPointName $server -DistributionPointGroupName $DPgroup }
        Write-Host "Complete."
    }
}


#http://www.powershellmagazine.com/2013/07/08/pstip-converting-a-string-to-a-system-datetime-object/
function Convert-DateString ([String]$Date, [String[]]$Format)
{
   $result = New-Object DateTime
 
   $convertible = [DateTime]::TryParseExact(
      $Date,
      $Format,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::None,
      [ref]$result)
 
   if ($convertible) { $result }
}

#Log-It function: adds a timestamp and appends to a file.
Function LogIt {
    param(
    [Parameter(
        Position=1,
        Mandatory=$true,
        ValueFromPipeline=$true)
    ]
    [String]$output,

    [Parameter(
        Position=0,
        Mandatory=$true)
    ]
    [String]$logfile
    )
    If (!(Test-Path $logfile)) { New-Item $logfile -Type file -Force > $null}
    $write = "(" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ") $output"
    $write | Out-File $logfile -Append utf8
    $write | Write-Output
}



<#Script to parse distmgr.log for failures to connect to a Distribution Point, typically caused by either
WAN outages or a server refresh.

Servers that are pingable are assumed to have been refreshed and will have Install-ATSCCMDProle called on them.

Meant to be run once per day as a scheduled task on the SCCM MP.
#>
$SiteCode = 'XYZ'                                               #SCCM site code
$logfile = "C:\scripts\Failed DP Check.log"
$ErrorCountLimit = 10 #An error count >= than $ErrorCountLimit will trigger a DP role reinstall
$SCCMlogPath = "C:\Program Files\Microsoft Configuration Manager\Logs"


$distmgr = Get-Content "$SCCMlogPath\distmgr.log"
$PkgXferMgr = Get-Content "$SCCMlogPath\PkgXferMgr.log"
$failedServers = @()
$ToReinstall = @()
$now = Get-Date


#Greps log file for "Failed to connect to (servername FQDN) <(timestamp)", captures the servername and timestamp
$regex = 'Failed to connect to\s*\\*(\w*.*).<(\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2})'

$ConnectWMIEx = $distmgr | Select-String "DPConnection::ConnectWMIEx()"
$ConnectWMIEx | Foreach-Object {
    $_ -match $regex | Out-Null
    If (!$matches) { Return }
    $server = $matches[1]
    #If the error is <18 hours old, add $server to $failedServers
    $timestamp = Convert-DateString -Date $matches[2] -Format "MM-dd-yyyy HH:mm:ss"
    If (($now - $timestamp).AddHours -lt 18) {
        $failedServers += $server
    }
}

$CWmi = $PkgXferMgr | Select-String -Pattern "CWmi::Connect\(\)\sfailed"
$CWmi | Foreach-Object {
    $_ -match $regex | Out-Null
    If (!$matches) { Return }
    $server = $matches[1]
    #If the error is <18 hours old, add $server to $failedServers
    $timestamp = Convert-DateString -Date $matches[2] -Format "MM-dd-yyyy HH:mm:ss"
    If (($now - $timestamp).AddHours -lt 18) {
        $failedServers += $server
    }
}

$CWmi = $distmgr | Select-String -Pattern "CWmi::Connect\(\)\sfailed"
$CWmi | Foreach-Object {
    $_ -match $regex | Out-Null
    If (!$matches) { Return }
    $server = $matches[1]
    #If the error is <18 hours old, add $server to $failedServers
    $timestamp = Convert-DateString -Date $matches[2] -Format "MM-dd-yyyy HH:mm:ss"
    If (($now - $timestamp).AddHours -lt 18) {
        $failedServers += $server
    }
}
$failedServers | Sort -Unique | ForEach-Object {
    If (($failedServers | Select-String $_).Count -ge $ErrorCountLimit) {
        $ToReinstall += $_
    }
}

If ($ToReinstall.Count -lt 1) {
	"No failed DPs detected." | LogIt $logfile
	Return
}
Else {
    "Failed DPs detected:" | LogIt $logfile
    $ToReinstall | LogIt $logfile
}

$ToReinstall | Foreach-Object {
    If (Test-Connection $_ -Count 4) {
        Set-Location "$SiteCode`:"
        $SCCMDPInstall = Install-ATSCCMDProle $_ -Unattended
        #Log results
        Set-Location C:
        "Install-ATSCCMDProle $_" | LogIt $logfile
        $SCCMDPInstall | LogIt $logfile
    }
}

