#Brings up a browse for file dialog so they can provide a WIM file

#Hide the progress window which is always on top
$TSProgressUI = New-Object -ComObject Microsoft.SMS.TSProgressUI
$TSProgressUI.CloseProgressDialog()

Do {
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    $browse = New-Object System.Windows.Forms.OpenFileDialog
    $browse.Title = "Select your image (.WIM) file:"
    $browse.InitialDirectory = "D:\"
    $browse.Filter = "WIM files |*.wim"
    $browse.MultiSelect = $false
    $browse.RestoreDirectory = $true
    $browse.AutoUpgradeEnabled = $false
    If ($browse.ShowDialog() -eq 'OK') {
        $Filename = $browse.FileNames
        If (! (Test-Path $Filename)) { MsgBox "An image file must be selected to proceed." }
    }
} While (!$Filename) 

#Save the WIM's path to a Task Sequence variable
$TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
$TSEnv.Value("ImagePath") = "$($Filename)"

& .\Set-OSDComputerName.ps1