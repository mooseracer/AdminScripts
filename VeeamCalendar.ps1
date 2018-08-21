<#
List of the DayOfWeek/WeekOfMonth schedules of all the Active Full, Tape and SureBackup jobs.

C Anderson / December 2015
#>

#"If there are no Administrative rights, it will display a popup window asking user for Admin rights"
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-noprofile -windowstyle hidden & '" + $myinvocation.mycommand.definition + "'"
    Start-Process "$psHome\powershell.exe" -Verb runAs -ArgumentList $arguments
    break
}



Add-PSSnapin VeeamPSSnapIn

#Create a JobSchedules collection composed of all the Active Fulls and Tape jobs.
    $JobSchedules = @()
    #Get all jobs that have an Active Full scheduled
    $FullJobs = Get-VBRJob | ? { $_.BackupStorageOptions.EnableFullBackup -eq $True }
    Foreach ($Job in $FullJobs) {
        $JobSchedule = New-Object System.Object
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Name -Value $Job.Name
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Type -Value "Full"
        $JobSchedule | Add-Member -MemberType NoteProperty -Name DayOfWeek -Value $Job.BackupTargetOptions.FullBackupMonthlyScheduleOptions.DayOfWeek
        Switch ($Job.BackupTargetOptions.FullBackupMonthlyScheduleOptions.DayNumberInMonth) {
            "First" { $DayNumberInMonth = 1 }
            "Second" { $DayNumberInMonth = 2 }
            "Third" { $DayNumberInMonth = 3 }
            "Fourth" { $DayNumberInMonth = 4 }
            "Last" { $DayNumberInMonth = 4 }
        }
        $JobSchedule | Add-Member -MemberType NoteProperty -Name WeekOfMonth -Value $DayNumberInMonth
        
        $Backup = $Job.FindLastBackup()
        If ($Backup) {
            $Size = $Backup.GetAllStorages() | ? { $_.IsFull -eq $True } | Sort CreationTime -Descending | Select -First 1 -ExpandProperty Stats | Select -ExpandProperty BackupSize
            $Size = [math]::Round(($Size / 1024 / 1024 / 1024 / 1024), 1)
            $JobSchedule | Add-Member -MemberType NoteProperty -Name Size -Value $Size
        }
        
        $JobSchedules += $JobSchedule
    }

    #Get all Tape Jobs
    $TapeJobs = Get-VBRTapeJob
    $TapeBackups = Get-VBRTapeBackup
    Foreach ($Job in $TapeJobs) {
        $JobSchedule = New-Object System.Object
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Name -Value $Job.Name
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Type -Value "Tape"
        $JobSchedule | Add-Member -MemberType NoteProperty -Name DayOfWeek -Value $Job.NextRun.DayOfWeek
        Switch ($Job.ScheduleOptions.MonthlyOptions.DayNumberInMonth) {
            "First" { $DayNumberInMonth = 1 }
            "Second" { $DayNumberInMonth = 2 }
            "Third" { $DayNumberInMonth = 3 }
            "Fourth" { $DayNumberInMonth = 4 }
            "Last" { $DayNumberInMonth = 4 }
        }
        $JobSchedule | Add-Member -MemberType NoteProperty -Name WeekOfMonth -Value $DayNumberInMonth

        $Backup = $TapeBackups | ? { $_.JobId.Guid -eq $Job.Id } | Sort CreationTime -Descending | Select -First 1
        If ($Backup) {
            $Size = $Backup.GetAllStorages() | Sort CreationTime -Descending | Select -First 1 | Select -ExpandProperty Stats | Select -ExpandProperty BackupSize
            $Size = [math]::Round(($Size / 1024 / 1024 / 1024 / 1024), 1)
            $JobSchedule | Add-Member -MemberType NoteProperty -Name Size -Value $Size
        }

        $JobSchedules += $JobSchedule
    }


    #Get all SureBackup Jobs
    $SBJobs = Get-VSBJob | ? {$_.IsScheduleEnabled -eq $true}
    Foreach ($Job in $SBJobs) {
        $JobSchedule = New-Object System.Object
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Name -Value $Job.Name
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Type -Value "SB"
        $JobSchedule | Add-Member -MemberType NoteProperty -Name DayOfWeek -Value $Job.ScheduleOptions.OptionsMonthly.DayOfWeek
        Switch ($Job.ScheduleOptions.OptionsMonthly.DayNumberInMonth) {
            "First" { $DayNumberInMonth = 1 }
            "Second" { $DayNumberInMonth = 2 }
            "Third" { $DayNumberInMonth = 3 }
            "Fourth" { $DayNumberInMonth = 4 }
            "Last" { $DayNumberInMonth = 4 }
        }
        $JobSchedule | Add-Member -MemberType NoteProperty -Name WeekOfMonth -Value $DayNumberInMonth

        $JobSchedules += $JobSchedule
    }

    #Get all File Copy Jobs
    $FileCopyJobs = Get-VBRJob | ? {$_.JobType -eq 'Copy' -and $_.SourceType -eq 'Files' -and $_.IsScheduleEnabled -eq $true}
    Foreach ($Job in $FileCopyJobs) {
        $JobSchedule = New-Object System.Object
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Name -Value $Job.Name
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Type -Value "Copy"
        $JobSchedule | Add-Member -MemberType NoteProperty -Name DayOfWeek -Value $Job.ScheduleOptions.OptionsMonthly.DayOfWeek
        Switch ($Job.ScheduleOptions.OptionsMonthly.DayNumberInMonth) {
            "First" { $DayNumberInMonth = 1 }
            "Second" { $DayNumberInMonth = 2 }
            "Third" { $DayNumberInMonth = 3 }
            "Fourth" { $DayNumberInMonth = 4 }
            "Last" { $DayNumberInMonth = 4 }
        }
        $JobSchedule | Add-Member -MemberType NoteProperty -Name WeekOfMonth -Value $DayNumberInMonth

        $JobSchedules += $JobSchedule
    }

    #Get all Stornext jobs from Task Scheduler
    $StornextJobs = Get-ScheduledTask | ? {$_.State -ne 'Disabled' -and $_.TaskName -like "Stornext*"} | Get-ScheduledTaskInfo
    Foreach ($Job in $StornextJobs) {
        $JobSchedule = New-Object System.Object
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Name -Value $Job.TaskName
        $JobSchedule | Add-Member -MemberType NoteProperty -Name Type -Value "Copy"
        $JobSchedule | Add-Member -MemberType NoteProperty -Name DayOfWeek -Value $Job.NextRunTime.DayOfWeek
        
        #Calculate week of month: [int rounded down](Day of the month - Day of the week + 13)/7
        #i.e. Sunday the 13th = [int](13 - 1 + 13)/7 = week 3
        $WeekOfMonth = (($Job.NextRunTime.Day - ($Job.NextRunTime.DayOfWeek.value__ + 1) + 13) / 7)
        $WeekOfMonth = [math]::floor($WeekOfMonth)
        If ($WeekOfMonth -gt 4) { $WeekOfMonth = 4 }

        $JobSchedule | Add-Member -MemberType NoteProperty -Name WeekOfMonth -Value $WeekOfMonth

        $JobSchedules += $JobSchedule
    }    


$JobSchedules = $JobSchedules | Sort-Object Name


#Create a simple calendar structure, 4 weeks by 7 days.
$Calendar = @()
For ($i=1; $i -le 4; $i++) {
    $Week = New-Object System.Object
    $Week | Add-Member -MemberType NoteProperty -Name Week -Value "$i"
    $Week | Add-Member -MemberType NoteProperty -Name Sunday -Value ""
    $Week | Add-Member -MemberType NoteProperty -Name Monday -Value ""
    $Week | Add-Member -MemberType NoteProperty -Name Tuesday -Value ""
    $Week | Add-Member -MemberType NoteProperty -Name Wednesday -Value ""
    $Week | Add-Member -MemberType NoteProperty -Name Thursday -Value ""
    $Week | Add-Member -MemberType NoteProperty -Name Friday -Value ""
    $Week | Add-Member -MemberType NoteProperty -Name Saturday -Value ""
    $Calendar += $Week
}

#Populate the calendar with JobSchedules.
Foreach ($Job in $JobSchedules) {
    If ($Job.Type -eq 'Full') {
        $Calendar[$Job.WeekOfMonth - 1].($Job.DayOfWeek) += "$($Job.Name) - $($Job.Size)TB`n"
    }
    ElseIf ($Job.Type -eq 'SB') {
        $Calendar[$Job.WeekOfMonth - 1].($Job.DayOfWeek) += "$($Job.Name)`n"
    }
    ElseIf ($Job.Type -eq 'Copy') {
        $Calendar[$Job.WeekOfMonth - 1].($Job.DayOfWeek) += "$($Job.Name)`n"
    }
    Else {
        $Calendar[$Job.WeekOfMonth - 1].($Job.DayOfWeek) += "$($Job.Name) - $($Job.Size)TB (Tape)`n"
    }
}

$Calendar | Out-GridView -Title "VEEAM - Monthly Jobs" -Wait