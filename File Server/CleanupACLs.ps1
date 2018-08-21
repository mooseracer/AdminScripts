Function AT-CleanupACLs {
    <#
        .SYNOPSIS
            Enumerates folders with explicit permissions set for any users/groups specified, or any non-MyCorp domain SIDs, or any orphaned SIDs, and removes them
            from the folder's permissions.

        .DESCRIPTION
            Every folder in the tree that has explicit permissions set will have its ACL examined, and will be flagged if:
                - Any accounts matching the -Account parameter are found
                - Any of the SIDs in the ACL beginning with S-1-5-21* do not match S-1-5-21-3231561394* (non-MyCorp accounts)
                - Any of the SIDs in the ACL cannot be resolved (orphaned SIDs)

            Flagged folders will then have their ownership checked and corrected to the -Owner parameter, as well as
            having -Owner added to the ACL with Full Control.

            All of the accounts found by the search are then removed from the ACL.

            Only folders with explicit permissions in their ACL are searched! An ACL that only contains inherited entries will
            not be flagged, even if those entries are ones you would want removed. Therefore it is important that the root folder
            has explicit permissions that will match your search: when it is corrected its children's inherited ACLs will be
            updated.

            
            Author: Charles Anderson / March 2017

        .PARAMETER Path
            The root folder of the directory tree to be cleaned up.

        .PARAMETER Account
            The accounts or groups to remove from any explicitly defined permissions. Defaults to '*Server Adm*'. Accepts multiple accounts
            in the form @('*account1*','*account2*').

        .PARAMETER Owner
            The account or group that will be set as the owner. Defaults to MyCorp\AT-Server-Admins.

        .EXAMPLE
            AT-CleanupACLs -Path D:\DATA

            Description
            -----------
            Corrects ownership to MyCorp\Server-Admins and removes permissions for *Server Adm* for folders under (and including) D:\DATA.

        .EXAMPLE
            AT-CleanupACLs -Path D:\Projects -Account @('*TRNITS*','*TRNPPA*') -Owner MyCorp\AT-AppServer-Admin

            Description
            -----------
            Corrects ownership to MyCorp\AT-AppServer-Admin and removes permissions for all the TRNITS and TRNPPA accounts.
    #>
    Param (
        [parameter(Mandatory=$True,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [string]$Path,
        [parameter()]
        [string[]]$Account = '*Server Adm*',
        [parameter()]
        [string]$Owner = 'MyCorp\Server-Admins'
    )

    $oldVerbose = $VerbosePreference
    { $VerbosePreference = "continue" }

    #Functions 
        #Activate necessary admin privileges to make changes without NTFS perms
        Try {
            [void][TokenAdjuster]
        } Catch {
            $AdjustTokenPrivileges = @"
            using System;
            using System.Runtime.InteropServices;

                public class TokenAdjuster
                {
                [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
                internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
                ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
                [DllImport("kernel32.dll", ExactSpelling = true)]
                internal static extern IntPtr GetCurrentProcess();
                [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
                internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr
                phtok);
                [DllImport("advapi32.dll", SetLastError = true)]
                internal static extern bool LookupPrivilegeValue(string host, string name,
                ref long pluid);
                [StructLayout(LayoutKind.Sequential, Pack = 1)]
                internal struct TokPriv1Luid
                {
                public int Count;
                public long Luid;
                public int Attr;
                }
                internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
                internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
                internal const int TOKEN_QUERY = 0x00000008;
                internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
                public static bool AddPrivilege(string privilege)
                {
                try
                {
                bool retVal;
                TokPriv1Luid tp;
                IntPtr hproc = GetCurrentProcess();
                IntPtr htok = IntPtr.Zero;
                retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
                tp.Count = 1;
                tp.Luid = 0;
                tp.Attr = SE_PRIVILEGE_ENABLED;
                retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
                retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                return retVal;
                }
                catch (Exception ex)
                {
                throw ex;
                }
                }
                public static bool RemovePrivilege(string privilege)
                {
                try
                {
                bool retVal;
                TokPriv1Luid tp;
                IntPtr hproc = GetCurrentProcess();
                IntPtr htok = IntPtr.Zero;
                retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
                tp.Count = 1;
                tp.Luid = 0;
                tp.Attr = SE_PRIVILEGE_DISABLED;
                retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
                retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                return retVal;
                }
                catch (Exception ex)
                {
                throw ex;
                }
                }
                }
"@
            Add-Type $AdjustTokenPrivileges
        }
        [void][TokenAdjuster]::AddPrivilege("SeRestorePrivilege") #Necessary to set Owner Permissions
        [void][TokenAdjuster]::AddPrivilege("SeBackupPrivilege") #Necessary to bypass Traverse Checking
        [void][TokenAdjuster]::AddPrivilege("SeTakeOwnershipPrivilege") #Necessary to override FilePermissions



        Function Set-Owner {
            <#
                .SYNOPSIS
                    Changes owner of a file or folder to another user or group.

                .DESCRIPTION
                    Changes owner of a file or folder to another user or group.

                .PARAMETER Path
                    The folder or file that will have the owner changed.

                .PARAMETER Account
                    Optional parameter to change owner of a file or folder to specified account.

                    Default value is 'Builtin\Administrators'

                .PARAMETER Recurse
                    Recursively set ownership on subfolders and files beneath given folder.

                .NOTES
                    Name: Set-Owner
                    Author: Boe Prox
                    Version History:
                         1.0 - Boe Prox
                            - Initial Version

                .EXAMPLE
                    Set-Owner -Path C:\temp\test.txt

                    Description
                    -----------
                    Changes the owner of test.txt to Builtin\Administrators

                .EXAMPLE
                    Set-Owner -Path C:\temp\test.txt -Account 'Domain\bprox

                    Description
                    -----------
                    Changes the owner of test.txt to Domain\bprox

                .EXAMPLE
                    Set-Owner -Path C:\temp -Recurse 

                    Description
                    -----------
                    Changes the owner of all files and folders under C:\Temp to Builtin\Administrators

                .EXAMPLE
                    Get-ChildItem C:\Temp | Set-Owner -Recurse -Account 'Domain\bprox'

                    Description
                    -----------
                    Changes the owner of all files and folders under C:\Temp to Domain\bprox
            #>
            [cmdletbinding(
                SupportsShouldProcess = $True
            )]
            Param (
                [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
                [Alias('FullName')]
                [string[]]$Path,
                [parameter()]
                [string]$Account = 'Builtin\Administrators',
                [parameter()]
                [switch]$Recurse
            )
            Begin {
                #Prevent Confirmation on each Write-Debug command when using -Debug
                If ($PSBoundParameters['Debug']) {
                    $DebugPreference = 'Continue'
                }
            }
            Process {
                ForEach ($Item in $Path) {
                    #Write-Verbose "FullName: $Item"
                    #The ACL objects do not like being used more than once, so re-create them on the Process block
                    $DirOwner = New-Object System.Security.AccessControl.DirectorySecurity
                    $DirOwner.SetOwner([System.Security.Principal.NTAccount]$Account)
                    $FileOwner = New-Object System.Security.AccessControl.FileSecurity
                    $FileOwner.SetOwner([System.Security.Principal.NTAccount]$Account)
                    $DirAdminAcl = New-Object System.Security.AccessControl.DirectorySecurity
                    $FileAdminAcl = New-Object System.Security.AccessControl.DirectorySecurity
                    $AdminACL = New-Object System.Security.AccessControl.FileSystemAccessRule('Builtin\Administrators','FullControl','ContainerInherit,ObjectInherit','InheritOnly','Allow')
                    $FileAdminAcl.AddAccessRule($AdminACL)
                    $DirAdminAcl.AddAccessRule($AdminACL)
                    Try {
                        $Item = Get-Item -LiteralPath $Item -Force -ErrorAction Stop
                        If (-NOT $Item.PSIsContainer) {
                            If ($PSCmdlet.ShouldProcess($Item, 'Set File Owner')) {
                                Try {
                                    $Item.SetAccessControl($FileOwner)
                                } Catch {
                                    Write-Warning "Couldn't take ownership of $($Item.FullName)! Taking FullControl of $($Item.Directory.FullName)"
                                    $Item.Directory.SetAccessControl($FileAdminAcl)
                                    $Item.SetAccessControl($FileOwner)
                                }
                            }
                        } Else {
                            If ($PSCmdlet.ShouldProcess($Item, 'Set Directory Owner')) {                        
                                Try {
                                    $Item.SetAccessControl($DirOwner)
                                } Catch {
                                    Write-Warning "Couldn't take ownership of $($Item.FullName)! Taking FullControl of $($Item.Parent.FullName)"
                                    $Item.Parent.SetAccessControl($DirAdminAcl) 
                                    $Item.SetAccessControl($DirOwner)
                                }
                            }
                            If ($Recurse) {
                                [void]$PSBoundParameters.Remove('Path')
                                Get-ChildItem $Item -Force | Set-Owner @PSBoundParameters
                            }
                        }
                    } Catch {
                        Write-Warning "$($Item): $($_.Exception.Message)"
                    }
                }
            }
            End {}
        }


        filter ConvertFrom-SDDLtoSIDs
        {
        <#
        .SYNOPSIS

            Convert a raw security descriptor from SDDL form to a parsed security descriptor.

            Original Author: Matthew Graeber (@mattifestation)

            Modified: C Anderson / MyCorp CTSB / March 2017

        .DESCRIPTION

            ConvertFrom-SDDL generates a parsed security descriptor based upon any string in raw security descriptor definition language (SDDL) form. ConvertFrom-SDDL will parse the SDDL regardless of the type of object the security descriptor represents.

            Modified: removed bulk of the parsing, only want it to return SIDs without trying to resolve them.

        .PARAMETER RawSDDL

            Specifies the security descriptor in raw SDDL form.

        .EXAMPLE

            ConvertFrom-SDDL -RawSDDL 'D:PAI(A;;0xd01f01ff;;;SY)(A;;0xd01f01ff;;;BA)(A;;0x80120089;;;NS)'

        .EXAMPLE

            'O:BAG:SYD:(D;;0xf0007;;;AN)(D;;0xf0007;;;BG)(A;;0xf0005;;;SY)(A;;0x5;;;BA)', 'O:BAG:SYD:PAI(D;OICI;FA;;;BG)(A;OICI;FA;;;BA)(A;OICIIO;FA;;;CO)(A;OICI;FA;;;SY)' | ConvertFrom-SDDL

        .INPUTS

            System.String

            ConvertFrom-SDDL accepts SDDL strings from the pipeline

        .OUTPUTS

            System.Management.Automation.PSObject

        .LINK

            http://www.exploit-monday.com
        #>

            Param (
                [Parameter( Position = 0, Mandatory = $True, ValueFromPipeline = $True )]
                [ValidateNotNullOrEmpty()]
                [String[]]
                $RawSDDL
            )

            # Get reference to sealed RawSecurityDescriptor class
            $RawSecurityDescriptor = [Int].Assembly.GetTypes() | ? { $_.FullName -eq 'System.Security.AccessControl.RawSecurityDescriptor' }

            # Create an instance of the RawSecurityDescriptor class based upon the provided raw SDDL
            try
            {
                $Sddl = [Activator]::CreateInstance($RawSecurityDescriptor, [Object[]] @($RawSDDL))
            }
            catch [Management.Automation.MethodInvocationException]
            {
                throw $Error[0]
            }
            Return $sddl.DiscretionaryAcl | Select -ExpandProperty SecurityIdentifier
        }


        #Enumerate all folders that have explicit permissions set that 1) contain an account specified in $NTAccount, or 2) contain foreign SIDs, or 3) contain orphaned SIDs.
        Function AT-GetFoldersForCleanup([String]$Path, [String[]]$NTAccount) {
            $Return = @()
            [System.IO.DirectoryInfo[]] $folders = @()
            $folders += (Get-Item $Path) #Include root folder
            $folders += Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue | ? { $_.PSIsContainer }  #Not using -Directory on GCI for Powershell v2.0 compatibility
            $folders | % {
                $path = $_.FullName
                Write-Progress -Activity "Enumerating folders..." -Status $path
                $ACL = $_ | Get-Acl
                $AccessRules = $ACL.GetAccessRules($true,$false,[System.Security.Principal.NTAccount])
                $results = @()

                #Search for accounts that match $NTAccount
                Foreach ($string in $NTAccount) {
                    $result = ($AccessRules | ? {$_.IdentityReference -like $string}) | Select -ExpandProperty IdentityReference | Select -ExpandProperty Value
                    $results += $result
                }
            
                #Search for foreign SIDs
                $SIDs = ConvertFrom-SDDLtoSIDs $ACL.Sddl
                $SIDs.Value | % {
                    If ($_ -like 'S-1-5-21*' -and $_ -notlike 'S-1-5-21-3231512345*') { #S-1-5-21-3231512345 = MyCorp.com
                        $SecurityID = New-Object System.Security.Principal.SecurityIdentifier $_
                        $results += $SecurityID.ToString()
                    }
                }

                #Search for orphaned SIDs
                $results += $AccessRules | ? {$_.IdentityReference -like 'S-1-5-21*'} | Select -ExpandProperty IdentityReference | Select -ExpandProperty Value

            
                If ($results) {
                    $ReturnItem = New-Object PSObject -Property @{
                        Path = $Path
                        NTAccount = $results | Sort -Unique
                    }
                    $Return += $ReturnItem
                }
            }
            Return ($Return | Sort {$_.Path.Length}) #Sort by path length so root folders are done first.
        }





    #************ MAIN ************#

    #Enumerate folders with explicit permissions set for any users/groups in $Account, or any non-MyCorp domain SIDs  
    $folders = AT-GetFoldersForCleanup -Path $Path -NTAccount $Account
    $folders


    #Fix the Owner on each folder; add $Owner to ACL
    Foreach ($folder in $folders) {
        #Re-check the current owner, set it to $Owner if different
        $ACL = Get-ACL $folder.Path
        If ($ACL.Owner -ne $Owner) {
            Write-Verbose "Setting owner on $($Folder.path) to $Owner"
            Write-Progress -Activity "Setting Owner..." -Status $folder.Path
            Set-Owner -Path $Folder.Path -Account $Owner -Recurse
        }

        #Add $Owner with Full Control
        $ACL = Get-ACL $folder.Path
        #Check to see if it's already here
        $AccessRules = $ACL.GetAccessRules($true,$true,[System.Security.Principal.NTAccount])
        If ($AccessRules.IdentityReference -notcontains $Owner) {
            $ar = New-Object  system.security.accesscontrol.filesystemaccessrule($Owner,"FullControl","ObjectInherit,ContainerInherit","None","Allow")
            $ACL.AddAccessRule($ar)
            Write-Verbose "Granting FullControl on $($folder.Path) to $Owner"
            $ACL | Set-Acl
        }
    }


    #Remove each NTAccount from the folder's ACL
    Foreach ($folder in $folders) {
        $ACL = Get-Acl $folder.Path
        Write-Progress -Activity "Cleaning up ACLs..." -Status $folder.Path
        $ACEs = @()
        $folder.NTAccount | % {
            #account for SIDs vs Names
            If ($_ -like 'S-1-5-21*') { $SecurityID = New-Object System.Security.Principal.SecurityIdentifier $_ }
            Else { $SecurityID = $_ }
            $ACEs += New-Object System.Security.AccessControl.FileSystemAccessRule($SecurityID,'Read','None','None','Allow')
        }
        $ACEs | % { $ACL.RemoveAccessRuleAll($_) }
        Write-Verbose "Removing all found NTAccounts from ACL of $($Folder.Path)."
        $ACL | Set-Acl
    }


    #Cleanup
    #Remove privileges that had been granted
    [void][TokenAdjuster]::RemovePrivilege("SeRestorePrivilege") 
    [void][TokenAdjuster]::RemovePrivilege("SeBackupPrivilege") 
    [void][TokenAdjuster]::RemovePrivilege("SeTakeOwnershipPrivilege")

    $VerbosePreference = $oldVerbose
}