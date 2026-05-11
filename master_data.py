# =============================================================================
# master_data.py
# Generates all dimension tables:
#   - dim_products.csv
#   - dim_warehouses.csv
#   - dim_suppliers.csv
#   - dim_supplier_products.csv
#
# Run this first before simulation.py.
# Output goes to the /output folder defined in config.py.
# =============================================================================

import os
import random
import pandas as pd
from datetime import date, timedelta

import config

# Seed once at the top — all random calls below are reproducible
random.seed(config.RANDOM_SEED)

# Create output folder if it doesn't exist
os.makedirs(config.OUTPUT_DIR, exist_ok=True)


# =============================================================================
# 1. DIM_PRODUCTS
# =============================================================================

# Realistic product names per category
PRODUCT_NAMES = {
    "Milk": [
        "Whole Milk 1L", "Skimmed Milk 1L", "Semi-Skimmed Milk 2L",
        "Organic Whole Milk 1L", "Full Cream Milk 500ml"
    ],
    "Fresh Juice": [
        "Orange Juice 1L", "Apple Juice 1L", "Mango Juice 500ml",
        "Mixed Berry Juice 750ml", "Pineapple Juice 1L"
    ],
    "Yogurt": [
        "Plain Yogurt 500g", "Strawberry Yogurt 150g", "Greek Yogurt 400g",
        "Mango Yogurt 150g", "Low Fat Yogurt 500g"
    ],
    "Bread": [
        "White Sliced Bread 400g", "Wholemeal Bread 400g", "Multigrain Bread 500g",
        "Sourdough Loaf 500g", "Brown Bread 400g"
    ],
    "Ready Meals": [
        "Chicken Tikka Masala 400g", "Pasta Bolognese 380g",
        "Vegetable Curry 350g", "Mac and Cheese 300g", "Beef Stew 400g"
    ],
}

# Base cost ranges per category (min, max) in currency units
COST_RANGES = {
    "Milk":        (0.60,  1.20),
    "Fresh Juice": (0.80,  1.80),
    "Yogurt":      (0.50,  1.50),
    "Bread":       (0.40,  1.00),
    "Ready Meals": (1.80,  3.50),
}

# Margin multiplier to get base_price from base_cost (30–60% markup)
MARGIN_RANGE = (1.30, 1.60)

SIM_START = date.fromisoformat(config.SIM_START_DATE)

def generate_products():
    rows = []
    product_num = 1

    # Distribute 25 products across 5 categories — 5 products each
    for category, names in PRODUCT_NAMES.items():
        shelf_life = config.SHELF_LIFE_DAYS[category]
        cost_min, cost_max = COST_RANGES[category]

        for name in names:
            product_id = f"P{product_num:03d}"

            base_cost  = round(random.uniform(cost_min, cost_max), 2)
            margin     = random.uniform(*MARGIN_RANGE)
            base_price = round(base_cost * margin, 2)

            # Launch date: most products launched before sim start,
            # a couple launched during the year (late entrants)
            if product_num <= 22:
                days_before = random.randint(30, 730)
                launch_date = SIM_START - timedelta(days=days_before)
            else:
                # Products 23–25 launch partway through the sim year
                days_into_sim = random.randint(30, 300)
                launch_date = SIM_START + timedelta(days=days_into_sim)

            # Status: products 24 and 25 are Inactive (discontinued/not yet live)
            status = "Inactive" if product_num >= 24 else "Active"

            # Unit size pulled from the product name for realism
            unit_size = name.split()[-1]   # e.g. "1L", "400g", "500ml"

            rows.append({
                "product_id":    product_id,
                "product_name":  name,
                "category":      category,
                "unit_size":     unit_size,
                "base_cost":     base_cost,
                "base_price":    base_price,
                "shelf_life_days": shelf_life,
                "launch_date":   launch_date.isoformat(),
                "status":        status,
            })

            product_num += 1

    return pd.DataFrame(rows)


# =============================================================================
# 2. DIM_WAREHOUSES
# =============================================================================

WAREHOUSE_NAMES = [
    "Northern Distribution Centre",
    "Southern Hub",
    "Eastern Fulfilment Centre",
    "Western Depot",
    "Central Warehouse",
]

WAREHOUSE_CITIES = ["Manchester", "Bristol", "Norwich", "Cardiff", "Birmingham"]

# Storage capacities (units) — different sizes for each warehouse
WAREHOUSE_CAPACITIES = [8000, 12000, 6000, 7500, 15000]

# Cold storage — needed for Milk, Juice, Yogurt, Ready Meals
COLD_STORAGE = [1, 1, 0, 1, 1]   # 1 = yes, 0 = no


def generate_warehouses():
    rows = []
    for i, region in enumerate(config.REGIONS):
        rows.append({
            "warehouse_id":           f"W{i+1:03d}",
            "warehouse_name":         WAREHOUSE_NAMES[i],
            "city":                   WAREHOUSE_CITIES[i],
            "region":                 region,
            "storage_capacity_units": WAREHOUSE_CAPACITIES[i],
            "cold_storage_flag":      COLD_STORAGE[i],
        })
    return pd.DataFrame(rows)


# =============================================================================
# 3. DIM_SUPPLIERS
# =============================================================================

SUPPLIER_NAMES = [
    "FreshFlow Logistics",
    "PrimePack Distributors",
    "Greenfield Supply Co.",
    "NorthStar Foods Ltd",
    "SunRise FMCG Supplies",
    "Rapid Refresh Ltd",
    "Heritage Food Distributors",
    "Metro Supply Chain",
    "Agri-Direct Ltd",
    "PeakFresh Wholesale",
    "Coastal Provisions Ltd",
    "Inland Food Services",
]

SUPPLIER_CITIES = [
    "London", "Birmingham", "Manchester", "Leeds", "Glasgow",
    "Liverpool", "Bristol", "Sheffield", "Edinburgh", "Nottingham",
    "Cardiff", "Leicester",
]


def generate_suppliers():
    rows = []
    for i in range(config.NUM_SUPPLIERS):
        supplier_id = f"SUP{i+1:03d}"

        lead_time   = random.randint(config.LEAD_TIME_MIN, config.LEAD_TIME_MAX)
        reliability = round(
            random.uniform(config.SUPPLIER_RELIABILITY_MIN,
                           config.SUPPLIER_RELIABILITY_MAX), 2
        )

        # Contract start: 1–5 years before simulation start
        days_before = random.randint(365, 365 * 5)
        contract_start = SIM_START - timedelta(days=days_before)

        rows.append({
            "supplier_id":            supplier_id,
            "supplier_name":          SUPPLIER_NAMES[i],
            "supplier_city":          SUPPLIER_CITIES[i],
            "average_lead_time_days": lead_time,
            "reliability_score":      reliability,
            "contract_start_date":    contract_start.isoformat(),
        })

    return pd.DataFrame(rows)


# =============================================================================
# 4. DIM_SUPPLIER_PRODUCTS
# =============================================================================
# Each product is assigned 2–3 suppliers.
# The first assigned supplier is the PRIMARY supplier.
# Others are SECONDARY (backup/alternate).
# This table is the reference the simulation uses when placing reorders.

def generate_supplier_products(df_products, df_suppliers):
    rows = []
    supplier_ids = df_suppliers["supplier_id"].tolist()

    for _, product in df_products.iterrows():
        num_suppliers = random.randint(
            config.SUPPLIERS_PER_PRODUCT_MIN,
            config.SUPPLIERS_PER_PRODUCT_MAX
        )

        # Pick suppliers without replacement for this product
        assigned = random.sample(supplier_ids, num_suppliers)

        for rank, supplier_id in enumerate(assigned):
            rows.append({
                "product_id":   product["product_id"],
                "supplier_id":  supplier_id,
                "is_primary":   1 if rank == 0 else 0,
            })

    return pd.DataFrame(rows)


# =============================================================================
# MAIN — generate, print summary, save CSVs
# =============================================================================

if __name__ == "__main__":

    print("Generating master data...\n")

    df_products         = generate_products()
    df_warehouses       = generate_warehouses()
    df_suppliers        = generate_suppliers()
    df_supplier_products = generate_supplier_products(df_products, df_suppliers)

    # ── Save to CSV ──────────────────────────────────────────────────────────
    df_products.to_csv(config.OUTPUT_FILES["products"], index=False)
    df_warehouses.to_csv(config.OUTPUT_FILES["warehouses"], index=False)
    df_suppliers.to_csv(config.OUTPUT_FILES["suppliers"], index=False)
    df_supplier_products.to_csv(config.OUTPUT_FILES["supplier_products"], index=False)

    # ── Summary ──────────────────────────────────────────────────────────────
    print(f"dim_products         → {len(df_products)} rows")
    print(f"dim_warehouses       → {len(df_warehouses)} rows")
    print(f"dim_suppliers        → {len(df_suppliers)} rows")
    print(f"dim_supplier_products→ {len(df_supplier_products)} rows")
    print(f"\nFiles saved to: {config.OUTPUT_DIR}")

    # ── Quick data preview ───────────────────────────────────────────────────
    print("\n── Products sample ──────────────────────────────────────────────")
    print(df_products[["product_id","product_name","category",
                        "base_cost","base_price","shelf_life_days","status"]].to_string(index=False))

    print("\n── Warehouses ───────────────────────────────────────────────────")
    print(df_warehouses.to_string(index=False))

    print("\n── Suppliers ────────────────────────────────────────────────────")
    print(df_suppliers.to_string(index=False))

    print("\n── Supplier-Product links (first 15 rows) ───────────────────────")
    print(df_supplier_products.head(15).to_string(index=False))
