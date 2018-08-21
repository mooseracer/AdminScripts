#Sets the default wallpaper. Adapted from: https://smsagent.wordpress.com/2015/06/16/setting-the-default-windows-wallpaper-during-os-deployment/

#Get the TS variables
$tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
$OSDTargetSystemRoot =  $tsenv.Value('OSDTargetSystemRoot')
$OSDTargetSystemDrive = $tsenv.Value('OSDTargetSystemDrive')

#Copy Wallpapers and lock screen image
Copy -Path .\wallpapers -Destination "$OSDTargetSystemDrive\Users\Public\Pictures" -Recurse
Copy -Path .\img100.jpg -Destination "$OSDTargetSystemRoot\Web\Screen\img100.jpg" -Force

#Choose and set desktop wallpaper
function Get-ScreenResolution {            
[void] [Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")            
[void] [Reflection.Assembly]::LoadWithPartialName("System.Drawing")            
$Screens = [system.windows.forms.screen]::AllScreens            
    foreach ($Screen in $Screens) {
     $DeviceName = $Screen.DeviceName
     $Width  = $Screen.Bounds.Width
     $Height  = $Screen.Bounds.Height
     $IsPrimary = $Screen.Primary

     $OutputObj = New-Object -TypeName PSobject
     $OutputObj | Add-Member -MemberType NoteProperty -Name DeviceName -Value $DeviceName
     $OutputObj | Add-Member -MemberType NoteProperty -Name Width -Value $Width
     $OutputObj | Add-Member -MemberType NoteProperty -Name Height -Value $Height
     $OutputObj | Add-Member -MemberType NoteProperty -Name IsPrimaryMonitor -Value $IsPrimary
     $OutputObj
    }
}

#Find aspect ratio
$ScreenRes = Get-ScreenResolution | ? {$_.IsPrimaryMonitor -eq $true}
$ratio = "{0:N1}" -f $(($ScreenRes.Width / $ScreenRes.Height))
Switch ($ratio) {
    1.8 {$wallpaper = "1920x1080"} #16:9
    1.6 {$wallpaper = "1920x1200"} #16:10
    1.3 {$wallpaper = "1024x768"} #4:3
}

#Get a random wallpaper
$wallpaperPath = (Get-Random (dir "$OSDTargetSystemDrive\Users\Public\Pictures\wallpapers\$wallpaper" -Filter *.jpg)).FullName
 
# Rename default wallpapers
Rename-Item $OSDTargetSystemRoot\Web\Wallpaper\Windows\img0.jpg img1.jpg -Force
DIR $OSDTargetSystemRoot\Web\4K\Wallpaper\Windows | % { Rename-Item $_.FullName -NewName "$($_.Name -replace "img0","img1")" }
 
# Copy new default wallpaper
Copy-Item $wallpaperPath $OSDTargetSystemRoot\Web\Wallpaper\Windows\img0.jpg -Force
Copy-Item $wallpaperPath $OSDTargetSystemRoot\Web\4K\Wallpaper\Windows\img0.jpg -Force
Copy-Item $wallpaperPath "$OSDTargetSystemRoot\Web\4K\Wallpaper\Windows\img0_$($ScreenRes.Width)x$($ScreenRes.Height).jpg" -Force