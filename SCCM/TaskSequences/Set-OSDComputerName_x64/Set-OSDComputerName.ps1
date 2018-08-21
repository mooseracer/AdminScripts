#https://www.scconfigmgr.com/2013/10/02/prompt-for-computer-name-during-osd-with-powershell/


#Hide the progress window which is always on top
$TSProgressUI = New-Object -ComObject Microsoft.SMS.TSProgressUI
$TSProgressUI.CloseProgressDialog()

Function Load-Form 
{
    $Form.Controls.Add($TBComputerName)
    $Form.Controls.Add($GBComputerName)
    $Form.Controls.Add($ButtonOK)
    $Form.Add_Shown({$Form.Activate()})
    [void] $Form.ShowDialog()
}
 
Function Set-OSDComputerName 
{
    $ErrorProvider.Clear()
    if ($TBComputerName.Text.Length -eq 0) 
    {
        $ErrorProvider.SetError($GBComputerName, "Please enter a computer name.")
    }

    elseif ($TBComputerName.Text.Length -gt 15) 
    {
        $ErrorProvider.SetError($GBComputerName, "Computer name cannot be more than 15 characters.")
    }

    #Validation Rule for computer names.
    elseif ($TBComputerName.Text -match "^[-_]|[^a-zA-Z0-9-_]")
    {
        $ErrorProvider.SetError($GBComputerName, "Computer name invalid, please correct the computer name.")
    }

    else 
    {
        $OSDComputerName = $TBComputerName.Text.ToUpper()
        $OSDComputerName | Out-File C:\ComputerName.txt -Force
        $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
        $TSEnv.Value("OSDComputerName") = "$($OSDComputerName)"
        $Form.Close()
    }
}


#******************MAIN******************
$ValidComputerName = $false

[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

$Global:ErrorProvider = New-Object System.Windows.Forms.ErrorProvider

Do {
    $Form = New-Object System.Windows.Forms.Form
    $FontRatio = $Form.Font.GetHeight() / 12.45019
    $Form.ClientSize = "$([int](250*$FontRatio)),$([int](60*$FontRatio))"
    $Form.StartPosition = "CenterScreen"
    $Form.Text = "Enter Computer Name"
    $Form.ControlBox = $false
    $Form.TopMost = $true

    $TBComputerName = New-Object System.Windows.Forms.TextBox
    $TBComputerName.Location = "$([int](22*$FontRatio)),$([int](15*$FontRatio))"
    $TBComputerName.ClientSize = "$([int](200*$FontRatio)),$([int](50*$FontRatio))"
    $TBComputerName.Font = "Arial,12"

    $Form.KeyPreview = $True
    $Form.Add_KeyDown({if ($_.KeyCode -eq "Enter"){Set-OSDComputerName}})

    Load-Form

    #Check domain for valid computer object
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $ComputerName = "$($TSEnv.Value("OSDComputerName"))"
    $domain = "mycorp.com"
    $lkup = New-Object System.Management.Automation.PSCredential ("sccm.lkup.service", $(ConvertTo-SecureString "B4fr&vUSefrawRap" -AsPlainText -Force))
    $ValidComputerName = Get-ADComputer $ComputerName -Credential $lkup -Server $domain
    #Error categorizing
    If (!$?) {
        Switch ($Error[0].CategoryInfo.Category) {
            "ObjectNotFound" {$MessageBody = "The computer object '$ComputerName' was not found on the domain. Please check the spelling and ensure the object exists."}
            "ResourceUnavailable" {$MessageBody = "Unable to contact the domain $domain. Please check your network connection."}
        }
    }
    If (!$ValidComputerName) {
        Add-Type -AssemblyName PresentationCore,PresentationFramework
        $ButtonType = [System.Windows.MessageBoxButton]::OK
        $MessageIcon = [System.Windows.MessageBoxImage]::Error
        If (!$MessageBody) { $MessageBody = "$($Error[0].Exception)" }
        $MessageTitle = "Error validating computer name"
        [System.Windows.MessageBox]::Show($MessageBody,$MessageTitle,$ButtonType,$MessageIcon)
    }
} While (!$ValidComputerName)