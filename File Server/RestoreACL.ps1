#Restores folder permissions from shadow copy.
#Given a VSS snapshot mounted to a folder, clone the NTFS ACLs out of its folder tree onto a live folder structure.
#Modify user variables under #MAIN

#region support code
#Log-It function
Function LogIt {
    param(
    [Parameter(
        Position=1,
        Mandatory=$true,
        ValueFromPipeline=$true)
    ]
    [String]$output,

    [Parameter(
        Position=0,
        Mandatory=$true)
    ]
    [String]$logfile
    )
    If (!(Test-Path $logfile)) { New-Item $logfile -Type file -Force > $null}
    $write = "(" + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + ") $output"
    #While (Test-FileLock $logfile) { Start-Sleep -Milliseconds 10 }
    $write | Out-File $logfile -Append utf8
    $write | Write-Output
}
Set-StrictMode -Version 2.0
function enable-privilege {
 param(
  ## The privilege to adjust. This set is taken from
  ## http://msdn.microsoft.com/en-us/library/bb530716(VS.85).aspx
  [ValidateSet(
   "SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege",
   "SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege",
   "SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege",
   "SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege",
   "SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege",
   "SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege",
   "SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege",
   "SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege",
   "SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege",
   "SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege",
   "SeUndockPrivilege", "SeUnsolicitedInputPrivilege")]
  $Privilege,
  ## The process on which to adjust the privilege. Defaults to the current process.
  $ProcessId = $pid,
  ## Switch to disable the privilege, rather than enable it.
  [Switch] $Disable
 )

 ## Taken from P/Invoke.NET with minor adjustments.
 $definition = @'
 using System;
 using System.Runtime.InteropServices;
  
 public class AdjPriv
 {
  [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
  internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
   ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
  
  [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
  internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
  [DllImport("advapi32.dll", SetLastError = true)]
  internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  internal struct TokPriv1Luid
  {
   public int Count;
   public long Luid;
   public int Attr;
  }
  
  internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
  internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
  internal const int TOKEN_QUERY = 0x00000008;
  internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
  public static bool EnablePrivilege(long processHandle, string privilege, bool disable)
  {
   bool retVal;
   TokPriv1Luid tp;
   IntPtr hproc = new IntPtr(processHandle);
   IntPtr htok = IntPtr.Zero;
   retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
   tp.Count = 1;
   tp.Luid = 0;
   if(disable)
   {
    tp.Attr = SE_PRIVILEGE_DISABLED;
   }
   else
   {
    tp.Attr = SE_PRIVILEGE_ENABLED;
   }
   retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
   retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
   return retVal;
  }
 }
'@

 $processHandle = (Get-Process -id $ProcessId).Handle
 $type = Add-Type $definition -PassThru
 $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable)
}

enable-privilege SeSecurityPrivilege
enable-privilege SeRestorePrivilege
#endregion

#MAIN
$logfile = 'C:\mount\fixACL.log'
$shadowPath = 'c:\mount\Folder757\Public\'
$dest = 'D:\folder\'

#To mount a Shadow Copy to a folder:
#Find the mount point of the date you want then make a symlink to it. You must add a trailing \ to the end!
#VSSADMIN LIST SHADOWS
#MKLINK /D C:\VSS\Folder757 \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy757\
#
#Alternatively, use 'ShadowCopy Functions.ps1':
#Get-VolumeShadowCopy D | ? {$_.Date -gt "4-Apr-2017"} | Select -ExpandProperty Path | Mount-VolumeShadowCopy -Destination C:\mount


#Make a dir tree with robocopy to get around GCI's 260 char path limit
$shadowFolders2 = & robocopy.exe $shadowPath NULL /L /E /NC /NS /NFL /NJH /NJS /XJ 2>&1
$shadowFolders = @()
$shadowFolders2 | % { $shadowFolders += ($_.Trim()) } #Call Trim in a foreach so it works with powershell v2.0
$shadowFolders = $shadowFolders | Sort -Property Length

#Copy the ACL from the shadow folder to the live folder
$shadowFolders | % {
    If ($_ -eq $null -or $_ -eq "") { Return }
    $ACL = Get-ACl $_
    If (!$?) { $Error[0] | LogIt $logfile; Return }
    $oldPath = $_
    $newPath = $oldPath.Replace("$shadowPath","$dest")
    If (Test-Path $newPath) {
        Set-ACL -Path $newPath -AclObject $ACL
        "ACL from $oldPath set on $newPath" | LogIt $logfile
    }
}
