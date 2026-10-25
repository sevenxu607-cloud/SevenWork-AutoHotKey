# tools/build.ps1 -- build a portable SevenWork release
#
# ASCII only: Windows PowerShell 5.1 reads BOM-less .ps1 as system ANSI.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1 -SkipWebBuild
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1 -NoZip
#
# Output:
#   dist\SevenWork\SevenWork.exe
#   dist\SevenWork\web\dist\...
#   dist\SevenWork\WebView2Loader.dll
#   dist\SevenWork-<version>-portable.zip (unless -NoZip)
#
# Pandoc is intentionally NOT bundled. The Alt+M conversion feature is optional
# and detects pandoc.exe in Config.PandocPath or PATH at use time.

param(
    [switch]$SkipWebBuild,
    [switch]$NoZip
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$web = Join-Path $root 'web'
$webDist = Join-Path $web 'dist'
$stage = Join-Path $root 'dist\SevenWork'
$source = Join-Path $root 'SevenWork.ahk'
$loader = Join-Path $root 'src\lib\WebView2\64bit\WebView2Loader.dll'
$config = Join-Path $root 'src\WorkBench\Kernel\Config.ahk'

$ahk2exe = $env:SEVENWORK_AHK2EXE
if (-not $ahk2exe) { $ahk2exe = 'D:\02-Apps\AutoHotkey\Compiler\Ahk2Exe.exe' }
$ahkBase = $env:SEVENWORK_AHK_BASE
if (-not $ahkBase) { $ahkBase = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe' }

if (-not (Test-Path -LiteralPath $ahk2exe)) { throw "Ahk2Exe not found: $ahk2exe" }
if (-not (Test-Path -LiteralPath $ahkBase)) { throw "AutoHotkey64 base not found: $ahkBase" }
if (-not (Test-Path -LiteralPath $source)) { throw "Launcher not found: $source" }
if (-not (Test-Path -LiteralPath $loader)) { throw "WebView2Loader.dll not found: $loader" }

$version = '0.0.0'
$line = Select-String -Path $config -Pattern 'static Version\s*:=\s*"([^"]+)"' | Select-Object -First 1
if ($line) { $version = $line.Matches[0].Groups[1].Value }
$commit = 'unknown'
try { $commit = (git -C $root rev-parse --short HEAD).Trim() } catch {}

if (-not $SkipWebBuild) {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) { throw 'npm not found; install Node.js or use -SkipWebBuild' }
    Push-Location $web
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $web 'node_modules'))) {
            & $npm.Source ci
            if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
        }
        & $npm.Source run build
        if ($LASTEXITCODE -ne 0) { throw 'npm run build failed' }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $webDist 'index.html'))) {
    throw "web/dist/index.html not found: $webDist"
}

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$exe = Join-Path $stage 'SevenWork.exe'
$compileArgs = @(
    '/in', ('"' + $source + '"'),
    '/out', ('"' + $exe + '"'),
    '/base', ('"' + $ahkBase + '"'),
    '/compress', '2',
    '/silent'
)
$proc = Start-Process -FilePath $ahk2exe -ArgumentList $compileArgs -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) { throw "Ahk2Exe failed with exit code $($proc.ExitCode)" }
if (-not (Test-Path -LiteralPath $exe)) { throw "compiled exe not found: $exe" }

New-Item -ItemType Directory -Force -Path (Join-Path $stage 'web\dist') | Out-Null
Copy-Item -Path (Join-Path $webDist '*') -Destination (Join-Path $stage 'web\dist') -Recurse -Force
Copy-Item -LiteralPath $loader -Destination (Join-Path $stage 'WebView2Loader.dll') -Force
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $stage 'LICENSE') -Force
$readme = Join-Path $root 'README.md'
if (Test-Path -LiteralPath $readme) {
    Copy-Item -LiteralPath $readme -Destination (Join-Path $stage 'README.md') -Force
}
$notices = Join-Path $root 'THIRD-PARTY-NOTICES.txt'
if (Test-Path -LiteralPath $notices) {
    Copy-Item -LiteralPath $notices -Destination (Join-Path $stage 'THIRD-PARTY-NOTICES.txt') -Force
}

$buildInfo = @(
    "version=$version",
    "commit=$commit",
    "built=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
    "runtime=AutoHotkey v2 x64",
    "web=web/dist",
    "pandoc=optional (not bundled)"
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $stage 'BUILD.txt'), $buildInfo, [Text.UTF8Encoding]::new($false))

if (-not $NoZip) {
    $zip = Join-Path $root ("dist\SevenWork-" + $version + "-portable.zip")
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
    Write-Host ("ZIP: " + $zip)
}

Write-Host ("STAGE: " + $stage)
Write-Host ("VERSION: " + $version + " (" + $commit + ")")
