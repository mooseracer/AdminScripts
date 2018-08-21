#Sensor for measuring the number of completed backup jobs from Arcserve over the last period of $days.
#Incomplete jobs are counted as complete. A max of one job per day is counted.
#Works on Arcserve 16.5, 17 (16.0 fails)
#
# C Anderson / June 2017

$ComputerName = "$($args[0])"
[int]$days = "$($args[1])"
$shortComputerName = $ComputerName.Split(".")[0]
$ServiceAccount = 'MyCorp\PRTG.SERVICE.ACCOUNT'
[ScriptBlock]$query1 = {param($days = 7); & "C:\Program Files (x86)\ca\arcserve backup\ca_dbmgr.exe" -show jobs -completed -last "$days" days}
[ScriptBlock]$query2 = {param($days = 7); & "C:\Program Files (x86)\ca\arcserve backup\ca_dbmgr.exe" -show jobs -incomplete -last "$days" days}
[ScriptBlock]$jobListquery = { & "C:\Program Files (x86)\ca\arcserve backup\ca_qmgr.exe" -list }
[ScriptBlock]$ca_auth = { 
    param($ServiceAccount,$shortComputerName)
    & "C:\Program Files (x86)\ca\arcserve backup\ca_auth.exe" -equiv add $ServiceAccount $shortComputerName caroot caroot caroot
}

Try {
    $PSSessionOptions = New-PSSessionOption -OpenTimeout 30000 -OperationTimeout 60000 -IdleTimeout 60000 -CancelTimeout 10000
    $session = New-PSSession -ComputerName $ComputerName -SessionOption $PSSessionOptions -ErrorAction Stop
} Catch {
    Write-Host "-1:$($Error[0])"
    Exit -1
}


#Query arcserve for completed jobs within the last $days
$result = Invoke-Command -Session $session -ScriptBlock $query1 -ArgumentList $days
If (!($?)) {
    Write-Host "-1:$($Error[0])"
    Exit -1
}
ElseIf ($result -like "*not validated*") {
    #Add $ServiceAccount to arcserve with caroot access
    $result = Invoke-Command -Session $session -ScriptBlock $ca_auth -ArgumentList $ServiceAccount, $shortComputerName
    $result = Invoke-Command -Session $session -ScriptBlock $query1 -ArgumentList $days
}
If ($result -notlike "*Jobs!") {
    $JobResult = $result
}
#Query arcserve for incomplete jobs within the last $days
$result = Invoke-Command -Session $session -ScriptBlock $query2 -ArgumentList $days
If ($result -notlike "*Jobs!") {
    $JobResult += $result
}
#We'll deal with $JobResult at the end.


#Enumerate and parse job list, raise errors for scheduled jobs on Hold or a lack of jobs ready/running.
$jobList = Invoke-Command -Session $session -ScriptBlock $jobListquery | Select-String "BACKUP|ROTATION" | Select-String -NotMatch "Makeup"
Remove-PSSession -Session $session

$ReadyJobCount = 0
$HoldJobCount = 0

[regex]$regex = @"
.*(\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}:\d{2})
"@

Foreach ($job in $jobList) {
    If ($job -match $regex) {
        $jobdate = Get-Date $Matches[1]
        If ((($job -match "READY") -and $jobdate -ge (Get-Date))`
            -or ($job -match "ACTIVE")) {
                $ReadyJobCount++
        }
        If ($job -match "HOLD" -and $jobdate -ge (Get-Date)) {
            $HoldJobCount++
        }
    }
}

If ($ReadyJobCount -lt 1) {
    Write-Host "-1:$ReadyJobCount jobs are scheduled to run."
    Exit -1
}
If ($HoldJobCount -gt 0) {
    If ($HoldJobCount -eq 1) { $s = "" } Else { $s = "s" }
    Write-Host "-1:$HoldJobCount scheduled job$s on hold."
    Exit -1
}


#Handle $JobResult to estimate job completions.
$JobResult = $JobResult | Select-String "BACKUP|ROTATION"
If ($JobResult -eq "" -or $JobResult -eq $null) {  #No completed jobs
    Write-Host "0:OK"
    Exit 0
}
Else { #Return the number of completed jobs
    #grep MM/dd/yyyy and eliminate duplicates, we only want to count one completion per day
    [regex]$regex = @"
.*(\d{1,2}\/\d{1,2}\/\d{4}) 
"@
    $dates = @()
    $JobResult | % {
        If ($_ -match $regex) {
            $dates += $Matches[1] 
        }
    }
    $CompletedCount = ($dates | Select -Unique).Count
}
Write-Host "$CompletedCount`:OK"
Exit 0