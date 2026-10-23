# check-docs.ps1 - documentation health check.
# ASCII only on purpose: powershell.exe 5.1 reads a BOM-less .ps1 as system ANSI,
# so any non-ASCII character here would be mangled before it is parsed.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-docs.ps1
#
# Checks
#   1) relative links in *.md exist on disk
#   2) *.md  = LF, no BOM           (see .gitattributes)
#   3) *.ahk = CRLF, no BOM
#   4) README badge version == Config.Version
#   5) line counts (informational)
#
# Exit code: 0 = all pass, 1 = at least one failure

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:failCount = 0

function Rel([string]$p) { return $p.Replace($root + '\', '') }

function Get-EolInfo([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $crlf = 0; $cr = 0; $lf = 0
    for ($i = 0; $i -lt $b.Length; $i++) {
        if ($b[$i] -eq 13 -and ($i + 1) -lt $b.Length -and $b[$i + 1] -eq 10) { $crlf++; $i++ }
        elseif ($b[$i] -eq 13) { $cr++ }
        elseif ($b[$i] -eq 10) { $lf++ }
    }
    return @{ Bom = $bom; Crlf = $crlf; Cr = $cr; Lf = $lf }
}

# ---------- collect files ----------
$mdFiles = @()
$mdFiles += Get-ChildItem -LiteralPath $root -Filter *.md -File
$mdFiles += Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Filter *.md -File -Recurse
$mdFiles += Get-ChildItem -LiteralPath (Join-Path $root '.clinerules') -Filter *.md -File
$mdFiles = $mdFiles | Where-Object { $_.FullName -notmatch '\\\.git\\' } | Sort-Object FullName

$ahkFiles = @()
$ahkFiles += Get-ChildItem -LiteralPath $root -Filter *.ahk -File
$ahkFiles += Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter *.ahk -File -Recurse
# tests\ holds the pure-logic runner; same CRLF/no-BOM rule applies there.
$testsDir = Join-Path $root 'tests'
if (Test-Path -LiteralPath $testsDir) {
    $ahkFiles += Get-ChildItem -LiteralPath $testsDir -Filter *.ahk -File -Recurse
}
# src\lib\ holds third-party AHK bindings (WebView2). Keep them byte-identical to
# upstream: converting their line endings would have to be redone on every upgrade,
# and the diff would be pure whitespace noise.
$ahkFiles = $ahkFiles | Where-Object { $_.FullName -notlike '*\src\lib\*' }
$ahkFiles = $ahkFiles | Sort-Object FullName

# ---------- 1) links ----------
Write-Host ''
Write-Host '=== 1) relative links ==='
$linkRe = [regex]'\]\(([^)\s]+)\)'
$linkTotal = 0
$badLinks = 0
foreach ($f in $mdFiles) {
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    # Skip fenced code blocks: sample paths inside them are not real links.
    $inFence = $false
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($ln in ($text -split "`r?`n")) {
        if ($ln -match '^\s*```') { $inFence = -not $inFence; continue }
        if (-not $inFence) { [void]$kept.Add($ln) }
    }
    $scan = ($kept -join "`n")
    foreach ($m in $linkRe.Matches($scan)) {
        $raw = $m.Groups[1].Value
        if ($raw -match '^(https?:|mailto:|#|data:)') { continue }
        $target = $raw.Split('#')[0]
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $linkTotal++
        $full = Join-Path $f.DirectoryName ($target.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $full)) {
            Write-Host ("  FAIL  {0} -> {1}" -f (Rel $f.FullName), $raw)
            $badLinks++
        }
    }
}
if ($badLinks -eq 0) {
    Write-Host ("  PASS  {0} link(s) in {1} file(s)" -f $linkTotal, $mdFiles.Count)
} else {
    $script:failCount += $badLinks
}

# ---------- 2) md = LF, no BOM ----------
Write-Host ''
Write-Host '=== 2) *.md encoding (LF, no BOM) ==='
$badMd = 0
foreach ($f in $mdFiles) {
    $e = Get-EolInfo $f.FullName
    if ($e.Bom -or $e.Crlf -gt 0 -or $e.Cr -gt 0) {
        Write-Host ("  FAIL  {0}  BOM={1} CRLF={2} bareCR={3}" -f (Rel $f.FullName), $e.Bom, $e.Crlf, $e.Cr)
        $badMd++
    }
}
if ($badMd -eq 0) { Write-Host ("  PASS  {0} file(s)" -f $mdFiles.Count) } else { $script:failCount += $badMd }

# ---------- 3) ahk = CRLF, no BOM ----------
Write-Host ''
Write-Host '=== 3) *.ahk encoding (CRLF, no BOM) ==='
$badAhk = 0
foreach ($f in $ahkFiles) {
    $e = Get-EolInfo $f.FullName
    if ($e.Bom -or $e.Lf -gt 0 -or $e.Cr -gt 0) {
        Write-Host ("  FAIL  {0}  BOM={1} bareLF={2} bareCR={3}" -f (Rel $f.FullName), $e.Bom, $e.Lf, $e.Cr)
        $badAhk++
    }
}
if ($badAhk -eq 0) { Write-Host ("  PASS  {0} file(s)" -f $ahkFiles.Count) } else { $script:failCount += $badAhk }

# ---------- 4) version consistency ----------
Write-Host ''
Write-Host '=== 4) version: README badge vs Config.Version ==='
$cfgPath = Join-Path $root 'src\WorkBench\Kernel\Config.ahk'
$readmePath = Join-Path $root 'README.md'
$cfgText = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
$readmeText = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
$mCfg = [regex]::Match($cfgText, 'static\s+Version\s*:=\s*"([\d.]+)"')
$mBadge = [regex]::Match($readmeText, 'badge/version-([\d.]+)-')
if (-not $mCfg.Success) {
    Write-Host '  FAIL  cannot parse Config.Version'
    $script:failCount++
} elseif (-not $mBadge.Success) {
    Write-Host '  FAIL  cannot parse README version badge'
    $script:failCount++
} elseif ($mCfg.Groups[1].Value -ne $mBadge.Groups[1].Value) {
    Write-Host ("  FAIL  README badge {0} != Config.Version {1}" -f $mBadge.Groups[1].Value, $mCfg.Groups[1].Value)
    $script:failCount++
} else {
    Write-Host ("  PASS  {0} (README badge == Config.Version)" -f $mCfg.Groups[1].Value)
}

# ---------- 5) line counts ----------
Write-Host ''
Write-Host '=== 5) line counts (informational) ==='
foreach ($f in $mdFiles) {
    $n = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8).Length
    Write-Host ("  {0,5}  {1}" -f $n, (Rel $f.FullName))
}

# ---------- 6) fenced code blocks balanced ----------
Write-Host ''
Write-Host '=== 6) fenced code blocks (must be even) ==='
$badFence = 0
foreach ($f in $mdFiles) {
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $n = 0
    foreach ($ln in ($text -split "`r?`n")) { if ($ln -match '^\s*```') { $n++ } }
    if (($n % 2) -ne 0) {
        Write-Host ("  FAIL  {0}  fence lines = {1} (odd)" -f (Rel $f.FullName), $n)
        $badFence++
    }
}
if ($badFence -eq 0) { Write-Host ("  PASS  {0} file(s)" -f $mdFiles.Count) } else { $script:failCount += $badFence }

# ---------- summary ----------
Write-Host ''
if ($script:failCount -eq 0) {
    Write-Host '=== RESULT: all checks passed ==='
    exit 0
}
Write-Host ("=== RESULT: {0} failure(s) ===" -f $script:failCount)
exit 1
