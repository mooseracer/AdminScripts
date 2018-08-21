$msapps = Get-AppxProvisionedPackage -Online | where publisherID -eq "8wekyb3d8bbwe"
$blacklist=gc '.\MS Provisioned Apps Blacklist.txt'
Foreach ($app in $msapps) {
    Foreach ($blacklisted in $blacklist) {
        If ($app.DisplayName -like "*$blacklisted*") {
            $app | Remove-AppxProvisionedPackage -AllUsers
        }
    }
}