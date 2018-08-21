function ConvertFrom-Json20([Object] $obj)
{
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    return ,$serializer.DeserializeObject($obj)
}


#Path to a share containing the CryptoBlocker scripts
$CryptoBlockerPath = '\\server\share\CryptoBlocker'


#Download current blacklist from fsrm.experiant.ca
$webClient = New-Object System.Net.WebClient
$jsonStr = (Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/get" -UseBasicParsing -Proxy 'http://proxy2.gonet.gov.on.ca:3128' -ProxyUseDefaultCredentials).content
#$jsonStr = $webClient.DownloadString("https://fsrm.experiant.ca/api/v1/get")
$monitoredExtensions = @(ConvertFrom-Json20($jsonStr) | % { $_.filters })

#Remove any whitelisted entries
[string[]]$whitelist = Get-Content \\SCCM\Packages\CryptoBlocker\CryptoBlocker_whitelist.txt
Foreach ($line in $whitelist) {
    If ($monitoredExtensions -contains $line) {
        $index = $monitoredExtensions.IndexOf($line)
        $monitoredExtensions[$index] = $null
    }
}

#Do a diff, show changes. You should review these for anything that could cause an obvious issue.
Get-Content "$CryptoBlockerPath\CryptoBlocker_extensions.txt" | Out-File C:\temp\CryptoBlocker_extensions_old.txt -Encoding utf8 -Force
$monitoredExtensions | Out-File C:\temp\CryptoBlocker_extensions_new.txt -Encoding utf8 -Force
fc.exe C:\temp\CryptoBlocker_extensions_old.txt C:\temp\CryptoBlocker_extensions_new.txt
del C:\temp\CryptoBlocker_extensions_* -Force

#Output to txt
$monitoredExtensions | Out-File "$CryptoBlockerPath\CryptoBlocker_extensions.txt" -Encoding utf8 -Force