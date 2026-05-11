-- =============================================================================
-- 01_create_database_and_tables.sql
-- Run this ONCE only during initial setup.
--
-- What this script does:
--   1. Creates the FMCG_Inventory database
--   2. Creates all 9 tables with correct data types
--   3. Applies primary keys
--   4. Applies foreign keys
--
-- After running this script, run:
--   02_stored_procedures.sql  (also once only)
--   03_reload_data.sql        (every time you refresh data)
-- =============================================================================


-- =============================================================================
-- STEP 1 — CREATE DATABASE
-- =============================================================================

USE master;
GO

IF NOT EXISTS (
    SELECT name FROM sys.databases WHERE name = 'FMCG_Inventory'
)
BEGIN
    CREATE DATABASE FMCG_Inventory;
    PRINT 'Database FMCG_Inventory created.';
END
ELSE
    PRINT 'Database FMCG_Inventory already exists — skipping.';
GO

USE FMCG_Inventory;
GO


-- =============================================================================
-- STEP 2 — CREATE TABLES
-- =============================================================================

-- ── dim_products ─────────────────────────────────────────────────────────────
CREATE TABLE dim_products (
    product_id       VARCHAR(10)    NOT NULL,
    product_name     VARCHAR(100)   NOT NULL,
    category         VARCHAR(50)    NOT NULL,
    unit_size        VARCHAR(20)    NOT NULL,
    base_cost        DECIMAL(10,2)  NOT NULL,
    base_price       DECIMAL(10,2)  NOT NULL,
    shelf_life_days  INT            NOT NULL,
    launch_date      DATE           NOT NULL,
    status           VARCHAR(10)    NOT NULL
);

-- ── dim_warehouses ───────────────────────────────────────────────────────────
CREATE TABLE dim_warehouses (
    warehouse_id            VARCHAR(10)   NOT NULL,
    warehouse_name          VARCHAR(100)  NOT NULL,
    city                    VARCHAR(50)   NOT NULL,
    region                  VARCHAR(20)   NOT NULL,
    storage_capacity_units  INT           NOT NULL,
    cold_storage_flag       TINYINT       NOT NULL
);

-- ── dim_suppliers ────────────────────────────────────────────────────────────
CREATE TABLE dim_suppliers (
    supplier_id              VARCHAR(10)   NOT NULL,
    supplier_name            VARCHAR(100)  NOT NULL,
    supplier_city            VARCHAR(50)   NOT NULL,
    average_lead_time_days   INT           NOT NULL,
    reliability_score        DECIMAL(5,2)  NOT NULL,
    contract_start_date      DATE          NOT NULL
);

-- ── dim_supplier_products ────────────────────────────────────────────────────
CREATE TABLE dim_supplier_products (
    product_id   VARCHAR(10)  NOT NULL,
    supplier_id  VARCHAR(10)  NOT NULL,
    is_primary   TINYINT      NOT NULL
);

-- ── fact_sales ───────────────────────────────────────────────────────────────
CREATE TABLE fact_sales (
    sale_id                 VARCHAR(15)   NOT NULL,
    sale_date               DATE          NOT NULL,
    warehouse_id            VARCHAR(10)   NOT NULL,
    product_id              VARCHAR(10)   NOT NULL,
    quantity_sold           INT           NOT NULL,
    selling_price_per_unit  DECIMAL(10,2) NOT NULL,
    discount_percent        DECIMAL(5,2)  NOT NULL,
    promotion_flag          TINYINT       NOT NULL
);

-- ── fact_goods_receipts ──────────────────────────────────────────────────────
CREATE TABLE fact_goods_receipts (
    receipt_id                VARCHAR(15)   NOT NULL,
    batch_id                  VARCHAR(15)   NOT NULL,
    product_id                VARCHAR(10)   NOT NULL,
    supplier_id               VARCHAR(10)   NOT NULL,
    warehouse_id              VARCHAR(10)   NOT NULL,
    receipt_date              DATE          NOT NULL,
    manufacture_date          DATE          NOT NULL,
    expiry_date               DATE          NOT NULL,
    quantity_received         INT           NOT NULL,
    purchase_price_per_unit   DECIMAL(10,4) NOT NULL,
    total_batch_cost          DECIMAL(12,2) NOT NULL
);

-- ── fact_sale_batch_map ──────────────────────────────────────────────────────
CREATE TABLE fact_sale_batch_map (
    sale_id              VARCHAR(15)   NOT NULL,
    batch_id             VARCHAR(15)   NOT NULL,
    quantity_from_batch  INT           NOT NULL,
    unit_cost_at_sale    DECIMAL(10,4) NOT NULL
);

-- ── fact_inventory_adjustments ───────────────────────────────────────────────
CREATE TABLE fact_inventory_adjustments (
    adjustment_id     VARCHAR(15)   NOT NULL,
    adjustment_date   DATE          NOT NULL,
    warehouse_id      VARCHAR(10)   NOT NULL,
    product_id        VARCHAR(10)   NOT NULL,
    batch_id          VARCHAR(15)   NOT NULL,
    adjustment_type   VARCHAR(20)   NOT NULL,
    quantity_adjusted INT           NOT NULL,
    reason_notes      VARCHAR(200)  NOT NULL
);

-- ── fact_stockout_events ─────────────────────────────────────────────────────
CREATE TABLE fact_stockout_events (
    stockout_id        VARCHAR(15)  NOT NULL,
    stockout_date      DATE         NOT NULL,
    warehouse_id       VARCHAR(10)  NOT NULL,
    product_id         VARCHAR(10)  NOT NULL,
    quantity_demanded  INT          NOT NULL,
    quantity_supplied  INT          NOT NULL,
    shortfall          INT          NOT NULL
);

PRINT 'All 9 tables created.';
GO


-- =============================================================================
-- STEP 3 — PRIMARY KEYS
-- =============================================================================

ALTER TABLE dim_products
    ADD CONSTRAINT PK_products PRIMARY KEY (product_id);

ALTER TABLE dim_warehouses
    ADD CONSTRAINT PK_warehouses PRIMARY KEY (warehouse_id);

ALTER TABLE dim_suppliers
    ADD CONSTRAINT PK_suppliers PRIMARY KEY (supplier_id);

ALTER TABLE dim_supplier_products
    ADD CONSTRAINT PK_supplier_products PRIMARY KEY (product_id, supplier_id);

ALTER TABLE fact_sales
    ADD CONSTRAINT PK_sales PRIMARY KEY (sale_id);

ALTER TABLE fact_goods_receipts
    ADD CONSTRAINT PK_goods_receipts PRIMARY KEY (receipt_id);

-- batch_id must be unique to support FK from fact_sale_batch_map
-- and fact_inventory_adjustments
ALTER TABLE fact_goods_receipts
    ADD CONSTRAINT UQ_batch_id UNIQUE (batch_id);

ALTER TABLE fact_sale_batch_map
    ADD CONSTRAINT PK_sale_batch_map PRIMARY KEY (sale_id, batch_id);

ALTER TABLE fact_inventory_adjustments
    ADD CONSTRAINT PK_adjustments PRIMARY KEY (adjustment_id);

ALTER TABLE fact_stockout_events
    ADD CONSTRAINT PK_stockouts PRIMARY KEY (stockout_id);

PRINT 'Primary keys and unique constraints applied.';
GO


-- =============================================================================
-- STEP 4 — FOREIGN KEYS
-- =============================================================================

-- dim_supplier_products
ALTER TABLE dim_supplier_products
    ADD CONSTRAINT FK_sup_prod_product
    FOREIGN KEY (product_id)  REFERENCES dim_products(product_id);

ALTER TABLE dim_supplier_products
    ADD CONSTRAINT FK_sup_prod_supplier
    FOREIGN KEY (supplier_id) REFERENCES dim_suppliers(supplier_id);

-- fact_sales
ALTER TABLE fact_sales
    ADD CONSTRAINT FK_sales_warehouse
    FOREIGN KEY (warehouse_id) REFERENCES dim_warehouses(warehouse_id);

ALTER TABLE fact_sales
    ADD CONSTRAINT FK_sales_product
    FOREIGN KEY (product_id)   REFERENCES dim_products(product_id);

-- fact_goods_receipts
ALTER TABLE fact_goods_receipts
    ADD CONSTRAINT FK_gr_product
    FOREIGN KEY (product_id)   REFERENCES dim_products(product_id);

ALTER TABLE fact_goods_receipts
    ADD CONSTRAINT FK_gr_supplier
    FOREIGN KEY (supplier_id)  REFERENCES dim_suppliers(supplier_id);

ALTER TABLE fact_goods_receipts
    ADD CONSTRAINT FK_gr_warehouse
    FOREIGN KEY (warehouse_id) REFERENCES dim_warehouses(warehouse_id);

-- fact_sale_batch_map
ALTER TABLE fact_sale_batch_map
    ADD CONSTRAINT FK_sbm_sale
    FOREIGN KEY (sale_id)  REFERENCES fact_sales(sale_id);

ALTER TABLE fact_sale_batch_map
    ADD CONSTRAINT FK_sbm_batch
    FOREIGN KEY (batch_id) REFERENCES fact_goods_receipts(batch_id);

-- fact_inventory_adjustments
ALTER TABLE fact_inventory_adjustments
    ADD CONSTRAINT FK_adj_warehouse
    FOREIGN KEY (warehouse_id) REFERENCES dim_warehouses(warehouse_id);

ALTER TABLE fact_inventory_adjustments
    ADD CONSTRAINT FK_adj_product
    FOREIGN KEY (product_id)   REFERENCES dim_products(product_id);

ALTER TABLE fact_inventory_adjustments
    ADD CONSTRAINT FK_adj_batch
    FOREIGN KEY (batch_id)     REFERENCES fact_goods_receipts(batch_id);

-- fact_stockout_events
ALTER TABLE fact_stockout_events
    ADD CONSTRAINT FK_so_warehouse
    FOREIGN KEY (warehouse_id) REFERENCES dim_warehouses(warehouse_id);

ALTER TABLE fact_stockout_events
    ADD CONSTRAINT FK_so_product
    FOREIGN KEY (product_id)   REFERENCES dim_products(product_id);

PRINT 'All foreign keys applied.';
GO


-- =============================================================================
-- STEP 5 — VERIFY STRUCTURE
-- =============================================================================

SELECT
    t.name                          AS table_name,
    COUNT(c.column_id)              AS column_count
FROM sys.tables t
JOIN sys.columns c ON t.object_id = c.object_id
GROUP BY t.name
ORDER BY t.name;

PRINT 'Setup complete. Now run 02_stored_procedures.sql';
GO
