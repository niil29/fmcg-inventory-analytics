-- Exploratory Data Analysis for FMCG Inventory Database

-- Checking row counts, data quality, and basic aggregations to understand the dataset
-- Row Count Validation Across All Tables

SELECT 'dim_products' AS table_name, COUNT(*) AS row_count FROM dim_products
UNION ALL
SELECT 'dim_supplier_products', COUNT(*)  FROM dim_supplier_products
UNION ALL
SELECT 'dim_suppliers', COUNT(*)  FROM dim_suppliers
UNION ALL
SELECT 'dim_warehouses', COUNT(*)  FROM dim_warehouses
UNION ALL
SELECT 'fact_goods_receipts', COUNT(*)  FROM fact_goods_receipts
UNION ALL
SELECT 'fact_inventory_adjustments', COUNT(*)  FROM fact_inventory_adjustments
UNION ALL
SELECT 'fact_sale_batch_map', COUNT(*)  FROM fact_sale_batch_map
UNION ALL
SELECT 'fact_sales', COUNT(*)  FROM fact_sales
UNION ALL
SELECT 'fact_stockout_events', COUNT(*)  FROM fact_stockout_events

PRINT 'printed row counts for all tables in the FMCG_Inventory database'


--  Sales Date Range and Scope Validation

SELECT MAX(sale_date) AS latest_sale_date,
	   MIN(sale_date) AS earliest_sale_date,
	   COUNT(DISTINCT product_id) AS unique_products_sold,
	   COUNT(DISTINCT warehouse_id) AS unique_warehouses_involved
FROM FACT_SALES


-- Sales Volume and Revenue by Warehouse

SELECT warehouse_id,
	   COUNT(*) AS total_sales_transactions,
	   SUM(quantity_sold) AS total_units_sold,
	   CAST(SUM(quantity_sold * selling_price_per_unit * (1 - discount_percent/100)) AS DECIMAL(10,2)) AS total_revenue,
	   CAST(AVG(selling_price_per_unit) AS DECIMAL(10,2)) AS average_selling_price_per_unit
FROM fact_sales s
GROUP BY warehouse_id
ORDER BY total_revenue DESC


-- Sales Transactions by Product Category

SELECT p.category AS product_category,
	   COUNT(*) AS total_sales_transactions,
	   SUM(quantity_sold) AS total_units_sold,
	   CAST(SUM(quantity_sold * selling_price_per_unit * (1 - discount_percent/100)) AS DECIMAL(10,2)) AS total_revenue,
	   CAST(AVG(discount_percent) AS DECIMAL(5,2)) AS average_discount_percent
FROM fact_sales s
INNER JOIN dim_products p ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY total_revenue DESC


-- Null and Data Quality Check

SELECT *
FROM fact_sales
WHERE quantity_sold <= 0;

SELECT *
FROM fact_goods_receipts
WHERE expiry_date <= receipt_date;

SELECT *
FROM fact_sale_batch_map
WHERE quantity_from_batch <= 0;


--  Orphaned records in fact_sale_batch_map

SELECT *
FROM fact_sale_batch_map sbm
LEFT JOIN fact_sales s ON sbm.sale_id = s.sale_id
WHERE s.sale_id IS NULL;


-- Orphaned batch records

SELECT *
FROM fact_sale_batch_map sbm
LEFT JOIN fact_goods_receipts gr ON sbm.batch_id = gr.batch_id
WHERE gr.batch_id IS NULL;


-- Staging Views
-- Creating a view to enrich sales data with product and warehouse details for easier analysis

CREATE OR ALTER VIEW vw_sales_enriched AS
	SELECT s.sale_id,
	   s.sale_date,
	   s.warehouse_id,
	   s.product_id,
	   s.quantity_sold,
	   s.selling_price_per_unit,
	   s.discount_percent,
	   s.promotion_flag,
	   p.product_name,
	   p.category,
	   p.base_cost,
	   p.base_price,
	   p.shelf_life_days,
	   w.warehouse_name,
	   w.region,
	   w.cold_storage_flag
	FROM fact_sales s
	INNER JOIN dim_products p ON s.product_id = p.product_id
	INNER JOIN dim_warehouses w ON s.warehouse_id = w.warehouse_id
	GO

	PRINT 'Created view vw_sales_enriched to combine sales data with product and warehouse details for enhanced analysis';

	-- Test query to validate the view

SELECT TOP 10 *
FROM vw_sales_enriched;

-- creating a view to enrich goods receipt data with product, warehouse, and supplier details for easier analysis

CREATE OR ALTER VIEW vw_goods_receipts_enriched AS
	SELECT gr.receipt_id,
	   gr.receipt_date,
	   gr.warehouse_id,
	   gr.product_id,
	   gr.quantity_received,
	   gr.purchase_price_per_unit,
	   gr.supplier_id,
	   gr.batch_id,
	   p.product_name,
	   p.category,
	   p.base_cost,
	   p.base_price,
	   p.shelf_life_days,
	   w.warehouse_name,
	   w.region,
	   w.cold_storage_flag,
	   sp.supplier_name,
	   sp.supplier_city,
	   sp.average_lead_time_days,
	   sp.reliability_score
	FROM fact_goods_receipts gr
	INNER JOIN dim_products p ON gr.product_id = p.product_id
	INNER JOIN dim_warehouses w ON gr.warehouse_id = w.warehouse_id
	INNER JOIN dim_suppliers sp ON gr.supplier_id = sp.supplier_id
	GO
	PRINT 'Created view vw_goods_receipts_enriched to combine goods receipt data with product and warehouse details for enhanced analysis';
	
-- Test query to validate the view
SELECT TOP 10 *
FROM vw_goods_receipts_enriched;

-- Creating a view to enrich inventory adjustment data with product and warehouse details for easier analysis 

CREATE OR ALTER VIEW vw_inventory_adjustments_enriched AS
	SELECT ia.adjustment_id,
	   ia.adjustment_date,
	   ia.warehouse_id,
	   ia.product_id,
	   ia.batch_id,
	   ia.adjustment_type,
	   ia.quantity_adjusted,
	   ia.reason_notes,
	   p.product_name,
	   p.category,
	   p.base_cost,
	   p.base_price,
	   p.shelf_life_days,
	   w.warehouse_name,
	   w.region,
	   w.cold_storage_flag
	FROM fact_inventory_adjustments ia
	INNER JOIN dim_products p ON ia.product_id = p.product_id
	INNER JOIN dim_warehouses w ON ia.warehouse_id = w.warehouse_id
	GO
	PRINT 'Created view vw_inventory_adjustments_enriched to combine inventory adjustment data with product and warehouse details for enhanced analysis';
	
-- Test query to validate the view
SELECT TOP 10 *
FROM vw_inventory_adjustments_enriched;


-- Creating a view to enrich stockout event data with product and warehouse details for easier analysis

CREATE OR ALTER VIEW vw_expiry_rate_by_category AS
SELECT
	gr.product_id,
	p.category,
	w.warehouse_id,
	w.warehouse_name,
	w.region,
	gr.receipt_date,
	gr.quantity_received,
	ISNULL(adj.quantity_expired, 0) AS quantity_expired
FROM fact_goods_receipts gr
JOIN dim_products p ON gr.product_id = p.product_id
JOIN dim_warehouses w ON gr.warehouse_id = w.warehouse_id
LEFT JOIN (
	SELECT batch_id, SUM(quantity_adjusted) AS quantity_expired
	FROM fact_inventory_adjustments
	WHERE adjustment_type = 'Expiry'
	GROUP BY batch_id
	) adj ON gr.batch_id = adj.batch_id


SELECT TOP 50 *
FROM vw_expiry_rate_by_category;


-- creating a view to calculate inventory aging and expiry risk for each batch of products in the warehouses, combining data from goods receipts, sales, and inventory adjustments

CREATE OR ALTER VIEW vw_inventory_aging AS
WITH unit_sold AS (
    SELECT batch_id,
           SUM(quantity_from_batch) AS total_units_sold
    FROM fact_sale_batch_map
    GROUP BY batch_id
),
units_written_off AS (
    SELECT batch_id,
           SUM(quantity_adjusted) AS total_units_written_off
    FROM fact_inventory_adjustments
    WHERE adjustment_type = 'Expiry'
    GROUP BY batch_id
)
SELECT 
    gr.batch_id,
    gr.product_id,
    p.category,
    gr.warehouse_id,
    w.warehouse_name,
    w.region,
    gr.receipt_date,
    gr.expiry_date,
    gr.purchase_price_per_unit,
    gr.quantity_received,
    ISNULL(us.total_units_sold, 0) AS total_units_sold,
    ISNULL(wo.total_units_written_off, 0) AS total_units_written_off,
    (gr.quantity_received 
        - ISNULL(us.total_units_sold, 0) 
        - ISNULL(wo.total_units_written_off, 0)) AS current_stock,
    DATEDIFF(DAY, '2024-12-31', gr.expiry_date) AS days_until_expiry,
    CASE 
        WHEN DATEDIFF(DAY, '2024-12-31', gr.expiry_date) <= 2 THEN 'Critical'
        WHEN DATEDIFF(DAY, '2024-12-31', gr.expiry_date) BETWEEN 3 AND 5 THEN 'Near Expiry'
        WHEN DATEDIFF(DAY, '2024-12-31', gr.expiry_date) BETWEEN 6 AND 7 THEN 'Ageing'
        WHEN DATEDIFF(DAY, '2024-12-31', gr.expiry_date) > 7 THEN 'Fresh'
        ELSE 'Expired'
    END AS age_band
FROM fact_goods_receipts gr
JOIN dim_products p ON gr.product_id = p.product_id
JOIN dim_warehouses w ON gr.warehouse_id = w.warehouse_id
LEFT JOIN unit_sold us ON gr.batch_id = us.batch_id
LEFT JOIN units_written_off wo ON gr.batch_id = wo.batch_id
WHERE gr.expiry_date > '2024-12-31'
AND (gr.quantity_received 
        - ISNULL(us.total_units_sold, 0) 
        - ISNULL(wo.total_units_written_off, 0)) > 0;