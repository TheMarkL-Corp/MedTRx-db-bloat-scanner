-- ============================================================================
-- MedTRx DB Bloat & Data Health Diagnostic Scanner
-- Target: amisdbv2 / amisdb (PostgreSQL)
-- Mode: READ-ONLY (No data modifications)
-- ============================================================================

\pset footer off

\echo ============================================================================
\echo [1/5] DATABASE SIZE & STORAGE OVERVIEW
\echo ============================================================================

SELECT
    current_database() AS "Database",
    pg_size_pretty(pg_database_size(current_database())) AS "Total DB Size";

\echo(
\echo ============================================================================
\echo [2/5] TOP TABLES BY DISK USAGE & DEAD TUPLE RATIO (PHYSICAL BLOAT)
\echo ============================================================================

SELECT
    schemaname || '.' || relname AS "Table",
    n_live_tup AS "Live Rows",
    n_dead_tup AS "Dead Rows",
    ROUND(
        CASE WHEN (n_live_tup + n_dead_tup) > 0
             THEN (n_dead_tup::numeric / (n_live_tup + n_dead_tup)::numeric) * 100
             ELSE 0
        END, 1
    ) AS "Dead %",
    pg_size_pretty(pg_total_relation_size(relid)) AS "Total Size",
    pg_size_pretty(pg_relation_size(relid)) AS "Table Size",
    pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS "Index Size",
    CASE
        WHEN n_dead_tup > 10000 AND (n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0)::numeric) > 0.20 THEN 'HIGH BLOAT (Needs VACUUM)'
        WHEN n_dead_tup > 1000 THEN 'MODERATE DEAD TUPLES'
        ELSE 'OPTIMAL'
    END AS "Health Status"
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 12;

\echo(
\echo ============================================================================
\echo [3/5] PRESCRIPTION & SCHEDULE DUPLICATION AUDIT (LOGICAL BLOAT)
\echo ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'Schedule') THEN
        RAISE NOTICE 'Analyzing MedTRx v2 "Schedule" and "Prescriptions" tables...';
    ELSE
        RAISE NOTICE 'Table "Schedule" not found in current database. Skipping MedTRx v2 schedule audit.';
    END IF;
END $$;

-- Check Schedule duplicate slots
SELECT
    COALESCE(SUM(dup_count - 1), 0) AS "Total Duplicate Schedule Slots",
    COUNT(*) AS "Unique (Order, Date, Time) Combos Duplicated"
FROM (
    SELECT "Med_Order_Id", "Schedule_Date", "Schedule_Time", COUNT(*) as dup_count
    FROM "public"."Schedule"
    GROUP BY "Med_Order_Id", "Schedule_Date", "Schedule_Time"
    HAVING COUNT(*) > 1
) sub;

-- Detailed Schedule distribution across dates
SELECT
    "Schedule_Date",
    COUNT(*) AS "Total Schedules",
    COUNT(DISTINCT "Med_Order_Id") AS "Distinct Prescriptions",
    COUNT(CASE WHEN "Schedule_Status" = '01' THEN 1 END) AS "Pending ('01')",
    COUNT(CASE WHEN "Schedule_Status" != '01' THEN 1 END) AS "Processed/Other",
    CASE
        WHEN "Schedule_Date" < CURRENT_DATE THEN 'Past Date (Historical/Accumulated)'
        WHEN "Schedule_Date" = CURRENT_DATE THEN 'Active Today'
        ELSE 'Future Scheduled'
    END AS "Date Category"
FROM "public"."Schedule"
GROUP BY "Schedule_Date"
ORDER BY "Schedule_Date" DESC
LIMIT 15;

\echo(
\echo ============================================================================
\echo [4/5] LEGACY AMIS v1 "AMiS_Patient_Prescription" INFILTRATION AUDIT
\echo ============================================================================

DO $$
DECLARE
    v_cnt bigint := 0;
    v_legacy_dates integer := 0;
    v_min_date text;
    v_max_date text;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'AMiS_Patient_Prescription') THEN
        EXECUTE 'SELECT COUNT(*) FROM "public"."AMiS_Patient_Prescription"' INTO v_cnt;
        EXECUTE 'SELECT COUNT(DISTINCT DATE("Create_Time")), MIN(DATE("Create_Time"))::text, MAX(DATE("Create_Time"))::text FROM "public"."AMiS_Patient_Prescription"' INTO v_legacy_dates, v_min_date, v_max_date;
        RAISE NOTICE '[ALERT] Legacy table "AMiS_Patient_Prescription" EXISTS!';
        RAISE NOTICE '  Total Legacy Rows: %', v_cnt;
        RAISE NOTICE '  Distinct Injection Days: %, Range: % to %', v_legacy_dates, v_min_date, v_max_date;
        IF v_cnt > 30 THEN
            RAISE WARNING '[BLOAT DETECTED] "GenPatientPrescription" has accumulated % rows over % days!', v_cnt, v_legacy_dates;
        END IF;
    ELSE
        RAISE NOTICE '[OK] Legacy table "AMiS_Patient_Prescription" does NOT exist in this database.';
    END IF;
END $$;

\echo(
\echo ============================================================================
\echo [5/5] CLINICAL DATA SUMMARY METRICS
\echo ============================================================================

SELECT
    (SELECT COUNT(*) FROM "public"."Patients") AS "Total Patients",
    (SELECT COUNT(*) FROM "public"."Encounter") AS "Total Encounters",
    (SELECT COUNT(*) FROM "public"."Encounter" WHERE "Discharge_Date" IS NULL) AS "Active Encounters",
    (SELECT COUNT(*) FROM "public"."Prescriptions") AS "Total Prescriptions",
    (SELECT COUNT(*) FROM "public"."Schedule") AS "Total Schedules",
    (SELECT COUNT(*) FROM "public"."AMiS_Patient_Medication_Dispense") AS "Total Dispense Logs";

\echo(
\echo ============================================================================
\echo DIAGNOSTIC AUDIT COMPLETE
\echo ============================================================================
