# ============================================================================
# Standalone Release Packaging Script for MedTRx DB Bloat Scanner
# ============================================================================
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReleaseDir = Join-Path $ScriptDir "release"
$ZipPath = Join-Path $ReleaseDir "MedTRx-DB-Bloat-Scanner-v1.0.0.zip"

if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
}

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}

$filesToPack = @(
    "scan_bloat.bat",
    "db_scanner.ps1",
    "scanner_diagnostic.sql",
    "config.ini",
    "config.ini.template",
    "README.md",
    "qa_check.ps1"
)

$targetFilePaths = $filesToPack | ForEach-Object { Join-Path $ScriptDir $_ }

Compress-Archive -Path $targetFilePaths -DestinationPath $ZipPath -Force

Write-Host "`n[+] Successfully created release archive: $ZipPath" -ForegroundColor Green
Get-Item $ZipPath | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
