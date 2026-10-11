# Personal Build Self-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A personal `my-version` build of No Reload Mod Manager that a daily Windows scheduled task keeps merged with the newest upstream release, rebuilds, and reinstalls.

**Architecture:** The PowerShell helpers live in one module (`SelfUpdate.psm1`), which Pester tests cover. A thin `update.ps1` uses them to run the job against a dedicated clone in `%LOCALAPPDATA%\NRMM-Builder\repo`. Two small scripts register and remove the scheduled task. In the Flutter app, the upstream updater is switched off. The new code lives in a new file, so future upstream merges are unlikely to hit conflicts.

**Tech Stack:** Windows PowerShell 5.1, Pester 3.4.0 (preinstalled, so use `Should Be` syntax and not `Should -Be`), git, Flutter/Dart, fastforge, Inno Setup 6, Windows Task Scheduler.

**Spec:** `docs/superpowers/specs/2026-10-11-self-update-pipeline-design.md`

## Global Constraints

- Upstream: `https://github.com/Aglglg/No-Reload-Mod-Manager.git`. Fork (origin): `https://github.com/Aswadina/No-Reload-Mod-Manager.git`.
- Personal branch: `my-version`. `main` mirrors `upstream/main`.
- Follow upstream release tags matching `^v\d+\.\d+\.\d+$`, newest by version number. Never follow `upstream/main`.
- Builder folder: `%LOCALAPPDATA%\NRMM-Builder` (`repo\`, `state.json`, `update.lock`, `logs\yyyy-MM-dd.log`, keep 30 logs).
- The job never touches the dev folder `C:\Users\Aswad\No-Reload-Mod-Manager`.
- Installed app: `%APPDATA%\No Reload Mod Manager\No_Reload_Mod_Manager.exe`, process name `No_Reload_Mod_Manager`.
- Installer: `dist\<version>\no_reload_mod_manager-<version>-windows-setup.exe`, run with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`.
- Scheduled task name: `NRMM Self-Update`, daily 04:00, start when available, current user, interactive logon only.
- Any failure leaves the installed app untouched, logs the reason, and shows a toast.
- Scripts must run on Windows PowerShell 5.1 (no `pwsh`, no `??`, no `&&`).
- Keep personal Dart changes in new files under `lib/custom/` where possible. Edits to upstream files stay as small as possible.

## Review Focus

1. **Crashed or killed run leaves a stale lock.** The next run must take over a lock whose PID is dead and must not skip forever. (Task 2 test: "takes over a lock held by a dead PID".)
2. **Merge conflict leaves the clone half-merged.** After a conflict the clone must be clean (no `MERGE_HEAD`, empty status), and the next run must start fresh. (Task 3 tests: "aborts and cleans up on conflict" and "Reset-ToBranch recovers a dirty, half-merged clone".)
3. **Odd tags upstream** such as `v3.10.0` vs `v3.9.0`, `v3.2.3-beta`, or a tag without `v`. Sorting must be numeric, and pre-release or odd tags are ignored. (Task 2 tests.)
4. **App not running at install time.** Closing it must not throw, and the job must not launch an app that wasn't open. (Task 2 test: "Stop-App returns false when not running"; Task 4 relaunch only if `$wasRunning`.)
5. **Build "succeeds" but no installer appears** (wrong version folder, fastforge quirk). This must count as a failure, and nothing gets pushed or installed. (Task 2 test for `Get-InstallerPath`; Task 4 checks that the file exists before the push.)

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/self-update/SelfUpdate.psm1` | All helper functions: config, logging, lock, state, tag picking, git helpers, app stop, toast. |
| `tools/self-update/update.ps1` | The job. Wires the helpers together in spec order. Supports `-DryRun` and `-Force`. |
| `tools/self-update/install-task.ps1` | Prepares the builder clone and registers the scheduled task. |
| `tools/self-update/uninstall-task.ps1` | Removes the scheduled task. |
| `tools/self-update/tests/SelfUpdate.Tests.ps1` | Pester 3.4 tests for the module. |
| `lib/custom/self_update_dialog.dart` | New dialog explaining that updates come from the self-update task. |
| `lib/main.dart` (modify) | Remove the upstream appcast feed setup and the unused import. |
| `lib/tabs/settings_tab.dart` (modify) | "Check for Updates" button opens the new dialog. |

Run the tests with:
`powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tools/self-update/tests -EnableExit"`

---

### Task 1: Branch setup and merge the current upstream release

**Files:** none (git only)

**Interfaces:**
- Produces: local and remote branch `my-version` containing `Reorder-groups` + spec/plan docs + upstream `v3.2.3`. Remote `upstream` in the dev folder.

- [ ] **Step 1: Add the upstream remote and fetch tags**

```bash
cd /c/Users/Aswad/No-Reload-Mod-Manager
git remote add upstream https://github.com/Aglglg/No-Reload-Mod-Manager.git
git fetch upstream --tags
```
Expected: tags up to `v3.2.3` listed.

- [ ] **Step 2: Create `my-version` from `Reorder-groups` and merge v3.2.3**

```bash
git checkout -b my-version Reorder-groups
git merge --no-edit -m "Merge upstream release v3.2.3" v3.2.3
```
Expected: merge completes with no conflicts (checked on 2026-10-11 with `git merge-tree`).

- [ ] **Step 3: Verify the merge**

Run: `git merge-base --is-ancestor v3.2.3 HEAD && echo OK`
Expected: `OK`

- [ ] **Step 4: Push `my-version` and bring the fork's `main` up to date**

```bash
git push -u origin my-version
git push origin refs/remotes/upstream/main:refs/heads/main
```
Expected: both pushes succeed. `main` is a fast-forward.

---

### Task 2: SelfUpdate module, pure helpers

**Files:**
- Create: `tools/self-update/SelfUpdate.psm1`
- Test: `tools/self-update/tests/SelfUpdate.Tests.ps1`

**Interfaces:**
- Produces (all exported):
  - `Get-SelfUpdateConfig` returns a hashtable with keys `BuilderDir, RepoDir, StatePath, LockPath, LogDir, OriginUrl, UpstreamUrl, Branch, AppExe, ProcessName, TaskName`
  - `Set-LogFile -Path <string>`, `Write-Log -Message <string>`
  - `Get-NewestReleaseTag -Tags <string[]>` returns `[string]` or `$null`
  - `Get-PubspecVersion -PubspecPath <string>` returns `[string]` (for example `3.2.3+1`)
  - `Get-InstallerPath -RepoDir <string> -Version <string>` returns `[string]`
  - `Read-State -Path <string>` returns object with `tree, commit, version, installedAt`, or `$null`
  - `Write-State -Path -Tree -Commit -Version`
  - `Test-ShouldBuild -Tree <string> -State <obj> [-Force]` returns `[bool]`
  - `Enter-Lock -Path` returns `[bool]`, `Exit-Lock -Path`
  - `Remove-OldLogs -LogDir <string> -Keep <int>`
  - `Stop-App -ProcessName <string>` returns `[bool]` (true when it was running)
  - `Show-Toast -Title <string> -Message <string>` (never throws)

- [ ] **Step 1: Write the failing tests**

Create `tools/self-update/tests/SelfUpdate.Tests.ps1`:

```powershell
$modulePath = Join-Path $PSScriptRoot '..\SelfUpdate.psm1'
Import-Module $modulePath -Force

Describe 'Get-NewestReleaseTag' {
    It 'picks the highest version numerically' {
        Get-NewestReleaseTag -Tags @('v3.9.0', 'v3.10.0', 'v3.2.3') | Should Be 'v3.10.0'
    }
    It 'ignores pre-release and non-v tags' {
        Get-NewestReleaseTag -Tags @('v3.2.3', 'v3.3.0-beta', '4.0.0', 'latest') | Should Be 'v3.2.3'
    }
    It 'returns null when there are no release tags' {
        Get-NewestReleaseTag -Tags @('foo') | Should Be $null
    }
}

Describe 'Get-PubspecVersion' {
    It 'reads the version line' {
        $file = Join-Path $TestDrive 'pubspec.yaml'
        Set-Content -Path $file -Value @('name: x', '# version: 0.0.1', 'version: 3.2.3+1', 'environment:')
        Get-PubspecVersion -PubspecPath $file | Should Be '3.2.3+1'
    }
    It 'throws when there is no version line' {
        $file = Join-Path $TestDrive 'empty.yaml'
        Set-Content -Path $file -Value 'name: x'
        { Get-PubspecVersion -PubspecPath $file } | Should Throw
    }
}

Describe 'Get-InstallerPath' {
    It 'builds the fastforge output path' {
        Get-InstallerPath -RepoDir 'C:\r' -Version '3.2.3+1' |
            Should Be 'C:\r\dist\3.2.3+1\no_reload_mod_manager-3.2.3+1-windows-setup.exe'
    }
}

Describe 'State' {
    It 'round-trips through Write-State and Read-State' {
        $path = Join-Path $TestDrive 'sub\state.json'
        Write-State -Path $path -Tree 'abc' -Commit 'def' -Version '3.2.3+1'
        $s = Read-State -Path $path
        $s.tree | Should Be 'abc'
        $s.commit | Should Be 'def'
        $s.version | Should Be '3.2.3+1'
    }
    It 'returns null for a missing file' {
        Read-State -Path (Join-Path $TestDrive 'nope.json') | Should Be $null
    }
    It 'returns null for a corrupt file' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -Path $path -Value '{not json'
        Read-State -Path $path | Should Be $null
    }
}

Describe 'Test-ShouldBuild' {
    It 'builds when there is no state' {
        Test-ShouldBuild -Tree 'a' -State $null | Should Be $true
    }
    It 'skips when the tree matches' {
        Test-ShouldBuild -Tree 'a' -State ([pscustomobject]@{ tree = 'a' }) | Should Be $false
    }
    It 'builds when the tree differs' {
        Test-ShouldBuild -Tree 'b' -State ([pscustomobject]@{ tree = 'a' }) | Should Be $true
    }
    It 'builds when forced' {
        Test-ShouldBuild -Tree 'a' -State ([pscustomobject]@{ tree = 'a' }) -Force | Should Be $true
    }
    It 'builds when state has no tree property' {
        Test-ShouldBuild -Tree 'a' -State ([pscustomobject]@{ other = 1 }) | Should Be $true
    }
}

Describe 'Lock' {
    It 'takes a free lock and refuses a lock held by a live PID' {
        $path = Join-Path $TestDrive 'free.lock'
        Enter-Lock -Path $path | Should Be $true
        Enter-Lock -Path $path | Should Be $false   # held by this (live) process
        Exit-Lock -Path $path
        Test-Path $path | Should Be $false
    }
    It 'takes over a lock held by a dead PID' {
        $path = Join-Path $TestDrive 'stale.lock'
        Set-Content -Path $path -Value '999999'
        Enter-Lock -Path $path | Should Be $true
    }
    It 'takes over an empty lock file' {
        $path = Join-Path $TestDrive 'empty.lock'
        New-Item -ItemType File -Path $path | Out-Null
        Enter-Lock -Path $path | Should Be $true
    }
}

Describe 'Remove-OldLogs' {
    It 'keeps only the newest N logs' {
        $dir = Join-Path $TestDrive 'logs'
        New-Item -ItemType Directory -Path $dir | Out-Null
        1..5 | ForEach-Object { Set-Content -Path (Join-Path $dir ("2026-10-0$_.log")) -Value 'x' }
        Remove-OldLogs -LogDir $dir -Keep 2
        (Get-ChildItem $dir).Name -join ',' | Should Be '2026-10-04.log,2026-10-05.log'
    }
    It 'does nothing when the folder is missing' {
        { Remove-OldLogs -LogDir (Join-Path $TestDrive 'none') -Keep 2 } | Should Not Throw
    }
}

Describe 'Stop-App' {
    It 'returns false when not running' {
        Stop-App -ProcessName 'Definitely_Not_A_Real_Process_123' | Should Be $false
    }
    It 'stops a running process and returns true' {
        $p = Start-Process -FilePath 'ping.exe' -ArgumentList '-n', '60', '127.0.0.1' -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 300
        Stop-App -ProcessName 'PING' | Should Be $true
        $p.HasExited | Should Be $true
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tools/self-update/tests -EnableExit"`
Expected: FAIL, because the module file does not exist.

- [ ] **Step 3: Write the module**

Create `tools/self-update/SelfUpdate.psm1`:

```powershell
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tools/self-update/tests -EnableExit"`
Expected: all tests PASS.

- [ ] **Step 5: Smoke-test the toast by hand**

Run: `powershell -NoProfile -Command "Import-Module ./tools/self-update/SelfUpdate.psm1; Show-Toast 'NRMM test' 'Toast works'"`
Expected: a Windows notification appears. If it doesn't, the log line explains why. Do not block on this. The job keeps working without toasts.

- [ ] **Step 6: Commit**

```bash
git add tools/self-update/SelfUpdate.psm1 tools/self-update/tests/SelfUpdate.Tests.ps1
git commit -m "feat(self-update): add helper module with tests"
```

---

### Task 3: Git helpers

**Files:**
- Modify: `tools/self-update/SelfUpdate.psm1` (add functions before `Export-ModuleMember`)
- Test: `tools/self-update/tests/SelfUpdate.Tests.ps1` (append)

**Interfaces:**
- Consumes: `Write-Log` (Task 2).
- Produces:
  - `Invoke-Native -FilePath <string> -ArgumentList <string[]> [-WorkingDirectory <string>] [-AllowFailure]` returns `[pscustomobject]@{ ExitCode=<int>; Output=<string[]> }`. Throws on non-zero exit unless `-AllowFailure`.
  - `Initialize-BuilderRepo -RepoDir -OriginUrl -UpstreamUrl -Branch` clones if missing and makes sure the `upstream` remote URL is set.
  - `Reset-ToBranch -RepoDir -Branch` aborts any merge, force-checks out `origin/<Branch>`, and removes untracked files (keeps ignored files such as `build/`).
  - `Invoke-UpstreamMerge -RepoDir -Ref` returns `[bool]`. `$false` means conflict, and the merge has been aborted.

- [ ] **Step 1: Write the failing tests**

Append to `tools/self-update/tests/SelfUpdate.Tests.ps1`:

```powershell
function New-TestRepo {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Invoke-Native git @('init', '-q', '-b', 'my-version') -WorkingDirectory $Path | Out-Null
    Invoke-Native git @('config', 'user.email', 't@t') -WorkingDirectory $Path | Out-Null
    Invoke-Native git @('config', 'user.name', 't') -WorkingDirectory $Path | Out-Null
    Set-Content -Path (Join-Path $Path 'a.txt') -Value 'base'
    Invoke-Native git @('add', '.') -WorkingDirectory $Path | Out-Null
    Invoke-Native git @('commit', '-q', '-m', 'base') -WorkingDirectory $Path | Out-Null
}

Describe 'Invoke-Native' {
    It 'returns output and exit code' {
        $r = Invoke-Native git @('--version')
        $r.ExitCode | Should Be 0
        ($r.Output -join '') | Should Match 'git version'
    }
    It 'throws on failure' {
        { Invoke-Native git @('not-a-command') } | Should Throw
    }
    It 'does not throw on failure with -AllowFailure' {
        (Invoke-Native git @('not-a-command') -AllowFailure).ExitCode | Should Not Be 0
    }
}

Describe 'Invoke-UpstreamMerge' {
    It 'merges a non-conflicting tag' {
        $repo = Join-Path $TestDrive 'clean'
        New-TestRepo $repo
        Invoke-Native git @('checkout', '-q', '-b', 'theirs') -WorkingDirectory $repo | Out-Null
        Set-Content -Path (Join-Path $repo 'b.txt') -Value 'theirs'
        Invoke-Native git @('add', '.') -WorkingDirectory $repo | Out-Null
        Invoke-Native git @('commit', '-q', '-m', 'theirs') -WorkingDirectory $repo | Out-Null
        Invoke-Native git @('tag', 'v1.0.1') -WorkingDirectory $repo | Out-Null
        Invoke-Native git @('checkout', '-q', 'my-version') -WorkingDirectory $repo | Out-Null
        Set-Content -Path (Join-Path $repo 'c.txt') -Value 'mine'
        Invoke-Native git @('add', '.') -WorkingDirectory $repo | Out-Null
        Invoke-Native git @('commit', '-q', '-m', 'mine') -WorkingDirectory $repo | Out-Null

        Invoke-UpstreamMerge -RepoDir $repo -Ref 'v1.0.1' | Should Be $true
        Test-Path (Join-Path $repo 'b.txt') | Should Be $true
    }
    It 'aborts and cleans up on conflict' {
        $repo = Join-Path $TestDrive 'conflict'
        New-TestRepo $repo
        Invoke-Native git @('checkout', '-q', '-b', 'theirs') -WorkingDirectory $repo | Out-Null
        Set-Content -Path (Join-Path $repo 'a.txt') -Value 'theirs'
        Invoke-Native git @('commit', '-q', '-am', 'theirs') -WorkingDirectory $repo | Out-Null
        Invoke-Native git @('tag', 'v1.0.1') -WorkingDirectory $repo | Out-Null
        Invoke-Native git @('checkout', '-q', 'my-version') -WorkingDirectory $repo | Out-Null
        Set-Content -Path (Join-Path $repo 'a.txt') -Value 'mine'
        Invoke-Native git @('commit', '-q', '-am', 'mine') -WorkingDirectory $repo | Out-Null

        Invoke-UpstreamMerge -RepoDir $repo -Ref 'v1.0.1' | Should Be $false
        Test-Path (Join-Path $repo '.git\MERGE_HEAD') | Should Be $false
        (Invoke-Native git @('status', '--porcelain') -WorkingDirectory $repo).Output.Count | Should Be 0
        (Get-Content (Join-Path $repo 'a.txt')) | Should Be 'mine'
    }
}

Describe 'Initialize-BuilderRepo and Reset-ToBranch' {
    $source = Join-Path $TestDrive 'source'
    $origin = Join-Path $TestDrive 'origin.git'
    $clone = Join-Path $TestDrive 'builder\repo'
    New-TestRepo $source
    Invoke-Native git @('clone', '-q', '--bare', $source, $origin) | Out-Null

    It 'clones the branch and adds the upstream remote' {
        Initialize-BuilderRepo -RepoDir $clone -OriginUrl $origin -UpstreamUrl 'https://example.com/up.git' -Branch 'my-version'
        Test-Path (Join-Path $clone '.git') | Should Be $true
        (Invoke-Native git @('remote', 'get-url', 'upstream') -WorkingDirectory $clone).Output[0] |
            Should Be 'https://example.com/up.git'
    }
    It 'is safe to run twice' {
        { Initialize-BuilderRepo -RepoDir $clone -OriginUrl $origin -UpstreamUrl 'https://example.com/up.git' -Branch 'my-version' } |
            Should Not Throw
    }
    It 'Reset-ToBranch recovers a dirty, half-merged clone' {
        Set-Content -Path (Join-Path $clone 'a.txt') -Value 'local edit'
        Set-Content -Path (Join-Path $clone 'junk.txt') -Value 'untracked'
        Set-Content -Path (Join-Path $clone '.git\MERGE_HEAD') -Value '0000000000000000000000000000000000000000'
        Invoke-Native git @('fetch', '-q', 'origin') -WorkingDirectory $clone | Out-Null

        Reset-ToBranch -RepoDir $clone -Branch 'my-version'

        Test-Path (Join-Path $clone '.git\MERGE_HEAD') | Should Be $false
        Test-Path (Join-Path $clone 'junk.txt') | Should Be $false
        (Get-Content (Join-Path $clone 'a.txt')) | Should Be 'base'
        (Invoke-Native git @('status', '--porcelain') -WorkingDirectory $clone).Output.Count | Should Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tools/self-update/tests -EnableExit"`
Expected: the new Describe blocks FAIL with "Invoke-Native is not recognized". The Task 2 tests still PASS.

- [ ] **Step 3: Add the git helpers to the module**

Insert before `Export-ModuleMember -Function *` in `tools/self-update/SelfUpdate.psm1`:

```powershell
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
    Invoke-Native git @('checkout', '-f', '-B', $Branch, "origin/$Branch") -WorkingDirectory $RepoDir | Out-Null
    Invoke-Native git @('clean', '-fd') -WorkingDirectory $RepoDir | Out-Null
}

function Invoke-UpstreamMerge {
    param([string]$RepoDir, [string]$Ref)
    $result = Invoke-Native git @('merge', '--no-edit', '-m', "Merge upstream release $Ref", $Ref) -WorkingDirectory $RepoDir -AllowFailure
    if ($result.ExitCode -eq 0) { return $true }
    Invoke-Native git @('merge', '--abort') -WorkingDirectory $RepoDir -AllowFailure | Out-Null
    return $false
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tools/self-update/tests -EnableExit"`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/self-update/SelfUpdate.psm1 tools/self-update/tests/SelfUpdate.Tests.ps1
git commit -m "feat(self-update): add git helpers for clone, reset and merge"
```

---

### Task 4: The update job (`update.ps1`)

**Files:**
- Create: `tools/self-update/update.ps1`

**Interfaces:**
- Consumes: every function from Tasks 2 and 3.
- Produces: `update.ps1 [-DryRun] [-Force]`. Exit code 0 on success or "nothing new", 1 on any failure or conflict.

- [ ] **Step 1: Write the script**

Create `tools/self-update/update.ps1`:

```powershell
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
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Force)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SelfUpdate.psm1') -Force
$cfg = Get-SelfUpdateConfig

function Invoke-SelfUpdate {
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
    if ($proc.ExitCode -ne 0) {
        if ($wasRunning) { Start-Process -FilePath $cfg.AppExe -WorkingDirectory (Split-Path -Parent $cfg.AppExe) }
        throw "Installer exited with code $($proc.ExitCode)"
    }

    Write-State -Path $cfg.StatePath -Tree $tree -Commit $commit -Version $version
    if ($wasRunning) { Start-Process -FilePath $cfg.AppExe -WorkingDirectory (Split-Path -Parent $cfg.AppExe) }
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
```

- [ ] **Step 2: Parse-check the script**

Run: `powershell -NoProfile -Command "$null = [scriptblock]::Create((Get-Content -Raw tools/self-update/update.ps1)); 'parse OK'"`
Expected: `parse OK`

- [ ] **Step 3: Commit and push so the builder clone can see it**

```bash
git add tools/self-update/update.ps1
git commit -m "feat(self-update): add update job script"
git push origin my-version
```

- [ ] **Step 4: Dry run (real merge and build)**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\self-update\update.ps1 -DryRun`
Expected: clones into `%LOCALAPPDATA%\NRMM-Builder\repo`, logs `Newest upstream release: v3.2.3`, merge is "Already up to date" (Task 1 merged it), installs fastforge, builds, and logs `Built ...\dist\3.2.3+1\no_reload_mod_manager-3.2.3+1-windows-setup.exe`. Exit code 0.
If the build fails, read the log in `%LOCALAPPDATA%\NRMM-Builder\logs\` and fix the cause before going further. A likely cause is that the local Flutter version differs from the 3.32.8 used in upstream CI.

- [ ] **Step 5: Check the lock was released**

Run: `powershell -NoProfile -Command "Test-Path $env:LOCALAPPDATA\NRMM-Builder\update.lock"`
Expected: `False`

---

### Task 5: Turn off the upstream updater in the app

**Files:**
- Create: `lib/custom/self_update_dialog.dart`
- Modify: `lib/main.dart` (remove `import 'package:auto_updater/auto_updater.dart';` and the 4 feed lines in `setupWindow`)
- Modify: `lib/tabs/settings_tab.dart` (the "Check for Updates" button `onPressed`, and the `auto_updater` import)

**Interfaces:**
- Consumes: `alertDialogShownProvider` (`lib/utils/state_providers.dart`), `getAccentColor(WidgetRef, {int alpha})` (`lib/main.dart`).
- Produces: `class SelfUpdateInfoDialog extends ConsumerWidget` (const constructor, no params).

- [ ] **Step 1: Create the dialog**

Create `lib/custom/self_update_dialog.dart`:

```dart
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:no_reload_mod_manager/main.dart';
import 'package:no_reload_mod_manager/utils/state_providers.dart';

/// Personal build: shown instead of the upstream auto-updater. Updates are
/// installed by the daily "NRMM Self-Update" task (tools/self-update).
class SelfUpdateInfoDialog extends ConsumerWidget {
  const SelfUpdateInfoDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        MoveWindow(),
        AlertDialog(
          title: Text(
            'Updates'.tr(),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          content: Text(
            'This is a personal build. New releases are merged, built and '
            'installed automatically by the daily "NRMM Self-Update" task.\n\n'
            'Logs: %LOCALAPPDATA%\\NRMM-Builder\\logs',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(alertDialogShownProvider.notifier).state = false;
              },
              child: Text(
                'OK'.tr(),
                style: GoogleFonts.poppins(color: getAccentColor(ref)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Remove the upstream feed from `lib/main.dart`**

Delete the line `import 'package:auto_updater/auto_updater.dart';` (line 6 before any edits).

In `setupWindow`, replace:

```dart
  String feedURL =
      'https://raw.githubusercontent.com/Aglglg/No-Reload-Mod-Manager/refs/heads/main/appcast.xml';
  await autoUpdater.setFeedURL(feedURL);
  await autoUpdater.setScheduledCheckInterval(0);
```

with:

```dart
  // Personal build: updates come from tools/self-update, not the upstream appcast.
```

- [ ] **Step 3: Point the settings button at the dialog**

In `lib/tabs/settings_tab.dart`, replace the import `import 'package:auto_updater/auto_updater.dart';` with:

```dart
import 'package:no_reload_mod_manager/custom/self_update_dialog.dart';
```

Then, in the "Check for Updates" `ElevatedButton`, replace:

```dart
                        onPressed: () async {
                          ref.read(windowIsPinnedProvider.notifier).state =
                              false;
                          await autoUpdater.checkForUpdates();
                        },
```

with:

```dart
                        onPressed: () {
                          ref.read(alertDialogShownProvider.notifier).state =
                              true;
                          showDialog(
                            barrierDismissible: false,
                            context: context,
                            builder: (context) => const SelfUpdateInfoDialog(),
                          );
                        },
```

- [ ] **Step 4: Verify that no references to the upstream updater remain**

Run: `grep -rn "autoUpdater\|auto_updater\|appcast" lib`
Expected: no output.

- [ ] **Step 5: Analyze the changed files**

Run: `flutter analyze lib/custom/self_update_dialog.dart lib/main.dart lib/tabs/settings_tab.dart`
Expected: no `error` lines. Upstream may already have warnings or infos; compare with `git stash; flutter analyze <same files>; git stash pop` and confirm there are no new ones.

- [ ] **Step 6: Commit and push**

```bash
git add lib/custom/self_update_dialog.dart lib/main.dart lib/tabs/settings_tab.dart
git commit -m "feat: replace upstream auto-updater with self-update info dialog"
git push origin my-version
```

---

### Task 6: Scheduled task scripts and first real install

**Files:**
- Create: `tools/self-update/install-task.ps1`
- Create: `tools/self-update/uninstall-task.ps1`

**Interfaces:**
- Consumes: `Get-SelfUpdateConfig`, `Initialize-BuilderRepo`, `Invoke-Native`, `Reset-ToBranch`.
- Produces: a scheduled task named `NRMM Self-Update` that runs `<RepoDir>\tools\self-update\update.ps1`.

- [ ] **Step 1: Write `install-task.ps1`**

```powershell
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
```

- [ ] **Step 2: Write `uninstall-task.ps1`**

```powershell
<#
.SYNOPSIS
  Removes the "NRMM Self-Update" scheduled task. The builder folder is left in place.
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SelfUpdate.psm1') -Force
$cfg = Get-SelfUpdateConfig
Unregister-ScheduledTask -TaskName $cfg.TaskName -Confirm:$false
Write-Host "Removed '$($cfg.TaskName)'. Builder folder kept at $($cfg.BuilderDir)."
```

- [ ] **Step 3: Commit and push**

```bash
git add tools/self-update/install-task.ps1 tools/self-update/uninstall-task.ps1
git commit -m "feat(self-update): add scheduled task install/uninstall scripts"
git push origin my-version
```

- [ ] **Step 4: First real run by hand**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\self-update\update.ps1`
Expected: build, push (already up to date), app closes, silent install, app reopens, toast "NRMM updated". Exit code 0. No UAC prompt. If a UAC prompt appears, stop: the installer needs admin rights, and the scheduled task can't approve it at 04:00.

- [ ] **Step 5: Check the install by hand**

- Windows "Installed apps" shows "No Reload Mod Manager version 3.2.3+1", installed today.
- `%LOCALAPPDATA%\NRMM-Builder\state.json` holds the commit that was just built.
- In the app, drag-to-reorder groups works (your feature).
- Settings → "Check for Updates" shows the personal-build dialog, not the upstream updater.

- [ ] **Step 6: Second run is a no-op**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\self-update\update.ps1`
Expected: log ends with `Nothing new since the last install (<short>).`, and the app is not closed.

- [ ] **Step 7: Register the task and trigger it once**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\self-update\install-task.ps1
Start-ScheduledTask -TaskName 'NRMM Self-Update'
```
Then: `Get-ScheduledTaskInfo -TaskName 'NRMM Self-Update'` once it finishes.
Expected: `LastTaskResult` is `0`, and today's log shows a second "Nothing new" line.
