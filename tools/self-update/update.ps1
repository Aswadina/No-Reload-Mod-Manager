<#
.SYNOPSIS
  Merges the newest upstream release into my-version, builds the installer,
  and installs it over the current No Reload Mod Manager.
.PARAMETER DryRun
  Merge and build only. No push, no install, no state update.
.PARAMETER Force
  Rebuild even if nothing changed since the last install.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\self-update\update.ps1 -DryRun
.NOTES
  The scheduled task runs this file from the builder clone. If a bad push ever
  breaks this script, push the fix and re-run install-task.ps1 to reset the clone.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Force)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SelfUpdate.psm1') -Force
$cfg = Get-SelfUpdateConfig

function Invoke-SelfUpdate {
    Disable-GitPrompts
    foreach ($tool in 'git', 'flutter', 'dart') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH." }
    }
    $repo = $cfg.RepoDir

    Initialize-BuilderRepo -RepoDir $repo -OriginUrl $cfg.OriginUrl -UpstreamUrl $cfg.UpstreamUrl -Branch $cfg.Branch
    Invoke-Native git @('fetch', 'origin', '--prune') -WorkingDirectory $repo | Out-Null
    Invoke-Native git @('fetch', 'upstream', '--tags', '--prune', '--force') -WorkingDirectory $repo | Out-Null
    Reset-ToBranch -RepoDir $repo -Branch $cfg.Branch

    $tag = Get-NewestReleaseTag -Tags (Invoke-Native git @('tag', '--list', 'v*') -WorkingDirectory $repo).Output
    if (-not $tag) { throw 'No upstream release tags (v*) found.' }
    Write-Log "Newest upstream release: $tag"

    if (-not (Invoke-UpstreamMerge -RepoDir $repo -Ref $tag)) {
        Write-Log "Merging $tag into $($cfg.Branch) hit conflicts. Merge it by hand in the dev folder and push $($cfg.Branch)."
        Show-Toast 'NRMM update needs a manual merge' "Release $tag conflicts with your changes. Your current app was left as is."
        return 1
    }

    $commit = (Invoke-Native git @('rev-parse', 'HEAD') -WorkingDirectory $repo).Output[0]
    $tree = (Invoke-Native git @('rev-parse', 'HEAD^{tree}') -WorkingDirectory $repo).Output[0]
    $short = $commit.Substring(0, 7)
    if (-not (Test-ShouldBuild -Tree $tree -State (Read-State -Path $cfg.StatePath) -Force:$Force)) {
        Write-Log "Nothing new since the last install ($short)."
        return 0
    }

    $dist = Join-Path $repo 'dist'
    if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
    $globals = (Invoke-Native dart @('pub', 'global', 'list') -WorkingDirectory $repo).Output
    if (-not ($globals -match '^fastforge ')) {
        Write-Log 'Installing fastforge'
        Invoke-Native dart @('pub', 'global', 'activate', 'fastforge') -WorkingDirectory $repo | Out-Null
    }
    Write-Log "Building $short"
    Invoke-Native dart @('pub', 'global', 'run', 'fastforge:main', 'package', '--platform', 'windows', '--target', 'exe') -WorkingDirectory $repo | Out-Null

    $version = Get-PubspecVersion -PubspecPath (Join-Path $repo 'pubspec.yaml')
    $installer = Get-InstallerPath -RepoDir $repo -Version $version
    if (-not (Test-Path -LiteralPath $installer)) { throw "Build finished but no installer at $installer" }
    Write-Log "Built $installer"

    if ($DryRun) {
        Write-Log 'Dry run: skipping push and install.'
        Show-Toast 'NRMM dry run finished' "Built $version ($short). Nothing was installed."
        return 0
    }

    # Pushing is only a backup, so a failure here doesn't stop the install.
    $pushes = @(
        (Invoke-Native git @('push', 'origin', $cfg.Branch) -WorkingDirectory $repo -AllowFailure),
        (Invoke-Native git @('push', 'origin', 'refs/remotes/upstream/main:refs/heads/main') -WorkingDirectory $repo -AllowFailure)
    )
    if (@($pushes | Where-Object { $_.ExitCode -ne 0 }).Count -gt 0) { Write-Log 'A push to origin failed; continuing with install.' }

    $wasRunning = Stop-App -ProcessName $cfg.ProcessName
    Write-Log "Installing (app was running: $wasRunning)"
    $proc = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    # Always start the app afterwards, even if it wasn't open. On a failed
    # install this brings back the previous version.
    if ($proc.ExitCode -ne 0) {
        [void](Start-App -AppExe $cfg.AppExe)
        throw "Installer exited with code $($proc.ExitCode)"
    }

    Write-State -Path $cfg.StatePath -Tree $tree -Commit $commit -Version $version
    [void](Start-App -AppExe $cfg.AppExe)
    Write-Log "Installed $version ($short)."
    Show-Toast 'NRMM updated' "Now running $version ($short) with your changes."
    return 0
}

New-Item -ItemType Directory -Path $cfg.LogDir -Force | Out-Null
Set-LogFile (Join-Path $cfg.LogDir ((Get-Date -Format 'yyyy-MM-dd') + '.log'))
Remove-OldLogs -LogDir $cfg.LogDir -Keep 30

if (-not (Enter-Lock -Path $cfg.LockPath)) {
    Write-Log 'Another self-update run is in progress; exiting.'
    exit 0
}
$exitCode = 1
try {
    Write-Log "=== Self-update started (DryRun=$DryRun, Force=$Force) ==="
    # Last value only, in case any helper leaks pipeline output.
    $exitCode = @(Invoke-SelfUpdate)[-1]
} catch {
    Write-Log "FAILED: $($_.Exception.Message)"
    Show-Toast 'NRMM update failed' $_.Exception.Message
    $exitCode = 1
} finally {
    Exit-Lock -Path $cfg.LockPath
}
exit $exitCode
