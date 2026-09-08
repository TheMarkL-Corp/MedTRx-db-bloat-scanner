# MedTRx Database Bloat & Health Diagnostic Scanner

A lightweight, portable diagnostics and inspection tool designed for **MedTRx** and **AMiS** environments. It identifies potential database bloat, schedule duplications, legacy `GenPatientPrescription` record proliferation, un-vacuumed table storage, and active Windows Scheduled Tasks.

---

## 🔍 Diagnostic Capabilities

1. **Windows Task Scheduler Inspection**:
   - Inspects registered Windows scheduled tasks to detect background instances of `GenPatientPrescription.exe` or legacy SQL generators that continuously bloat the database.
2. **PostgreSQL Physical Storage & Dead Tuple Bloat**:
   - Queries `pg_stat_user_tables` to calculate live rows, dead row counts (`n_dead_tup`), and dead tuple percentages. Flags tables that require a `VACUUM FULL`.
3. **Prescription & Schedule Duplications (Logical Bloat)**:
   - Detects duplicate schedule slots `(Med_Order_Id, Schedule_Date, Schedule_Time)`.
   - Analyzes schedule distribution across historical, current, and future dates.
4. **Legacy AMiS v1 Schema Check (`AMiS_Patient_Prescription`)**:
   - Identifies if the legacy single-table schema exists, evaluates row volume, and checks if `GenPatientPrescription`'s 30 hardcoded seeds have multiplied over time without being purged.
5. **Clinical Entity Row Counts**:
   - Gathers row metrics for `Patients`, `Encounter`, `Prescriptions`, `Schedule`, and `AMiS_Patient_Medication_Dispense`.

---

## 🚀 How to Run

### 1-Click Execution (Recommended):
Double-click:
```cmd
scan_bloat.bat
```

### PowerShell Command Line:
```powershell
.\db_scanner.ps1
```
Or specify connection arguments explicitly:
```powershell
.\db_scanner.ps1 -DbHost "localhost" -DbPort "5433" -DbName "amisdbv2" -DbUser "apuser" -DbPassword "Syscom@123"
```

---

## 📁 Repository Layout

```
MedTRx-db-bloat-scanner/
├── scan_bloat.bat          # 1-click double-clickable runner
├── db_scanner.ps1          # Core PowerShell diagnostics orchestration
├── scanner_diagnostic.sql  # High-performance read-only diagnostic SQL suite
├── config.ini              # Active connection configuration
├── config.ini.template     # Configuration template
├── build_release.ps1       # Release zip packaging script
├── qa_check.ps1            # Automated test and AST validation suite
├── release/                # Generated portable zip distribution
└── README.md               # User & troubleshooting guide
```

---

## 🛠️ Interpreting Results & Remediation

| Indicator | Meaning | Recommended Action |
| :--- | :--- | :--- |
| **`Total Duplicate Schedule Slots > 0`** | Previous scripts copied rows into `Schedule` without deduplication checks. | Run deduplication query or use `MedTRx-demo-prescription-refresher` in-place shift. |
| **`AMiS_Patient_Prescription` has >30 rows** | `GenPatientPrescription.exe` ran daily without purging older dates. | Clean records older than current date or drop legacy table if migrating to v2. |
| **`Health Status: HIGH BLOAT` (`Dead % > 20%`)** | PostgreSQL has accumulated deleted/updated dead tuples on disk. | Execute `VACUUM (VERBOSE, ANALYZE);` or `VACUUM FULL;` during maintenance. |
| **Scheduled Task `GenPatientPrescription` Active** | Background task is continuously injecting records. | Disable or unregister the legacy scheduled task. |
