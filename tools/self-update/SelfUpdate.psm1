# Helpers for the personal-build self-update job. See
# docs/superpowers/specs/2026-10-11-self-update-pipeline-design.md
Set-StrictMode -Version 2

$script:LogFile = $null

function Get-SelfUpdateConfig {
    $builderDir = Join-Path $env:LOCALAPPDATA 'NRMM-Builder'
    return @{
        BuilderDir  = $builderDir
        RepoDir     = Join-Path $builderDir 'repo'
        StatePath   = Join-Path $builderDir 'state.json'
        LockPath    = Join-Path $builderDir 'update.lock'
        LogDir      = Join-Path $builderDir 'logs'
        OriginUrl   = 'https://github.com/Aswadina/No-Reload-Mod-Manager.git'
        UpstreamUrl = 'https://github.com/Aglglg/No-Reload-Mod-Manager.git'
        Branch      = 'my-version'
        AppExe      = Join-Path $env:APPDATA 'No Reload Mod Manager\No_Reload_Mod_Manager.exe'
        ProcessName = 'No_Reload_Mod_Manager'
        TaskName    = 'NRMM Self-Update'
    }
}

function Set-LogFile {
    param([string]$Path)
    $script:LogFile = $Path
}

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function Get-NewestReleaseTag {
    param([string[]]$Tags)
    $releases = @(foreach ($tag in $Tags) {
        if ($tag -match '^v(\d+)\.(\d+)\.(\d+)$') {
            [pscustomobject]@{
                Tag     = $tag
                Version = [version]('{0}.{1}.{2}' -f $Matches[1], $Matches[2], $Matches[3])
            }
        }
    })
    if ($releases.Count -eq 0) { return $null }
    return ($releases | Sort-Object Version -Descending | Select-Object -First 1).Tag
}

function Get-PubspecVersion {
    param([string]$PubspecPath)
    foreach ($line in Get-Content -LiteralPath $PubspecPath) {
        if ($line -match '^version:\s*(\S+)') { return $Matches[1] }
    }
    throw "No version line found in $PubspecPath"
}

function Get-InstallerPath {
    param([string]$RepoDir, [string]$Version)
    return Join-Path $RepoDir "dist\$Version\no_reload_mod_manager-$Version-windows-setup.exe"
}

function Read-State {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Write-State {
    param([string]$Path, [string]$Tree, [string]$Commit, [string]$Version)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [pscustomobject]@{
        tree        = $Tree
        commit      = $Commit
        version     = $Version
        installedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
}

# Compares git tree hashes rather than commits, so a re-created merge commit
# with identical content does not trigger a rebuild.
function Test-ShouldBuild {
    param([string]$Tree, $State, [switch]$Force)
    if ($Force) { return $true }
    if ($null -eq $State) { return $true }
    if (-not ($State.PSObject.Properties.Name -contains 'tree')) { return $true }
    return ($State.tree -ne $Tree)
}

function Enter-Lock {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $oldPid = 0
        $content = "$(Get-Content -LiteralPath $Path -Raw)".Trim()
        [void][int]::TryParse($content, [ref]$oldPid)
        if ($oldPid -gt 0 -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { return $false }
    }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $PID -Encoding ASCII
    return $true
}

function Exit-Lock {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Remove-OldLogs {
    param([string]$LogDir, [int]$Keep = 30)
    if (-not (Test-Path -LiteralPath $LogDir)) { return }
    Get-ChildItem -LiteralPath $LogDir -Filter '*.log' |
        Sort-Object Name -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force
}

function Stop-App {
    param([string]$ProcessName)
    $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $false }
    $procs | Stop-Process -Force
    foreach ($p in $procs) { [void]$p.WaitForExit(15000) }
    return $true
}

function Show-Toast {
    param([string]$Title, [string]$Message)
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $t = [Security.SecurityElement]::Escape($Title)
        $m = [Security.SecurityElement]::Escape($Message)
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$m</text></binding></visual></toast>")
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        # Windows PowerShell's own app ID, so no app registration is needed.
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch {
        Write-Log "Could not show toast: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function *
