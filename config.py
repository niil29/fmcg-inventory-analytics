# =============================================================================
# config.py
# Central configuration for the perishable goods supply chain simulation.
# All modules import from here — do not hardcode values elsewhere.
# =============================================================================

import os

# -----------------------------------------------------------------------------
# REPRODUCIBILITY
# -----------------------------------------------------------------------------
RANDOM_SEED = 42          # Fixed seed — all runs produce the same dataset.

# -----------------------------------------------------------------------------
# SIMULATION TIMELINE
# -----------------------------------------------------------------------------
SIM_START_DATE = "2024-01-01"   # ISO format. Day 1 of the simulation.
SIM_DAYS       = 365            # Total days to simulate.

# -----------------------------------------------------------------------------
# MASTER DATA DIMENSIONS
# -----------------------------------------------------------------------------
NUM_PRODUCTS   = 25     # P001 – P025
NUM_WAREHOUSES = 5      # W001 – W005
NUM_SUPPLIERS  = 12     # SUP001 – SUP012

REGIONS = ["North", "South", "East", "West", "Central"]

PRODUCT_CATEGORIES = ["Milk", "Fresh Juice", "Yogurt", "Bread", "Ready Meals"]

# -----------------------------------------------------------------------------
# DEMAND PARAMETERS
# -----------------------------------------------------------------------------
DEMAND_MIN = 15     # Minimum base daily demand (units) per product per warehouse
DEMAND_MAX = 80     # Maximum base daily demand (units) per product per warehouse

DEMAND_NOISE_PCT   = 0.20   # +-20% random noise applied each day to base demand
WEEKEND_MULTIPLIER = 1.55   # Saturday & Sunday demand boost

# Region-level demand multipliers (applied on top of base demand)
REGION_DEMAND_MULTIPLIERS = {
    "North":   1.00,
    "South":   1.10,
    "East":    0.90,
    "West":    1.05,
    "Central": 1.20,
}

# -----------------------------------------------------------------------------
# PROMOTION PARAMETERS
# -----------------------------------------------------------------------------
# Promotions are fully random and unpredictable — no fixed frequency per year.
# Each day, each product independently rolls against PROMO_DAILY_PROBABILITY.
# If triggered, the promotion runs for a random duration within the range below.
# This produces irregular promotion clusters — some products get many promos,
# some very few, purely by chance.
PROMO_DAILY_PROBABILITY = 0.04     # Per-product per-day chance a new promo starts
PROMO_DURATION_MIN      = 3        # Promotion lasts 3-14 days (random each time)
PROMO_DURATION_MAX      = 14
PROMO_BOOST_MIN         = 1.40     # Minimum demand multiplier during promotion
PROMO_BOOST_MAX         = 1.80     # Maximum demand multiplier during promotion
PROMO_DISCOUNT_MIN      = 0.05     # Minimum discount % recorded in sales table
PROMO_DISCOUNT_MAX      = 0.20     # Maximum discount % recorded in sales table

# -----------------------------------------------------------------------------
# INVENTORY & REORDER PARAMETERS
# -----------------------------------------------------------------------------
# Reorder triggers when: coverage_days < (supplier_lead_time + REORDER_BUFFER_DAYS)
# Evaluated per product per warehouse using the assigned supplier's lead time.
REORDER_BUFFER_DAYS = 1     # Safety buffer on top of lead time for reorder trigger

BATCH_COVER_MIN     = 5     # New batch quantity = 5-7 days of average daily demand
BATCH_COVER_MAX     = 7

# Initial inventory seeding (before day 1)
INITIAL_BATCHES_MIN = 1     # Each product/warehouse gets 1-2 batches pre-loaded
INITIAL_BATCHES_MAX = 2

# -----------------------------------------------------------------------------
# SUPPLIER PARAMETERS
# -----------------------------------------------------------------------------
SUPPLIER_RELIABILITY_MIN = 0.92     # Probability a delivery arrives on scheduled date
SUPPLIER_RELIABILITY_MAX = 0.99

LEAD_TIME_MIN = 1   # Days between order and warehouse receipt
LEAD_TIME_MAX = 3

# Each product is assigned 2-3 possible suppliers (one primary, rest as backup)
SUPPLIERS_PER_PRODUCT_MIN = 2
SUPPLIERS_PER_PRODUCT_MAX = 3

# -----------------------------------------------------------------------------
# COST & PRICE PARAMETERS
# -----------------------------------------------------------------------------
COST_VOLATILITY_PCT = 0.08      # +-8% random cost variation per batch received

# Optional inflation / dip quarters for realism
INFLATION_QUARTER   = 3         # Q3 gets a cost uplift
INFLATION_BUMP_PCT  = 0.05      # +5% on top of base cost during inflation quarter
DIP_QUARTER         = 1         # Q1 gets a cost dip
DIP_PCT             = 0.04      # -4% on base cost during dip quarter

# Selling price variation around base_price
PRICE_NOISE_PCT     = 0.05      # +-5% retail price variation per transaction

# -----------------------------------------------------------------------------
# SHELF LIFE PARAMETERS
# -----------------------------------------------------------------------------
# Category-level shelf life with realistic variation within the 5-10 day range.
SHELF_LIFE_DAYS = {
    "Milk":        7,
    "Fresh Juice": 9,
    "Yogurt":      10,
    "Bread":       5,
    "Ready Meals": 6,
}

# -----------------------------------------------------------------------------
# EXPIRY & SHRINKAGE PARAMETERS
# -----------------------------------------------------------------------------
SHRINKAGE_RATE_MIN   = 0.01   # 1% minimum shrinkage applied to affected batches
SHRINKAGE_RATE_MAX   = 0.03   # 3% maximum
SHRINKAGE_DAILY_PROB = 0.03   # 3% chance per day that a shrinkage event occurs
                               # per product per warehouse

# -----------------------------------------------------------------------------
# EXPECTED OUTPUT SCALE (reference only — not used in logic)
# -----------------------------------------------------------------------------
# Sales:                 ~60k – 90k rows
# Goods receipts:        ~6k  –  9k rows
# Inventory adjustments: ~2k  –  4k rows

# -----------------------------------------------------------------------------
# OUTPUT PATHS
# -----------------------------------------------------------------------------
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")

OUTPUT_FILES = {
    "products":          os.path.join(OUTPUT_DIR, "dim_products.csv"),
    "warehouses":        os.path.join(OUTPUT_DIR, "dim_warehouses.csv"),
    "suppliers":         os.path.join(OUTPUT_DIR, "dim_suppliers.csv"),
    "supplier_products": os.path.join(OUTPUT_DIR, "dim_supplier_products.csv"),
    "sales":             os.path.join(OUTPUT_DIR, "fact_sales.csv"),
    "sale_batch_map":    os.path.join(OUTPUT_DIR, "fact_sale_batch_map.csv"),
    "goods_receipts":    os.path.join(OUTPUT_DIR, "fact_goods_receipts.csv"),
    "adjustments":       os.path.join(OUTPUT_DIR, "fact_inventory_adjustments.csv"),
    "stockouts":         os.path.join(OUTPUT_DIR, "fact_stockout_events.csv"),
}
