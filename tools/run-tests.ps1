# run-tests.ps1 - run tests\RunTests.ahk and report the result.
#
# ASCII only on purpose: powershell.exe 5.1 reads a BOM-less .ps1 as system
# ANSI, so any non-ASCII character here would be mangled before it is parsed.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-tests.ps1
#
# Exit code: 0 = all assertions passed, 1 = failures or runner crashed

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe  = 'D:\02-Apps\AutoHotkey\v2\AutoHotkey64.exe'
$test = Join-Path $root 'tests\RunTests.ahk'
$log  = Join-Path $env:TEMP 'SevenWorkDev\tests.log'
$err  = Join-Path $env:TEMP 'SevenWorkDev\runner-stderr.txt'

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host ("FAIL  AutoHotkey not found: " + $exe)
    exit 1
}
if (-not (Test-Path -LiteralPath $test)) {
    Write-Host ("FAIL  test runner not found: " + $test)
    exit 1
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $err) | Out-Null
if (Test-Path -LiteralPath $err) { Remove-Item -LiteralPath $err -Force }
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }

# AHK is a GUI-subsystem exe: the call operator does not wait for it, and
# $LASTEXITCODE keeps its previous value (usually 0), which looks like success.
# Always use Start-Process -Wait -PassThru.
$p = Start-Process -FilePath $exe `
     -ArgumentList @('/ErrorStdOut', ('"' + $test + '"')) `
     -RedirectStandardError $err -Wait -PassThru

if (Test-Path -LiteralPath $log) {
    Get-Content -LiteralPath $log -Encoding UTF8
} else {
    Write-Host 'WARN  the runner did not write a log file'
}

if (Test-Path -LiteralPath $err) {
    $e = Get-Content -LiteralPath $err -Raw
    if ($e) {
        Write-Host ''
        Write-Host '--- stderr ---'
        Write-Host $e.Trim()
    }
}

Write-Host ''
if ($p.ExitCode -eq 0) {
    Write-Host '=== TESTS PASSED ==='
    exit 0
}
Write-Host ("=== TESTS FAILED (exit " + $p.ExitCode + ") ===")
exit 1
