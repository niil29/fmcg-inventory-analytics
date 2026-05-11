-- Expiry Loss Analysis

-- Total expiry loss by category 

SELECT category,
	   COUNT(*) AS total_expiry_events,
	   SUM(quantity_adjusted) AS total_unit_lost_to_expiry,
	   SUM(quantity_adjusted * base_cost) AS total_cost_lost_to_expiry
FROM vw_inventory_adjustments_enriched
WHERE adjustment_type =  'Expiry'
GROUP BY category
ORDER BY total_cost_lost_to_expiry DESC;


-- Expiry Loss Rate by Category

WITH receipts AS (
	SELECT category,
		   SUM(quantity_received) AS total_units_received
	FROM vw_goods_receipts_enriched
	GROUP BY category
),
expiry AS (
	SELECT category,
		   CAST(SUM(quantity_adjusted) AS FLOAT) AS total_units_lost_to_expiry
	FROM vw_inventory_adjustments_enriched
	WHERE adjustment_type = 'Expiry'
	GROUP BY category
)
SELECT r.category,
	   r.total_units_received,
	   e.total_units_lost_to_expiry,
	   CASE 
			WHEN r.total_units_received > 0 THEN CAST(e.total_units_lost_to_expiry *100 / r.total_units_received AS DECIMAL(10,2))
			ELSE 0
	   END AS expiry_loss_rate_percent
FROM receipts r
JOIN expiry e ON r.category = e.category
ORDER BY expiry_loss_rate_percent DESC;


-- Expiry Loss by Warehouse

SELECT warehouse_name,
	   region,
	   COUNT(*) AS total_expiry_events,
	   SUM(quantity_adjusted) AS total_unit_lost_to_expiry,
	   SUM(quantity_adjusted * base_cost) AS total_cost_lost_to_expiry,
	   CAST(AVG(quantity_adjusted * base_cost) AS DECIMAL(10,2)) AS avg_cost_lost_per_expiry_event
FROM vw_inventory_adjustments_enriched
WHERE adjustment_type = 'Expiry'
GROUP BY warehouse_name, region
ORDER BY total_cost_lost_to_expiry DESC;




-- Stockout Analysis

WITH stockout AS (
	SELECT so.warehouse_id,
		   p.category,
		   CAST(COUNT(*) AS INT) AS total_stockout_events,
		   CAST(SUM(shortfall) AS FLOAT) AS total_units_short
	FROM fact_stockout_events so
	JOIN dim_products p ON so.product_id = p.product_id
	GROUP BY warehouse_id, category
),
sales AS (
	SELECT s.warehouse_id,
		   p.category,
		   CAST(COUNT(*) AS INT) AS total_sales_events
	FROM fact_sales s
	JOIN dim_products p ON s.product_id = p.product_id
	GROUP BY warehouse_id, category
)

SELECT w.warehouse_name,
	   so.category,
	   w.region,
	   SUM(total_stockout_events) AS total_stockout_events,
	   SUM(total_units_short) AS total_units_short,
	   CAST(SUM(so.total_stockout_events) * 100.0 / SUM(s.total_sales_events) AS DECIMAL(10,2)) AS stockout_rate_percent
FROM stockout so
JOIN sales s on so.warehouse_id = s.warehouse_id AND so.category = s.category
JOIN dim_warehouses w ON so.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_name, so.category, w.region
ORDER BY stockout_rate_percent DESC;


-- Supplier Performance

-- Supplier Delivery Performance

SELECT supplier_name, 
	   supplier_city,
	   COUNT(DISTINCT batch_id) AS total_batches_received,
	   SUM(quantity_received) AS total_units_received,
	   CAST(AVG(purchase_price_per_unit) AS DECIMAL(10,2)) AS avg_cost_per_unit,
	   reliability_score
FROM vw_goods_receipts_enriched
GROUP BY supplier_name, supplier_city, reliability_score
ORDER BY total_batches_received DESC;

--  Supplier Lead Time and Cost Volatility Analysis

SELECT supplier_name,
	   average_lead_time_days,
	   reliability_score,
	   CAST(AVG(purchase_price_per_unit) AS DECIMAL(10,2)) AS avg_cost_per_unit,
	   CAST(MAX(purchase_price_per_unit) AS DECIMAL(10,2)) AS max_cost_per_unit,
	   CAST(MIN(purchase_price_per_unit) AS DECIMAL(10,2)) AS min_cost_per_unit,
	   CAST((MAX(purchase_price_per_unit) - MIN(purchase_price_per_unit)) AS DECIMAL(10,2)) AS price_range
FROM vw_goods_receipts_enriched
GROUP BY supplier_name, average_lead_time_days, reliability_score
ORDER BY reliability_score ASC
;


-- Inventory Aging

--  Batch Age Profile at End of Simulation

WITH unit_sold AS (
	SELECT batch_id,
			SUM(quantity_from_batch) AS total_units_sold
	FROM fact_sale_batch_map
	GROUP BY batch_id
),
units_written_off AS (
	SELECT batch_id,
			SUM(quantity_adjusted) AS total_units_written_off
	FROM vw_inventory_adjustments_enriched
	WHERE adjustment_type = 'Expiry'
	GROUP BY batch_id
),
active_batches AS (
	SELECT gr.batch_id,
			gr.product_id,
			gr.warehouse_id,
			gr.receipt_date,
			gr.expiry_date,
			gr.quantity_received,
			gr.purchase_price_per_unit,
			ISNULL(us.total_units_sold, 0) AS total_units_sold,
			ISNULL(wo.total_units_written_off, 0) AS total_units_written_off,
			(gr.quantity_received - ISNULL(us.total_units_sold, 0) - ISNULL(wo.total_units_written_off, 0)) AS current_stock
	FROM fact_goods_receipts gr
	LEFT JOIN unit_sold us ON gr.batch_id = us.batch_id
	LEFT JOIN units_written_off wo ON gr.batch_id = wo.batch_id
	WHERE expiry_date > '2024-12-31' 
	AND (gr.quantity_received - ISNULL(us.total_units_sold, 0) - ISNULL(wo.total_units_written_off, 0)) > 0
), 
batch_details AS (
	SELECT ab.batch_id,
			warehouse_name,
			region,
			current_stock,
			ab.purchase_price_per_unit,
			CASE WHEN DATEDIFF(DAY, '2024-12-31', expiry_date) <= 2 THEN 'Critical'
				WHEN DATEDIFF(DAY, '2024-12-31', expiry_date) BETWEEN 3 AND 5 THEN 'Near Expiry'
				WHEN DATEDIFF(DAY, '2024-12-31', expiry_date) BETWEEN 6 AND 7 THEN 'Ageing'
				WHEN DATEDIFF(DAY, '2024-12-31', expiry_date) > 7 THEN 'Fresh'
				ELSE 'Expired' END AS age_category
	FROM active_batches ab
	JOIN dim_warehouses w ON ab.warehouse_id = w.warehouse_id
) 

SELECT warehouse_name,
	   region,
	   age_category,
	   COUNT(*) AS total_batches,
	   SUM(current_stock) AS total_units_at_risk,
	   CAST(SUM(current_stock * purchase_price_per_unit) AS DECIMAL(10,2)) AS estimated_stock_value
FROM batch_details
GROUP BY warehouse_name, region, age_category
ORDER BY warehouse_name,
		 CASE WHEN age_category = 'Critical' THEN 1
			  WHEN age_category = 'Near Expiry' THEN 2
			  WHEN age_category = 'Ageing' THEN 3
			  WHEN age_category = 'Fresh' THEN 4
		 END

-- Gross Margin Analysis

-- Gross Margin Analysis by Category and Month

SELECT MONTH(sale_date) AS sale_month,
	   category,
	   CAST(SUM(quantity_sold * selling_price_per_unit) AS DECIMAL(10,2)) AS total_revenue,
	   CAST(SUM(sm.quantity_from_batch * unit_cost_at_sale) AS DECIMAL(10,2)) AS total_cost,
	   CAST((SUM(quantity_sold * selling_price_per_unit) - SUM(sm.quantity_from_batch * unit_cost_at_sale)) AS DECIMAL(10,2)) AS gross_margin,
	   CAST((SUM(quantity_sold * selling_price_per_unit) - SUM(sm.quantity_from_batch * unit_cost_at_sale)) * 100.0 
		/ NULLIF(SUM(quantity_sold * selling_price_per_unit), 0) AS DECIMAL(10,2)) AS gross_margin_percent
FROM vw_sales_enriched se
JOIN fact_sale_batch_map sm ON se.sale_id = sm.sale_id
GROUP BY MONTH(sale_date), category
ORDER BY category, MONTH(sale_date);

-- Warehouse Performance

-- Warehouse Performance Summary

WITH sales_summary AS (
	SELECT warehouse_id,
		   warehouse_name, 
		   region,
		   CAST(SUM(quantity_sold * selling_price_per_unit) AS DECIMAL(10,2)) AS total_revenue
	FROM vw_sales_enriched
	GROUP BY warehouse_id, warehouse_name, region
), 
expiry_summary AS (
	SELECT warehouse_id,
		   warehouse_name, 
		   CAST(SUM(quantity_adjusted * base_cost) AS DECIMAL(10,2)) AS total_expiry_loss	
	FROM vw_inventory_adjustments_enriched
	WHERE adjustment_type = 'Expiry'
	GROUP BY warehouse_id, warehouse_name
),
stockout_summary AS (
	SELECT warehouse_id, 
		   COUNT(*) AS total_stockout_events
	FROM fact_stockout_events
	GROUP BY warehouse_id
)
SELECT ss.warehouse_id,
	   ss.warehouse_name,
	   region,
	   total_revenue,
	   total_expiry_loss,
	   total_stockout_events,
	   CAST(total_expiry_loss * 100.0 / NULLIF(total_revenue, 0) AS DECIMAL(10,2)) AS expiry_loss_percent_of_revenue
FROM sales_summary ss
JOIN expiry_summary es ON ss.warehouse_id = es.warehouse_id
JOIN stockout_summary ss2 ON ss.warehouse_id = ss2.warehouse_id
ORDER BY total_revenue DESC;


-- Monthly Revenue and Cumulative Expiry Loss by Category

WITH monthly_revenue AS (
	SELECT MONTH(sale_date) AS sale_month,
		   category AS category,
		   CAST(SUM(quantity_sold * selling_price_per_unit) AS DECIMAL(10,2)) AS monthly_revenue
	FROM vw_sales_enriched
	GROUP BY MONTH(sale_date),category
),
monthly_expiry_loss AS (
	SELECT MONTH(adjustment_date) AS adjustment_month,
		   category,
		   CAST(SUM(quantity_adjusted * base_cost) AS DECIMAL(10,2)) AS monthly_expiry_loss
	FROM vw_inventory_adjustments_enriched
	WHERE adjustment_type = 'Expiry'
	GROUP BY MONTH(adjustment_date), category
)
SELECT mr.sale_month,
	   mr.category,
	   mr.monthly_revenue,
	   SUM(mr.monthly_revenue) OVER (PARTITION BY mr.category ORDER BY mr.sale_month) AS cumulative_revenue,
	   mel.monthly_expiry_loss,
	   SUM(mel.monthly_expiry_loss) OVER (PARTITION BY mel.category ORDER BY mel.adjustment_month) AS cumulative_expiry_loss
FROM monthly_revenue mr
JOIN monthly_expiry_loss mel 
	ON mr.sale_month = mel.adjustment_month AND mr.category = mel.category
ORDER BY mr.category, mr.sale_month;

-- Warehouse Performance Rankin

WITH sales_summary AS (
	SELECT warehouse_id,
		   warehouse_name, 
		   region,
		   CAST(SUM(quantity_sold * selling_price_per_unit) AS DECIMAL(10,2)) AS total_revenue
	FROM vw_sales_enriched
	GROUP BY warehouse_id, warehouse_name, region
), 
expiry_summary AS (
	SELECT warehouse_id,
		   warehouse_name, 
		   CAST(SUM(quantity_adjusted * base_cost) AS DECIMAL(10,2)) AS total_expiry_loss	
	FROM vw_inventory_adjustments_enriched
	WHERE adjustment_type = 'Expiry'
	GROUP BY warehouse_id, warehouse_name
),
stockout_summary AS (
	SELECT warehouse_id, 
		   COUNT(*) AS total_stockout_events
	FROM fact_stockout_events
	GROUP BY warehouse_id
)
SELECT ss.warehouse_id,
	   ss.warehouse_name,
	   region,
	   total_revenue,
	   DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
	   total_expiry_loss,
	   DENSE_RANK() OVER (ORDER BY  CAST(total_expiry_loss * 100.0 / NULLIF(total_revenue, 0) AS DECIMAL(10,2)) ASC) AS expiry_loss_percent_rank,
	   total_stockout_events,
	   DENSE_RANK() OVER (ORDER BY total_stockout_events ASC) AS stockout_rank,
	   CAST(total_expiry_loss * 100.0 / NULLIF(total_revenue, 0) AS DECIMAL(10,2)) AS expiry_loss_percent_of_revenue
FROM sales_summary ss
JOIN expiry_summary es ON ss.warehouse_id = es.warehouse_id
JOIN stockout_summary ss2 ON ss.warehouse_id = ss2.warehouse_id
ORDER BY revenue_rank ASC;
