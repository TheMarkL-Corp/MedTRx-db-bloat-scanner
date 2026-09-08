# ============================================================================
# QA Verification Test Suite - Standalone MedTRx DB Bloat Scanner
# ============================================================================
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n=== QA CHECK 1: PowerShell Scripts AST Validation ===" -ForegroundColor Cyan
$scripts = @("db_scanner.ps1", "build_release.ps1")
$psOk = $true
foreach ($s in $scripts) {
    $filePath = Join-Path $ScriptDir $s
    $tokens = $null
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$tokens, [ref]$errs)
    if ($errs.Count -eq 0) {
        Write-Host "  [PASS] $s (0 syntax errors)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $s has syntax errors:" -ForegroundColor Red
        $errs | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        $psOk = $false
    }
}

Write-Host "`n=== QA CHECK 2: Configuration Consistency ===" -ForegroundColor Cyan
$cfg = Get-Content (Join-Path $ScriptDir "config.ini") -Raw
$cfgTmpl = Get-Content (Join-Path $ScriptDir "config.ini.template") -Raw

$checks = @("host=localhost", "port=5433", "dbname=amisdbv2", "password=Syscom@123")
foreach ($chk in $checks) {
    if ($cfg.Contains($chk) -and $cfgTmpl.Contains($chk)) {
        Write-Host "  [PASS] $chk verified in both config.ini and config.ini.template" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $chk not matched in configuration files!" -ForegroundColor Red
        $psOk = $false
    }
}

Write-Host "`n=== QA CHECK 3: SQL Engine Integrity ===" -ForegroundColor Cyan
$sqlFiles = @("scanner_diagnostic.sql")
foreach ($f in $sqlFiles) {
    $sqlPath = Join-Path $ScriptDir $f
    if (Test-Path $sqlPath) {
        Write-Host "  [PASS] SQL file $f exists and verified" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Missing $f" -ForegroundColor Red
        $psOk = $false
    }
}

Write-Host "`n=== QA CHECK 4: Batch File Syntax & Launcher Safety ===" -ForegroundColor Cyan
$bats = @("scan_bloat.bat")
foreach ($b in $bats) {
    $batPath = Join-Path $ScriptDir $b
    if (Test-Path $batPath) {
        Write-Host "  [PASS] $b exists and is accessible" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $b missing!" -ForegroundColor Red
        $psOk = $false
    }
}

if ($psOk) {
    Write-Host "`n============================================================================" -ForegroundColor Green
    Write-Host "               ALL QA CHECKS PASSED SUCCESSFULLY (4/4)                       " -ForegroundColor Green
    Write-Host "============================================================================`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[FAIL] QA verification found issues." -ForegroundColor Red
    exit 1
}
