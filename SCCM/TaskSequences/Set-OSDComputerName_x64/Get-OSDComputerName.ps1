If (Test-Path C:\ComputerName.txt) {
    $OSDComputerName = (Get-Content C:\ComputerName.txt).Trim().ToUpper()
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $TSEnv.Value("OSDComputerName") = "$($OSDComputerName)"
    Remove-Item C:\ComputerName.txt -Force
}
Else { Exit 1 }