Function Mount-VolumeShadowCopy {
<#
    .SYNOPSIS
        Mount a volume shadow copy.
     
    .DESCRIPTION
        Mount a volume shadow copy.
      
    .PARAMETER ShadowPath
        Path of volume shadow copies submitted as an array of strings
      
    .PARAMETER Destination
        Target folder that will contain mounted volume shadow copies
              
    .EXAMPLE
        Get-CimInstance -ClassName Win32_ShadowCopy | 
        Mount-VolumeShadowCopy -Destination C:\VSS -Verbose
 
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
    [ValidatePattern('\\\\\?\\GLOBALROOT\\Device\\HarddiskVolumeShadowCopy\d{1,}')]
    [Alias("DeviceObject")]
    [String[]]$ShadowPath,
 
    [Parameter(Mandatory)]
    [ValidateScript({
        Test-Path -Path $_ -PathType Container
    }
    )]
    [String]$Destination
)
Begin {
    Try {
        $null = [mklink.symlink]
    } Catch {
        Add-Type @"
        using System;
        using System.Runtime.InteropServices;
  
        namespace mklink
        {
            public class symlink
            {
                [DllImport("kernel32.dll")]
                public static extern bool CreateSymbolicLink(string lpSymlinkFileName, string lpTargetFileName, int dwFlags);
            }
        }
"@
    }

    $ShadowCopies = Get-CimInstance Win32_ShadowCopy
    $Volumes = Get-CimInstance Win32_Volume

}
Process {
 
    $ShadowPath | ForEach-Object -Process {
 
        if ($($_).EndsWith("\")) {
            $sPath = $_
        } else {
            $sPath = "$($_)\"
        }

        $Date = $null
        $ShadowCopy = $ShadowCopies | ? { $_.DeviceObject -eq ($sPath.Substring(0,$sPath.Length-1)) } | Select VolumeName,InstallDate
        If ($shadowCopy) { $DriveLetter = $Volumes | ? { $_.DeviceID -eq $ShadowCopy.VolumeName } | Select -ExpandProperty DriveLetter }
        If ($shadowCopy -and $DriveLetter) { $Date = "$(Get-Date $ShadowCopy.InstallDate -Format "ddMMyyyy-hhmm")" }

        If ($Date) { $tPath = Join-Path -Path $Destination -ChildPath "Drive$($DriveLetter.Split(":")[0])-$Date" }
        Else {
            $tPath = Join-Path -Path $Destination -ChildPath (
            '{0}-{1}' -f (Split-Path -Path $sPath -Leaf),[GUID]::NewGuid().Guid
            )
        }

        try {
            if (
                [mklink.symlink]::CreateSymbolicLink($tPath,$sPath,1)
            ) {
                Write-Verbose -Message "Successfully mounted $sPath to $tPath"
            } else  {
                Write-Warning -Message "Failed to mount $sPath"
            }
        } catch {
            Write-Warning -Message "Failed to mount $sPath because $($_.Exception.Message)"
        }
    }
}
End {}
}

Function Dismount-VolumeShadowCopy {
<#
    .SYNOPSIS
        Dismount a volume shadow copy.
     
    .DESCRIPTION
        Dismount a volume shadow copy.
      
    .PARAMETER Path
        Path of volume shadow copies mount points submitted as an array of strings
      
    .EXAMPLE
        Get-ChildItem -Path C:\VSS | Dismount-VolumeShadowCopy -Verbose
         
 
#>
 
[CmdletBinding()]
Param(
    [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
    [Alias("FullName")]
    [string[]]$Path
)
Begin {
}
Process {
    $Path | ForEach-Object -Process {
        $sPath =  $_
        if (Test-Path -Path $sPath -PathType Container) {
            if ((Get-Item -Path $sPath).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                try {
                    [System.IO.Directory]::Delete($sPath,$false) | Out-Null
                    Write-Verbose -Message "Successfully dismounted $sPath"
                } catch {
                    Write-Warning -Message "Failed to dismount $sPath because $($_.Exception.Message)"
                }
            } else {
                Write-Warning -Message "The path $sPath isn't a reparsepoint"
            }
        } else {
            Write-Warning -Message "The path $sPath isn't a directory"
        }
     }
}
End {}
}




Function Get-VolumeShadowCopy {
<#
    .SYNOPSIS
        Enumerates available volume shadow copies.
     
    .DESCRIPTION
        Enumerates available volume shadow copies.
      
    .PARAMETER DriveLetter
        Drive letter of the volume you want to get shadow copies for.
      
    .EXAMPLE
        Get-VolumeShadowCopy -DriveLetter D

    .EXAMPLE
        (Get-VolumeShadowCopy D)[-1].Path | Mount-VolumeShadowCopy C:\temp

    .EXAMPLE
        Get-VolumeShadowCopy D | ? {$_.Date -gt "4-Apr-2017"} | Select -ExpandProperty Path | Mount-VolumeShadowCopy -Destination C:\temp
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
    [Alias("DriveLetter")]
    [string[]]$Drive
)
Begin {
    $Results = @()
    $AllShadowCopies = Get-CimInstance Win32_ShadowCopy
}
Process {
    $volume = Get-CimInstance Win32_Volume | ? { $_.DriveLetter -like "$Drive*" } | Select DriveLetter,DeviceID
    $ShadowCopies = $AllShadowCopies | ? { $_.VolumeName -eq $volume.DeviceID }
    $ShadowCopies | % {
        $Result = New-Object -TypeName PSObject -Property @{
            Drive = $volume.DriveLetter
            Date = $_.InstallDate
            Path = $_.DeviceObject
        }
        $Results += $Result
    }

}
End { Return $Results}
}