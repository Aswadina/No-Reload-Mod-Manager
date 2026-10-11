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
