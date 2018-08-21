#Copy System32 icons
Copy -Path .\Icons\System32\* -Destination "$env:windir\System32\"

#Copy Desktop shortcuts
Copy -Path .\Shortcuts\Desktop\* -Destination "$env:SystemDrive\Users\Public\Desktop\"

#Copy Start menu shortcuts
Copy -Path .\Shortcuts\StartButton\* -Destination "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\"

#Copy Favourites
Copy -Path .\Shortcuts\Favorites\* -Destination "$env:SystemDrive\Users\Default\Favorites\"

#Pin IE to taskbar
MD "$env:SystemDrive\Users\default\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
Copy -Path ".\Shortcuts\Desktop\Internet Explorer.lnk" -Destination "$env:SystemDrive\Users\default\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Internet Explorer.lnk"

#Add Notepad to Send-To menu
Copy -Path ".\Shortcuts\Notepad.lnk" -Destination "$env:SystemDrive\Users\Default\AppData\Roaming\Microsoft\Windows\SendTo"

