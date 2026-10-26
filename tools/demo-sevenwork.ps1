# demo-sevenwork.ps1 -- SevenWork UI demo / acceptance run
#
# ASCII only: powershell.exe 5.1 reads a BOM-less .ps1 as system ANSI.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\demo-sevenwork.ps1 -Mode Test
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\demo-sevenwork.ps1 -Mode Demo -Record
#
# Demo mode backs up %AppData%\SevenWork\_config.ini, uses a temporary vault,
# and restores the config in finally. It never writes the user's real vault.

param(
    [ValidateSet('Test', 'Demo')]
    [string]$Mode = 'Test',
    [switch]$Record,
    [switch]$Keep,
    [switch]$Force,
    [string]$DemoRoot = '',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$ahk = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$obsExe = 'D:\02-Apps\OBS-Studio\bin\64bit\obs64.exe'
$obsScript = Join-Path $repo 'tools\demo-obs.mjs'
$driver = Join-Path $repo 'tools\demo-sevenwork.ahk'
$launcher = Join-Path $repo 'SevenWork.ahk'
$configDir = Join-Path $env:APPDATA 'SevenWork'
$configPath = Join-Path $configDir '_config.ini'
$obsidianConfig = Join-Path $env:APPDATA 'obsidian\obsidian.json'

if (-not (Test-Path -LiteralPath $ahk)) { throw "AutoHotkey not found: $ahk" }
if (-not (Test-Path -LiteralPath $driver)) { throw "Driver not found: $driver" }
if (-not (Test-Path -LiteralPath $launcher)) { throw "Launcher not found: $launcher" }
if ($Mode -eq 'Demo' -and -not (Test-Path -LiteralPath $obsExe)) {
    throw "OBS not found: $obsExe"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($DemoRoot -eq '') { $DemoRoot = Join-Path $env:TEMP ("SevenWorkDemo-" + $stamp) }
if ($OutputRoot -eq '') {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $OutputRoot = Join-Path $desktop ("SevenWork-Demo\" + $stamp)
}
New-Item -ItemType Directory -Force -Path $DemoRoot, $OutputRoot | Out-Null

function Write-Utf8NoBom([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}

function Replace-FixtureTokens([string]$path, [string]$today, [string]$prev) {
    $text = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false))
    $text = $text.Replace('{{DATE}}', $today).Replace('{{PREV}}', $prev)
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}

function Test-ObsPort {
    try {
        return [bool](Get-NetTCPConnection -LocalPort 4456 -State Listen -ErrorAction SilentlyContinue)
    } catch {
        return $false
    }
}

function Ensure-Obs {
    $proc = Get-Process -Name obs64 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Start-Process -FilePath $obsExe -WorkingDirectory (Split-Path -Parent $obsExe) | Out-Null
        $script:obsStarted = $true
        $deadline = (Get-Date).AddSeconds(20)
        while (-not (Test-ObsPort) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
        if (-not (Test-ObsPort)) { throw 'OBS WebSocket did not start on port 4456' }
    }
    return $true
}

function Stop-Obsidian {
    # Graceful first, then kill the whole Electron tree. A bare Stop-Process on
    # the parent can leave renderer children with no window, and those children
    # keep the Obsidian single-instance lock forever.
    Get-Process Obsidian -ErrorAction SilentlyContinue | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
    }
    Start-Sleep -Seconds 2
    $procs = @(Get-Process Obsidian -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
        try {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>$null | Out-Null
        } catch {}
    }
    Start-Sleep -Seconds 2
    Get-Process Obsidian -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # Remove a stale lock only after the process tree is gone. Never delete it
    # while an Obsidian process is still alive.
    $lock = Join-Path $env:APPDATA 'obsidian\lockfile'
    if ((Test-Path -LiteralPath $lock) -and -not (Get-Process Obsidian -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }
}

function Register-DemoObsidianVault([string]$vaultPath) {
    if (-not (Test-Path -LiteralPath $obsidianConfig)) { return }
    $raw = [IO.File]::ReadAllText($obsidianConfig, [Text.UTF8Encoding]::new($false))
    try { $data = $raw | ConvertFrom-Json } catch { return }
    if (-not $data.vaults) { $data | Add-Member -NotePropertyName vaults -NotePropertyValue ([pscustomobject]@{}) }
    foreach ($name in $data.vaults.PSObject.Properties.Name) {
        $vault = $data.vaults.$name
        $vault | Add-Member -NotePropertyName open -NotePropertyValue $false -Force
    }
    $id = [guid]::NewGuid().ToString('N').Substring(0, 16)
    $entry = [pscustomobject]@{
        path = $vaultPath
        ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        open = $true
    }
    $data.vaults | Add-Member -NotePropertyName $id -NotePropertyValue $entry -Force
    $json = $data | ConvertTo-Json -Depth 10 -Compress
    Write-Utf8NoBom $obsidianConfig $json
}

function Toggle-Desktop {
    # Hide / restore unrelated desktop windows so recordings do not show real work.
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.ToggleDesktop()
    } catch {}
}

function Minimize-Obs {
    try {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public class SevenWorkDemoWin {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
}
'@ -ErrorAction SilentlyContinue
        $p = Get-Process -Name obs64 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.MainWindowHandle) { [SevenWorkDemoWin]::ShowWindow($p.MainWindowHandle, 6) | Out-Null }
    } catch {}
}

function Show-Obs {
    try {
        $p = Get-Process -Name obs64 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.MainWindowHandle) { [SevenWorkDemoWin]::ShowWindow($p.MainWindowHandle, 9) | Out-Null }
    } catch {}
}

function Run-Node([string[]]$nodeArgs, [string]$stdout, [string]$stderr) {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { throw 'node not found' }
    $p = Start-Process -FilePath $node.Source -ArgumentList $nodeArgs `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

$recording = ($Mode -eq 'Demo' -and $Record)
$obsSetup = $false
$obsStarted = $false
$obsMinimized = $false
$desktopToggled = $false
$originalConfig = Test-Path -LiteralPath $configPath
$hadObsidianConfig = Test-Path -LiteralPath $obsidianConfig
$backupConfig = Join-Path $DemoRoot 'config.backup.ini'
$backupObsidianConfig = Join-Path $DemoRoot 'obsidian.json.backup'
$appProc = $null
$driverCode = 1
$obsLog = Join-Path $DemoRoot 'obs.log'
$obsErr = Join-Path $DemoRoot 'obs.err.log'
$driverErr = Join-Path $DemoRoot 'driver.err.log'
$appErr = Join-Path $DemoRoot 'app.err.log'

try {
    if ($originalConfig) { Copy-Item -LiteralPath $configPath -Destination $backupConfig -Force }
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    $existing = Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'SevenWork\.ahk' }
    if ($existing) {
        if (-not $Force) { throw 'SevenWork is already running; close it or use -Force' }
        $existing | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $prev = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
    $fixtures = Join-Path $repo 'tools\demo-fixtures'
    $vault = Join-Path $DemoRoot 'Vault'
    $prompts = Join-Path $DemoRoot 'Prompts'
    $folders = Join-Path $DemoRoot 'Folders'
    $obsVault = Join-Path $DemoRoot 'ObsidianVault'
    New-Item -ItemType Directory -Force -Path $vault, $prompts, $folders, $obsVault | Out-Null
    Copy-Item -Path (Join-Path $fixtures 'Vault\*') -Destination $vault -Recurse -Force
    Copy-Item -Path (Join-Path $fixtures 'Prompts\*') -Destination $prompts -Recurse -Force
    Copy-Item -Path (Join-Path $fixtures 'Folders\*') -Destination $folders -Recurse -Force
    Copy-Item -Path (Join-Path $fixtures 'ObsidianVault\*') -Destination $obsVault -Recurse -Force
    Move-Item -LiteralPath (Join-Path $vault 'note.md') -Destination (Join-Path $vault ($today + '.md')) -Force
    Move-Item -LiteralPath (Join-Path $vault 'note-prev.md') -Destination (Join-Path $vault ($prev + '.md')) -Force
    Replace-FixtureTokens (Join-Path $vault ($today + '.md')) $today $prev
    Replace-FixtureTokens (Join-Path $vault ($prev + '.md')) $today $prev

    $obsidian = 'D:\02-Apps\Obsidian\Obsidian.exe'
    if (-not (Test-Path -LiteralPath $obsidian)) { throw "Obsidian not found: $obsidian" }
    $configText = @"
[Paths]
Vault=$vault
PromptsDir=$prompts

[Appearance]
ThemeIndex=1
FontIndex=4
FontSizeIndex=3

[Folders]
Slot1=$folders
Slot1Zone=aux
Slot2=
Slot2Zone=aux
Slot3=
Slot3Zone=aux

[Apps]
Slot1=
Slot1Zone=aux
Slot2=$obsidian
Slot2Zone=work
Slot3=
Slot3Zone=aux

[Input]
CapsLockMap=0
"@
    Write-Utf8NoBom $configPath $configText

    # Obsidian ignores "exe + path"; it opens the vault marked open in obsidian.json.
    # Close real instances, register the temp vault as the only open one, restore later.
    Stop-Obsidian
    if ($hadObsidianConfig) {
        Copy-Item -LiteralPath $obsidianConfig -Destination $backupObsidianConfig -Force
    }
    Register-DemoObsidianVault $obsVault

    if ($recording) {
        [void](Ensure-Obs)
        $code = Run-Node -nodeArgs @($obsScript, 'setup', '--root', $DemoRoot, '--output', $OutputRoot) -stdout $obsLog -stderr $obsErr
        if ($code -ne 0) { throw "OBS setup failed: $code" }
        $obsSetup = $true
        Minimize-Obs
        $obsMinimized = $true
        Start-Sleep -Milliseconds 500
    } elseif (Get-Process -Name obs64 -ErrorAction SilentlyContinue) {
        # OBS title contains SevenNote (profile name); hide it from title-based window lookup.
        Minimize-Obs
        $obsMinimized = $true
    }

    Toggle-Desktop
    $desktopToggled = $true
    Start-Sleep -Milliseconds 500

    $appProc = Start-Process -FilePath $ahk -ArgumentList @('/ErrorStdOut', ('"' + $launcher + '"')) `
        -RedirectStandardError $appErr -PassThru
    Start-Sleep -Seconds 4
    if ($appProc.HasExited) { throw "SevenWork exited during startup" }

    $recordArg = if ($recording) { 'Record' } else { 'NoRecord' }
    $driverArgs = @('/ErrorStdOut', $driver, $Mode, $DemoRoot, $repo,
        $recordArg, $appProc.Id)
    $driverProc = Start-Process -FilePath $ahk -ArgumentList $driverArgs `
        -RedirectStandardError $driverErr -Wait -PassThru
    $driverCode = $driverProc.ExitCode
    Write-Host ("driver exit=" + $driverCode)
} finally {
    if ($appProc -and -not $appProc.HasExited) {
        Stop-Process -Id $appProc.Id -Force -ErrorAction SilentlyContinue
    }
    if ($desktopToggled) {
        Toggle-Desktop
        Start-Sleep -Milliseconds 300
    }
    Stop-Obsidian
    if ($hadObsidianConfig -and (Test-Path -LiteralPath $backupObsidianConfig)) {
        Copy-Item -LiteralPath $backupObsidianConfig -Destination $obsidianConfig -Force
    } elseif (-not $hadObsidianConfig -and (Test-Path -LiteralPath $obsidianConfig)) {
        Remove-Item -LiteralPath $obsidianConfig -Force -ErrorAction SilentlyContinue
    }
    if ($obsSetup) {
        try {
            Run-Node -nodeArgs @($obsScript, 'teardown', '--root', $DemoRoot) `
                -stdout (Join-Path $DemoRoot 'obs-teardown.log') `
                -stderr (Join-Path $DemoRoot 'obs-teardown.err.log') | Out-Null
        } catch {}
        Show-Obs
        if ($obsStarted) { Get-Process -Name obs64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
    } elseif ($obsMinimized) {
        Show-Obs
    }
    if ($originalConfig -and (Test-Path -LiteralPath $backupConfig)) {
        Copy-Item -LiteralPath $backupConfig -Destination $configPath -Force
    } elseif (-not $originalConfig -and (Test-Path -LiteralPath $configPath)) {
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    }

    $driverLog = Join-Path $DemoRoot 'driver.log'
    if (Test-Path -LiteralPath $driverLog) {
        Copy-Item -LiteralPath $driverLog -Destination (Join-Path $OutputRoot 'driver.log') -Force
    }
    if (Test-Path -LiteralPath $obsLog) {
        Copy-Item -LiteralPath $obsLog -Destination (Join-Path $OutputRoot 'obs.log') -Force
    }
    $obsDriverLog = Join-Path $DemoRoot 'obs-driver.log'
    if (Test-Path -LiteralPath $obsDriverLog) {
        Copy-Item -LiteralPath $obsDriverLog -Destination (Join-Path $OutputRoot 'obs-driver.log') -Force
    }
    $summary = "mode=$Mode`r`ndriver_exit=$driverCode`r`noutput=$OutputRoot`r`n"
    Write-Utf8NoBom (Join-Path $OutputRoot 'manifest.txt') $summary

    if (-not $Keep) {
        try { Remove-Item -LiteralPath $DemoRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

if ($driverCode -ne 0) { exit 1 }
Write-Host ("DEMO PASSED: " + $OutputRoot)
exit 0

