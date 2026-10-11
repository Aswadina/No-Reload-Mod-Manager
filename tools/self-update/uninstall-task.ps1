<#
.SYNOPSIS
  Removes the "NRMM Self-Update" scheduled task. The builder folder is left in place.
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SelfUpdate.psm1') -Force
$cfg = Get-SelfUpdateConfig
Unregister-ScheduledTask -TaskName $cfg.TaskName -Confirm:$false
Write-Host "Removed '$($cfg.TaskName)'. Builder folder kept at $($cfg.BuilderDir)."
