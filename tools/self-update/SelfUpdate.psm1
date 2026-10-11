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
        if ($oldPid -gt 0) {
            # The lock only counts if it is younger than the task's 2-hour limit and
            # its PID still belongs to the process that wrote it (PIDs get reused).
            $written = (Get-Item -LiteralPath $Path).LastWriteTime
            $isFresh = $written -gt (Get-Date).AddHours(-3)
            $owner = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            $isOwner = $false
            if ($owner) {
                try { $isOwner = $owner.StartTime -le $written } catch { $isOwner = $true }
            }
            if ($isFresh -and $isOwner) { return $false }
        }
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

# Never throws, so a failed launch can't hide the real reason a run failed.
function Start-App {
    param([string]$AppExe)
    try {
        Start-Process -FilePath $AppExe -WorkingDirectory (Split-Path -Parent $AppExe) -ErrorAction Stop
        return $true
    } catch {
        Write-Log "Could not start the app: $($_.Exception.Message)"
        return $false
    }
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

# Runs a native command, logs its output, and throws on a non-zero exit code.
# ErrorActionPreference is relaxed locally because Windows PowerShell 5.1 turns
# native stderr lines into error records, and tools like git write progress there.
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = (Get-Location).Path,
        [switch]$AllowFailure
    )
    Push-Location -LiteralPath $WorkingDirectory
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
        Pop-Location
    }
    foreach ($line in $output) { Write-Log "  $line" }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "'$FilePath $($ArgumentList -join ' ')' failed with exit code $code"
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Initialize-BuilderRepo {
    param([string]$RepoDir, [string]$OriginUrl, [string]$UpstreamUrl, [string]$Branch)
    if (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) {
        $parent = Split-Path -Parent $RepoDir
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Write-Log "Cloning $OriginUrl ($Branch) into $RepoDir"
        Invoke-Native git @('clone', '--branch', $Branch, $OriginUrl, $RepoDir) -WorkingDirectory $parent | Out-Null
    }
    $remotes = (Invoke-Native git @('remote') -WorkingDirectory $RepoDir).Output
    if ($remotes -contains 'upstream') {
        Invoke-Native git @('remote', 'set-url', 'upstream', $UpstreamUrl) -WorkingDirectory $RepoDir | Out-Null
    } else {
        Invoke-Native git @('remote', 'add', 'upstream', $UpstreamUrl) -WorkingDirectory $RepoDir | Out-Null
    }
}

# Throws away any local state in the builder clone. Safe because the job owns
# this clone; ignored folders such as build/ are kept so Flutter builds stay fast.
function Reset-ToBranch {
    param([string]$RepoDir, [string]$Branch)
    Invoke-Native git @('merge', '--abort') -WorkingDirectory $RepoDir -AllowFailure | Out-Null
    Remove-Item -LiteralPath (Join-Path $RepoDir '.git\MERGE_HEAD') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $RepoDir '.git\index.lock') -Force -ErrorAction SilentlyContinue
    Invoke-Native git @('checkout', '-f', '-B', $Branch, "origin/$Branch") -WorkingDirectory $RepoDir | Out-Null
    Invoke-Native git @('clean', '-fd') -WorkingDirectory $RepoDir | Out-Null
}

# The job runs unattended, so a sign-in prompt would hang it until the task's
# time limit. With prompts off, an expired credential just fails the push.
function Disable-GitPrompts {
    $env:GCM_INTERACTIVE = 'never'
    $env:GIT_TERMINAL_PROMPT = '0'
}

function Invoke-UpstreamMerge {
    param([string]$RepoDir, [string]$Ref)
    $result = Invoke-Native git @('merge', '--no-edit', '-m', "Merge upstream release $Ref", $Ref) -WorkingDirectory $RepoDir -AllowFailure
    if ($result.ExitCode -eq 0) { return $true }
    Invoke-Native git @('merge', '--abort') -WorkingDirectory $RepoDir -AllowFailure | Out-Null
    return $false
}

Export-ModuleMember -Function *
