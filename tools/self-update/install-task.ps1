<#
.SYNOPSIS
  Prepares the builder clone and registers the daily "NRMM Self-Update" task.
.PARAMETER At
  Daily start time (default 04:00). Missed runs start as soon as possible.
#>
param([string]$At = '04:00')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SelfUpdate.psm1') -Force
$cfg = Get-SelfUpdateConfig

# The task runs the script from the builder clone, so the job updates itself
# whenever my-version changes.
Initialize-BuilderRepo -RepoDir $cfg.RepoDir -OriginUrl $cfg.OriginUrl -UpstreamUrl $cfg.UpstreamUrl -Branch $cfg.Branch
Invoke-Native git @('fetch', 'origin', '--prune') -WorkingDirectory $cfg.RepoDir | Out-Null
Reset-ToBranch -RepoDir $cfg.RepoDir -Branch $cfg.Branch

$script = Join-Path $cfg.RepoDir 'tools\self-update\update.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "update.ps1 not found at $script. Push $($cfg.Branch) first." }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $cfg.TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'Merges the newest No Reload Mod Manager release into my-version, builds and installs it.' `
    -Force | Out-Null
Write-Host "Registered '$($cfg.TaskName)' daily at $At, running $script"
