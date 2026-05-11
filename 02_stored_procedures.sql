-- =============================================================================
-- 02_stored_procedures.sql
-- Run this ONCE after 01_create_database_and_tables.sql
--
-- Creates 4 stored procedures:
--   usp_DisableConstraints   — disables all FK constraints
--   usp_TruncateAllTables    — truncates all 9 tables
--   usp_LoadAllData          — bulk inserts all 9 CSVs
--   usp_EnableConstraints    — re-enables and validates all FK constraints
--
-- These procedures are called by 03_reload_data.sql on every data refresh.
-- =============================================================================

USE FMCG_Inventory;
GO


-- =============================================================================
-- PROCEDURE 1: usp_DisableConstraints
-- Disables all foreign key constraints across the database.
-- Must be called before truncating tables.
-- =============================================================================

IF OBJECT_ID('usp_DisableConstraints', 'P') IS NOT NULL
    DROP PROCEDURE usp_DisableConstraints;
GO

CREATE PROCEDURE usp_DisableConstraints
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX) = '';

    SELECT @sql += 'ALTER TABLE ' + QUOTENAME(OBJECT_NAME(parent_object_id))
                 + ' NOCHECK CONSTRAINT ' + QUOTENAME(name) + ';' + CHAR(13)
    FROM sys.foreign_keys;

    EXEC sp_executesql @sql;

    PRINT 'All foreign key constraints disabled.';
END;
GO


-- =============================================================================
-- PROCEDURE 2: usp_TruncateAllTables
-- Truncates all 9 tables in correct order (child tables first).
-- Must be called after usp_DisableConstraints.
-- =============================================================================

IF OBJECT_ID('usp_TruncateAllTables', 'P') IS NOT NULL
    DROP PROCEDURE usp_TruncateAllTables;
GO

CREATE PROCEDURE usp_TruncateAllTables
AS
BEGIN
    SET NOCOUNT ON;

    -- TRUNCATE does not work even with FK constraints disabled.
    -- DELETE works regardless and is fast enough for this dataset size.

    -- Fact tables first (children)
    DELETE FROM fact_sale_batch_map;
    DELETE FROM fact_stockout_events;
    DELETE FROM fact_inventory_adjustments;
    DELETE FROM fact_goods_receipts;
    DELETE FROM fact_sales;

    -- Dimension tables (parents)
    DELETE FROM dim_supplier_products;
    DELETE FROM dim_suppliers;
    DELETE FROM dim_warehouses;
    DELETE FROM dim_products;

    PRINT 'All 9 tables cleared.';
END;
GO


-- =============================================================================
-- PROCEDURE 3: usp_LoadAllData
-- Bulk inserts all 9 CSVs from the output folder.
-- Must be called after usp_TruncateAllTables.
-- =============================================================================

IF OBJECT_ID('usp_LoadAllData', 'P') IS NOT NULL
    DROP PROCEDURE usp_LoadAllData;
GO

CREATE PROCEDURE usp_LoadAllData
AS
BEGIN
    SET NOCOUNT ON;

    -- ── Dimension tables ─────────────────────────────────────────────────────

    BULK INSERT dim_products
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\dim_products.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'dim_products loaded.';

    BULK INSERT dim_warehouses
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\dim_warehouses.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'dim_warehouses loaded.';

    BULK INSERT dim_suppliers
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\dim_suppliers.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'dim_suppliers loaded.';

    BULK INSERT dim_supplier_products
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\dim_supplier_products.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'dim_supplier_products loaded.';

    -- ── Fact tables ──────────────────────────────────────────────────────────

    BULK INSERT fact_sales
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\fact_sales.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'fact_sales loaded.';

    BULK INSERT fact_goods_receipts
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\fact_goods_receipts.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'fact_goods_receipts loaded.';

    BULK INSERT fact_sale_batch_map
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\fact_sale_batch_map.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'fact_sale_batch_map loaded.';

    BULK INSERT fact_inventory_adjustments
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\fact_inventory_adjustments.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'fact_inventory_adjustments loaded.';

    BULK INSERT fact_stockout_events
    FROM 'F:\LIBRARY\PORTFOLIO\08_Batch-Aware Inventory Design\output\fact_stockout_events.csv'
    WITH (
        FORMAT          = 'CSV',
        FIRSTROW        = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR   = '\n',
        TABLOCK
    );
    PRINT 'fact_stockout_events loaded.';

    PRINT 'All 9 CSVs loaded successfully.';
END;
GO


-- =============================================================================
-- PROCEDURE 4: usp_EnableConstraints
-- Re-enables and validates all foreign key constraints.
-- Must be called after usp_LoadAllData.
-- =============================================================================

IF OBJECT_ID('usp_EnableConstraints', 'P') IS NOT NULL
    DROP PROCEDURE usp_EnableConstraints;
GO

CREATE PROCEDURE usp_EnableConstraints
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX) = '';

    SELECT @sql += 'ALTER TABLE ' + QUOTENAME(OBJECT_NAME(parent_object_id))
                 + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(name) + ';' + CHAR(13)
    FROM sys.foreign_keys;

    EXEC sp_executesql @sql;

    PRINT 'All foreign key constraints re-enabled and validated.';

    -- Show row counts as confirmation
    SELECT 'dim_products'               AS table_name, COUNT(*) AS row_count FROM dim_products
    UNION ALL
    SELECT 'dim_warehouses',                           COUNT(*) FROM dim_warehouses
    UNION ALL
    SELECT 'dim_suppliers',                            COUNT(*) FROM dim_suppliers
    UNION ALL
    SELECT 'dim_supplier_products',                    COUNT(*) FROM dim_supplier_products
    UNION ALL
    SELECT 'fact_sales',                               COUNT(*) FROM fact_sales
    UNION ALL
    SELECT 'fact_goods_receipts',                      COUNT(*) FROM fact_goods_receipts
    UNION ALL
    SELECT 'fact_sale_batch_map',                      COUNT(*) FROM fact_sale_batch_map
    UNION ALL
    SELECT 'fact_inventory_adjustments',               COUNT(*) FROM fact_inventory_adjustments
    UNION ALL
    SELECT 'fact_stockout_events',                     COUNT(*) FROM fact_stockout_events;
END;
GO

PRINT 'All 4 stored procedures created. Now run 03_reload_data.sql';
GO