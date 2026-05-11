-- =============================================================================
-- 03_reload_data.sql
-- Run this EVERY TIME you want to refresh data after running run.py
--
-- Prerequisites:
--   01_create_database_and_tables.sql  must have been run once
--   02_stored_procedures.sql           must have been run once
--
-- What this does:
--   1. Disables all FK constraints
--   2. Truncates all 9 tables
--   3. Loads all 9 CSVs fresh from the output folder
--   4. Re-enables and validates all FK constraints
--   5. Shows final row counts
-- =============================================================================

USE FMCG_Inventory;
GO

PRINT '========================================';
PRINT ' FMCG Inventory — Data Reload Starting';
PRINT '========================================';

EXEC usp_DisableConstraints;
EXEC usp_TruncateAllTables;
EXEC usp_LoadAllData;
EXEC usp_EnableConstraints;

PRINT '========================================';
PRINT ' Data Reload Complete';
PRINT '========================================';
GO
