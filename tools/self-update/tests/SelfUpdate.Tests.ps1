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
