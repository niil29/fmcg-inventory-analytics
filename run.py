# =============================================================================
# run.py
# Single entry point for the full simulation pipeline.
#
# Usage:
#   python run.py
#
# What it does, in order:
#   1. Generates all dimension tables (master_data.py)
#   2. Runs the 365-day simulation (simulation.py)
#   3. Prints a final summary of all output files
# =============================================================================

import os
import time
import pandas as pd

import config

def print_separator():
    print("=" * 60)

def run_step(label, func):
    print_separator()
    print(f"  {label}")
    print_separator()
    start = time.time()
    func()
    elapsed = round(time.time() - start, 1)
    print(f"\n  Completed in {elapsed}s")

# =============================================================================
# IMPORT STEP FUNCTIONS
# =============================================================================

def step_master_data():
    import master_data
    import importlib
    importlib.reload(master_data)   # ensures fresh run even if already imported

    df_products          = master_data.generate_products()
    df_warehouses        = master_data.generate_warehouses()
    df_suppliers         = master_data.generate_suppliers()
    df_supplier_products = master_data.generate_supplier_products(
                               df_products, df_suppliers)

    os.makedirs(config.OUTPUT_DIR, exist_ok=True)
    df_products.to_csv(config.OUTPUT_FILES["products"],          index=False)
    df_warehouses.to_csv(config.OUTPUT_FILES["warehouses"],      index=False)
    df_suppliers.to_csv(config.OUTPUT_FILES["suppliers"],        index=False)
    df_supplier_products.to_csv(config.OUTPUT_FILES["supplier_products"], index=False)

    print(f"  dim_products          → {len(df_products)} rows")
    print(f"  dim_warehouses        → {len(df_warehouses)} rows")
    print(f"  dim_suppliers         → {len(df_suppliers)} rows")
    print(f"  dim_supplier_products → {len(df_supplier_products)} rows")


def step_simulation():
    import simulation
    import importlib
    importlib.reload(simulation)

    results = simulation.run_simulation()
    simulation.save_outputs(*results)


# =============================================================================
# FINAL SUMMARY
# =============================================================================

def print_final_summary():
    print_separator()
    print("  FINAL OUTPUT SUMMARY")
    print_separator()

    all_files = {
        "dim_products":           config.OUTPUT_FILES["products"],
        "dim_warehouses":         config.OUTPUT_FILES["warehouses"],
        "dim_suppliers":          config.OUTPUT_FILES["suppliers"],
        "dim_supplier_products":  config.OUTPUT_FILES["supplier_products"],
        "fact_sales":             config.OUTPUT_FILES["sales"],
        "fact_sale_batch_map":    config.OUTPUT_FILES["sale_batch_map"],
        "fact_goods_receipts":    config.OUTPUT_FILES["goods_receipts"],
        "fact_inventory_adj":     config.OUTPUT_FILES["adjustments"],
        "fact_stockout_events":   config.OUTPUT_FILES["stockouts"],
    }

    total_rows = 0
    for name, path in all_files.items():
        if os.path.exists(path):
            rows = sum(1 for _ in open(path)) - 1   # subtract header
            total_rows += rows
            print(f"  {name:<28} → {rows:>7,} rows")
        else:
            print(f"  {name:<28} → NOT FOUND")

    print_separator()
    print(f"  {'TOTAL ROWS':<28}   {total_rows:>7,}")
    print_separator()
    print(f"\n  All files saved to: {config.OUTPUT_DIR}\n")


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    total_start = time.time()

    print("\n")
    print_separator()
    print("  FMCG SUPPLY CHAIN SIMULATION")
    print_separator()
    print(f"  Simulation period : {config.SIM_START_DATE}  ({config.SIM_DAYS} days)")
    print(f"  Products          : {config.NUM_PRODUCTS}")
    print(f"  Warehouses        : {config.NUM_WAREHOUSES}")
    print(f"  Suppliers         : {config.NUM_SUPPLIERS}")
    print(f"  Output folder     : {config.OUTPUT_DIR}")
    print()

    run_step("STEP 1 of 2 — Generating master data...", step_master_data)
    run_step("STEP 2 of 2 — Running simulation...",     step_simulation)

    print_final_summary()

    total_elapsed = round(time.time() - total_start, 1)
    print(f"  Total run time: {total_elapsed}s\n")
