#Grants DCOM Launch & Activation permissions on ShellServiceHost to LOCAL SERVICE account.
#Prevents error 10016 in System eventlog.
#
#C Anderson / Oct 2017


function Take-Permissions {
    # Developed for PowerShell v4.0
    # Required Admin privileges
    # Links:
    #   http://shrekpoint.blogspot.ru/2012/08/taking-ownership-of-dcom-registry.html
    #   http://www.remkoweijnen.nl/blog/2012/01/16/take-ownership-of-a-registry-key-in-powershell/
    #   https://powertoe.wordpress.com/2010/08/28/controlling-registry-acl-permissions-with-powershell/

    param($rootKey, $key, [System.Security.Principal.SecurityIdentifier]$sid = 'S-1-5-32-545', $recurse = $true)

    switch -regex ($rootKey) {
        'HKCU|HKEY_CURRENT_USER'    { $rootKey = 'CurrentUser' }
        'HKLM|HKEY_LOCAL_MACHINE'   { $rootKey = 'LocalMachine' }
        'HKCR|HKEY_CLASSES_ROOT'    { $rootKey = 'ClassesRoot' }
        'HKCC|HKEY_CURRENT_CONFIG'  { $rootKey = 'CurrentConfig' }
        'HKU|HKEY_USERS'            { $rootKey = 'Users' }
    }

    ### Step 1 - escalate current process's privilege
    # get SeTakeOwnership, SeBackup and SeRestore privileges before executes next lines, script needs Admin privilege
    $import = '[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(ulong a, bool b, bool c, ref bool d);'
    $ntdll = Add-Type -Member $import -Name NtDll -PassThru
    $privileges = @{ SeTakeOwnership = 9; SeBackup =  17; SeRestore = 18 }
    foreach ($i in $privileges.Values) {
        $null = $ntdll::RtlAdjustPrivilege($i, 1, 0, [ref]0)
    }

    function Take-KeyPermissions {
        param($rootKey, $key, $sid, $recurse, $recurseLevel = 0)

        ### Step 2 - get ownerships of key - it works only for current key
        $regKey = [Microsoft.Win32.Registry]::$rootKey.OpenSubKey($key, 'ReadWriteSubTree', 'TakeOwnership')
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetOwner($sid)
        $regKey.SetAccessControl($acl)

        <#
        ### Step 3 - enable inheritance of permissions (not ownership) for current key from parent
        $acl.SetAccessRuleProtection($false, $false)
        $regKey.SetAccessControl($acl)

        ### Step 4 - only for top-level key, change permissions for current key and propagate it for subkeys
        # to enable propagations for subkeys, it needs to execute Steps 2-3 for each subkey (Step 5)
        if ($recurseLevel -eq 0) {
            $regKey = $regKey.OpenSubKey('', 'ReadWriteSubTree', 'ChangePermissions')
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule($sid, 'FullControl', 'ContainerInherit', 'None', 'Allow')
            $acl.ResetAccessRule($rule)
            $regKey.SetAccessControl($acl)
        }
        #>


        ### Step 5 - recursively repeat steps 2-5 for subkeys
        if ($recurse) {
            foreach($subKey in $regKey.OpenSubKey('').GetSubKeyNames()) {
                Take-KeyPermissions $rootKey ($key+'\'+$subKey) $sid $recurse ($recurseLevel+1)
            }
        }
    }

    Take-KeyPermissions $rootKey $key $sid $recurse
}



#User variables
$paths = @(
        'CLSID\{6B3B8D23-FA8D-40B9-8DBD-B950333E2C52}',
        'AppID\{4839DDB7-58C2-48F5-8283-E1D1807D0D7D}'
        )
$serviceAccount = "NT AUTHORITY\LOCAL SERVICE"
$localAdmins = "BUILTIN\Administrators"


#Take ownership & permissions of reg keys
Foreach ($path in $paths) {
    #Current user's SID
    $userObj = New-Object System.Security.Principal.NTAccount("SYSTEM")
    $userSID = $userObj.Translate([System.Security.Principal.SecurityIdentifier])

    #Take ownership
    Take-Permissions -rootKey 'HKCR' -key $path -sid $userSID

    #Set permissions
    $regKey = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey("$path",[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::ChangePermissions)
    $acl = $regKey.GetAccessControl()
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule($serviceAccount,"FullControl","ObjectInherit,ContainerInherit","None","Allow")
    $acl.SetAccessRule($rule)
    $regKey.SetAccessControl($acl)

    $rule = New-Object System.Security.AccessControl.RegistryAccessRule($localAdmins,"FullControl","ObjectInherit,ContainerInherit","None","Allow")
    $acl.SetAccessRule($rule)
    $regKey.SetAccessControl($acl)
    $regKey.Close()
}



#Set DCOM permissions
#http://stackoverflow.com/questions/11363342/change-dcom-config-security-settings-using-powershell
$appid = "{4839DDB7-58C2-48F5-8283-E1D1807D0D7D}"
$app = get-wmiobject -query ('SELECT * FROM Win32_DCOMApplicationSetting WHERE AppId = "' + $appid + '"') -enableallprivileges
$trustee = ([wmiclass] 'Win32_Trustee').CreateInstance()
$trustee.Domain = $serviceAccount.Split('\')[0]
$trustee.Name = $serviceAccount.Split('\')[1]
$fullControl = 31
$localLaunchActivate = 11

#Launch permissions
$sdRes = $app.GetLaunchSecurityDescriptor()
$sd = $sdRes.Descriptor
$ace = ([wmiclass] 'Win32_ACE').CreateInstance()
$ace.AccessMask = $localLaunchActivate
$ace.AceFlags = 0
$ace.AceType = 0
$ace.Trustee = $trustee
[System.Management.ManagementBaseObject[]] $newDACL = $sd.DACL + @($ace)
$sd.DACL = $newDACL
$app.SetLaunchSecurityDescriptor($sd)

<#
#Access permissions
$sdRes = $app.GetAccessSecurityDescriptor()
$sd = $sdRes.Descriptor
$ace = ([wmiclass] 'Win32_ACE').CreateInstance()
$ace.AccessMask = $localLaunchActivate
$ace.AceFlags = 0
$ace.AceType = 0
$ace.Trustee = $trustee
[System.Management.ManagementBaseObject[]] $newDACL = $sd.DACL + @($ace)
$sd.DACL = $newDACL
$app.SetAccessSecurityDescriptor($sd)
#>