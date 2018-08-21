<#
Script to automatically update the Membership Query Rules for all the 'Region-x' device collections in SCCM.
The rules are based on the names of the Boundaries. Make sure all Boundaries you want included have one of
-N-,-S-,-E-,-W- in their name.

#>
$Regions = @('Region-N','Region-S','Region-E','Region-W')

Function Set-ATSCCMRegionCollections {
    param ($region)

    $SiteServer = 'SCCM.CorpName.xyz'
    $SiteCode = 'XYZ'

    Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1" #where you have CM12 installed  
    CD $SiteCode`:

    $regionSuffix = $region.Split("-")[-1]
    $IPSubnets = Get-CMBoundary | Where-Object { $_.DisplayName -like "*-$regionSuffix-*"} | Select -ExpandProperty Value
    $IPRanges = @()

    If ($IPSubnets.Count -lt 1) { Throw "No boundaries found that match *-$regionSuffix-*" }


    #Build QueryExpression based on values returned from Get-CMBoundary, which should be mostly IP Subnets
    $QueryExpression = 'SELECT SMS_R_SYSTEM.Name from SMS_R_System where SMS_R_System.IPSubnets in ('

    Foreach ($IP in $IPSubnets) {
        If ($IP -eq "" -or $IP -eq $null) { Continue }
        #Add IP Ranges to a different list
        If ($IP.Contains('-')) {
            $IPRanges += $IP
        }
        Else {
            $QueryExpression += """$IP"","
        }
    }
    $QueryExpression = $QueryExpression.Remove($QueryExpression.Length-1)
    $QueryExpression += ')'

    #Build a 2nd Query Expression for any IP Ranges
    If ($IPRanges.Count -gt 0) {
        $RangesQueryExpression = 'SELECT * from SMS_R_System inner join SMS_G_System_NETWORK_ADAPTER_CONFIGURATION on SMS_G_System_NETWORK_ADAPTER_CONFIGURATION.ResourceId = SMS_R_System.ResourceId where '
        For ($i=0; $i -lt $IPRanges.Count; $i++) {
            $LowerIP = $IPRanges[$i].Split('-')[0]
            $UpperIP = $IPRanges[$i].Split('-')[-1]
            $RangesQueryExpression += "(SMS_G_System_NETWORK_ADAPTER_CONFIGURATION.IPAddress >= ""$LowerIP"" and "
            $RangesQueryExpression += "SMS_G_System_NETWORK_ADAPTER_CONFIGURATION.IPAddress <= ""$UpperIP"")"
            If ($i+1 -gt $IPRanges.Count) {
                $RangesQueryExpression += " or "
            }
        }
        $RangesQueryExpression += " and SMS_G_System_NETWORK_ADAPTER_CONFIGURATION.DHCPEnabled = 1"
    }


    #Get the collection
    $collection = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name='$region'"
    $collection.Get()

    #Remove any old rules
    Foreach ($Rule in $collection.CollectionRules) {
        $Collection.DeleteMembershipRule($Rule)
    }
    $collection.Get()

    #Build new rules using Query Expression(s)
    If ($IPSubnets.Count -gt 0) {
        $SubnetRule = ([WmiClass]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_CollectionRuleQuery").CreateInstance() 
        $SubnetRule.QueryExpression = $QueryExpression
        $SubnetRule.RuleName = "$region-Subnets"
        $collection.CollectionRules += $SubnetRule.PSObject.BaseObject
    }

    If ($IPRanges.Count -gt 0) {
        $RangesRule = ([WmiClass]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_CollectionRuleQuery").CreateInstance() 
        $RangesRule.QueryExpression = $RangesQueryExpression
        $RangesRule.RuleName = "$region-Ranges"
        $collection.CollectionRules += $RangesRule.PSObject.BaseObject
    }


    #Add the new rules
    $collection.Put()

    #Display new rules for verification
    $collection = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name='$region'"
    $collection.Get()
    $collection.CollectionRules
    $collection.RequestRefresh()
}

$Regions | ForEach-Object { Set-ATSCCMRegionCollections $_ }
