$CryptoBlockerPath = '\\server\share\CryptoBlocker'

$deploy = {
    Set-ExecutionPolicy RemoteSigned
    $workingDir = "C:\ProgramData\CryptoBlocker"
    If (!(Test-Path $workingDir)) { New-Item $workingDir -ItemType Directory -Force }
    Copy-Item \\SCCM\Packages\CryptoBlocker\* $workingDir\ -Force
    If ($?) {
        & $workingDir\CryptoBlocker_install.ps1
    }
}

$creds = Get-Credential

#Queries PRTG for a list of file servers. But you can make this list from any source and substitute it below.
ipmo \\SCCM\Packages\CryptoBlocker\PRTGAdminModule.psm1
$fileprint = Get-prtgDevicesInGroup -StartingID 12345 | ? {$_.Tags -like '*fileprintserver*'}
$fileprint = $fileprint | Select -ExpandProperty Host


#Run the installer script on each server.
$fileprint | % {
    #Write-Host "$_ - " -NoNewline
    Invoke-Command -cn $_ -Authentication Credssp -Credential $creds -ScriptBlock $deploy -AsJob
    While ((Get-Job -State Running).Count -ge 30) {
        Start-Sleep -s 5
    }
}

#Show failures
While ((Get-Job -State Running).Count -ge 1) {
    Start-Sleep -s 5
}
Get-Job | ? {$_.HasMoreData -eq $false}