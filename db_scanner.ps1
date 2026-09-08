<#
.SYNOPSIS
    MedTRx Database Bloat & Prescription Diagnostic Scanner.
.DESCRIPTION
    Scans MedTRx (amisdbv2) and legacy AMiS (amisdb) databases for:
    - Dead tuple table bloat (un-vacuumed tables)
    - Schedule and prescription duplicate slots
    - Legacy GenPatientPrescription data accumulation
    - Active Windows scheduled tasks that could be causing bloat
#>
[CmdletBinding()]
param (
    [string]$ConfigPath = "",
    [string]$DbHost = "",
    [string]$DbPort = "",
    [string]$DbName = "",
    [string]$DbUser = "",
    [string]$DbPassword = "",
    [string]$PsqlPath = "",
    [switch]$NoPause
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParentDir = Split-Path -Parent $ScriptDir

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "               MedTRx Database Bloat & Health Diagnostic Scanner            " -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Resolve configuration
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (Test-Path (Join-Path $ScriptDir "config.ini")) {
        $ConfigPath = Join-Path $ScriptDir "config.ini"
    } elseif (Test-Path (Join-Path $ParentDir "config.ini")) {
        $ConfigPath = Join-Path $ParentDir "config.ini"
    }
}

$cfg = @{}
if (Test-Path $ConfigPath) {
    Write-Host "[*] Reading configuration from: $ConfigPath" -ForegroundColor Gray
    Get-Content -LiteralPath $ConfigPath | Where-Object { $_ -match '^\s*([^#;\[][^=]*)\s*=\s*(.*)$' } | ForEach-Object {
        $cfg[$matches[1].Trim()] = $matches[2].Trim()
    }
}

# Override / defaults
if (-not $DbHost) { $DbHost = if ($cfg.ContainsKey("host")) { $cfg["host"] } else { "localhost" } }
if (-not $DbPort) { $DbPort = if ($cfg.ContainsKey("port")) { $cfg["port"] } else { "5433" } }
if (-not $DbName) { $DbName = if ($cfg.ContainsKey("dbname")) { $cfg["dbname"] } else { "amisdbv2" } }
if (-not $DbUser) { $DbUser = if ($cfg.ContainsKey("user")) { $cfg["user"] } else { "apuser" } }
if (-not $DbPassword) { $DbPassword = if ($cfg.ContainsKey("password")) { $cfg["password"] } else { "Syscom@123" } }
if (-not $PsqlPath) { $PsqlPath = if ($cfg.ContainsKey("psql_path")) { $cfg["psql_path"] } else { "" } }

# 2. Locate psql.exe
if (-not $PsqlPath -or -not (Test-Path $PsqlPath)) {
    $psqlCmd = Get-Command psql.exe -ErrorAction SilentlyContinue
    if ($psqlCmd) {
        $PsqlPath = $psqlCmd.Source
    } else {
        foreach ($v in @(17, 16, 15, 14, 13, 12, 11, 10)) {
            $candidate = "C:\Program Files\PostgreSQL\$v\bin\psql.exe"
            if (Test-Path $candidate) { $PsqlPath = $candidate; break }
            $candidateX86 = "C:\Program Files (x86)\PostgreSQL\$v\bin\psql.exe"
            if (Test-Path $candidateX86) { $PsqlPath = $candidateX86; break }
        }
    }
}

if (-not $PsqlPath -or -not (Test-Path $PsqlPath)) {
    Write-Host "[ERROR] psql.exe was not found. Please install PostgreSQL or configure psql_path in config.ini." -ForegroundColor Red
    if (-not $NoPause) { Read-Host "Press Enter to exit..." }
    exit 1
}

Write-Host "[*] Target Host : $DbHost`:$DbPort" -ForegroundColor DarkCyan
Write-Host "[*] Target DB   : $DbName (User: $DbUser)" -ForegroundColor DarkCyan
Write-Host "[*] psql Engine : $PsqlPath" -ForegroundColor DarkCyan
Write-Host ""

# 3. Check Windows Scheduled Tasks for potential rogue / legacy apps
Write-Host ">>> STEP 1: Windows Task Scheduler Audit (Bloat Generators)" -ForegroundColor Yellow
$potentialTasks = @()
try {
    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    foreach ($t in $allTasks) {
        $match = $false
        if ($t.TaskName -match 'GenPatient|Prescription|AMiS|MedTRx|ScheduleIdGen|Daily_Prescription') { $match = $true }
        if ($t.Actions) {
            foreach ($act in $t.Actions) {
                if ($act.Execute -match 'GenPatientPrescription|refresh_daily_prescriptions|generate_today_schedule|ScheduleIdGen') {
                    $match = $true
                }
            }
        }
        if ($match) { $potentialTasks += $t }
    }
} catch {
    Write-Host "  [!] Warning: Unable to inspect Scheduled Tasks (may require admin privileges)." -ForegroundColor Gray
}

if ($potentialTasks.Count -gt 0) {
    Write-Host "  Found $($potentialTasks.Count) scheduled task(s) related to prescriptions:" -ForegroundColor White
    foreach ($t in $potentialTasks) {
        $stateColor = if ($t.State -eq "Ready") { "Green" } elseif ($t.State -eq "Running") { "Magenta" } else { "Gray" }
        Write-Host "  - Task: $($t.TaskName) [State: $($t.State)]" -ForegroundColor $stateColor
        if ($t.TaskName -match 'GenPatient') {
            Write-Host "    [WARNING] 'GenPatientPrescription' is registered! This task periodically injects duplicate legacy prescriptions!" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  [OK] No active 'GenPatientPrescription' scheduled tasks detected." -ForegroundColor Green
}
Write-Host ""

# 4. Run PostgreSQL Diagnostic Script
Write-Host ">>> STEP 2: Database Storage & Data Redundancy Audit" -ForegroundColor Yellow
$sqlScript = Join-Path $ScriptDir "scanner_diagnostic.sql"

$env:PGPASSWORD = $DbPassword
$psqlArgs = @(
    "-h", $DbHost,
    "-p", $DbPort,
    "-U", $DbUser,
    "-d", $DbName,
    "-f", $sqlScript
)

try {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $PsqlPath
    $pinfo.Arguments = "-h $DbHost -p $DbPort -U $DbUser -d $DbName -f `"$sqlScript`""
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $env:PGPASSWORD = $null

    if ($proc.ExitCode -eq 0) {
        Write-Host $stdout
        if ($stderr) {
            Write-Host $stderr -ForegroundColor Gray
        }
    } else {
        Write-Host "[ERROR] psql failed with Exit Code: $($proc.ExitCode)" -ForegroundColor Red
        if ($stderr) { Write-Host $stderr -ForegroundColor Red }
        if ($stdout) { Write-Host $stdout }
    }
} catch {
    Write-Host "[ERROR] Failed to execute psql: $_" -ForegroundColor Red
    $env:PGPASSWORD = $null
}

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Scanner completed. Check alerts above to identify bloating in tables." -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

if (-not $NoPause) {
    Write-Host ""
    Read-Host "Press Enter to exit..."
}
