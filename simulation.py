# =============================================================================
# simulation.py
# Runs the 365-day supply chain simulation.
#
# Produces:
#   fact_goods_receipts.csv
#   fact_sales.csv
#   fact_sale_batch_map.csv
#   fact_inventory_adjustments.csv
#   fact_stockout_events.csv
#
# Requires:
#   config.py and master_data.py outputs must exist first.
#   Run master_data.py before this script.
# =============================================================================

import os
import random
import pandas as pd
from datetime import date, timedelta
from collections import defaultdict

import config

random.seed(config.RANDOM_SEED)

SIM_START = date.fromisoformat(config.SIM_START_DATE)


# =============================================================================
# LOAD MASTER DATA
# =============================================================================

def load_master_data():
    df_products  = pd.read_csv(config.OUTPUT_FILES["products"])
    df_warehouses = pd.read_csv(config.OUTPUT_FILES["warehouses"])
    df_suppliers  = pd.read_csv(config.OUTPUT_FILES["suppliers"])
    df_sup_prod   = pd.read_csv(config.OUTPUT_FILES["supplier_products"])

    # Only simulate Active products
    df_products = df_products[df_products["status"] == "Active"].copy()

    # Filter out late-launch products not yet live on sim start
    # (they'll be added dynamically when their launch_date is reached)
    df_products["launch_date"] = pd.to_datetime(df_products["launch_date"]).dt.date

    # Supplier lookup: supplier_id -> row dict
    suppliers = df_suppliers.set_index("supplier_id").to_dict("index")

    # Product-supplier map: product_id -> list of {supplier_id, is_primary}
    sup_prod_map = defaultdict(list)
    for _, row in df_sup_prod.iterrows():
        sup_prod_map[row["product_id"]].append({
            "supplier_id": row["supplier_id"],
            "is_primary":  row["is_primary"],
        })

    # Warehouse lookup: warehouse_id -> row dict
    warehouses = df_warehouses.set_index("warehouse_id").to_dict("index")

    return df_products, warehouses, suppliers, sup_prod_map


# =============================================================================
# INVENTORY STATE
# =============================================================================
# Structure:
#   inventory[warehouse_id][product_id] = list of batch dicts
#
# Each batch dict:
#   {
#     batch_id, supplier_id, quantity_remaining,
#     receipt_date, expiry_date, unit_cost
#   }

def make_inventory():
    return defaultdict(lambda: defaultdict(list))


# =============================================================================
# ID COUNTERS
# =============================================================================

class Counter:
    def __init__(self, prefix, start=1):
        self.prefix = prefix
        self.n = start

    def next(self):
        val = f"{self.prefix}{self.n:06d}"
        self.n += 1
        return val


# =============================================================================
# DEMAND CALCULATION
# =============================================================================

def get_base_demand(product_id, base_demand_map):
    return base_demand_map[product_id]


def calc_daily_demand(base_demand, today, region, promo_active, promo_boost):
    demand = base_demand

    # Weekend multiplier
    if today.weekday() >= 5:   # 5=Saturday, 6=Sunday
        demand *= config.WEEKEND_MULTIPLIER

    # Region multiplier
    demand *= config.REGION_DEMAND_MULTIPLIERS.get(region, 1.0)

    # Promotion boost
    if promo_active:
        demand *= promo_boost

    # Random noise ±20%
    noise = random.uniform(1 - config.DEMAND_NOISE_PCT,
                           1 + config.DEMAND_NOISE_PCT)
    demand *= noise

    return max(1, int(round(demand)))


# =============================================================================
# PROMOTION STATE
# =============================================================================
# promo_state[product_id] = {
#     "active": bool,
#     "days_remaining": int,
#     "boost": float,
#     "discount": float
# }

def init_promo_state(product_ids):
    return {pid: {"active": False, "days_remaining": 0,
                  "boost": 1.0, "discount": 0.0}
            for pid in product_ids}


def update_promo_state(promo_state, product_id):
    state = promo_state[product_id]

    if state["active"]:
        state["days_remaining"] -= 1
        if state["days_remaining"] <= 0:
            state["active"]         = False
            state["days_remaining"] = 0
            state["boost"]          = 1.0
            state["discount"]       = 0.0
    else:
        # Roll for new promotion
        if random.random() < config.PROMO_DAILY_PROBABILITY:
            duration = random.randint(config.PROMO_DURATION_MIN,
                                      config.PROMO_DURATION_MAX)
            state["active"]         = True
            state["days_remaining"] = duration
            state["boost"]          = random.uniform(config.PROMO_BOOST_MIN,
                                                     config.PROMO_BOOST_MAX)
            state["discount"]       = round(
                random.uniform(config.PROMO_DISCOUNT_MIN,
                               config.PROMO_DISCOUNT_MAX), 2)

    return state


# =============================================================================
# COST WITH VOLATILITY
# =============================================================================

def calc_purchase_cost(base_cost, today):
    quarter = (today.month - 1) // 3 + 1

    cost = base_cost

    # Quarterly inflation / dip
    if quarter == config.INFLATION_QUARTER:
        cost *= (1 + config.INFLATION_BUMP_PCT)
    elif quarter == config.DIP_QUARTER:
        cost *= (1 - config.DIP_PCT)

    # Batch-level random volatility ±8%
    volatility = random.uniform(1 - config.COST_VOLATILITY_PCT,
                                1 + config.COST_VOLATILITY_PCT)
    cost *= volatility

    return round(cost, 4)


# =============================================================================
# REORDER / DELIVERY HELPERS
# =============================================================================

def get_primary_supplier(product_id, sup_prod_map):
    for entry in sup_prod_map[product_id]:
        if entry["is_primary"] == 1:
            return entry["supplier_id"]
    # Fallback: return first available
    return sup_prod_map[product_id][0]["supplier_id"]


def get_total_stock(inventory, warehouse_id, product_id):
    return sum(b["quantity_remaining"]
               for b in inventory[warehouse_id][product_id])


def get_coverage_days(inventory, warehouse_id, product_id, base_demand):
    total = get_total_stock(inventory, warehouse_id, product_id)
    if base_demand == 0:
        return 999
    return total / base_demand


def should_reorder(coverage_days, lead_time):
    return coverage_days < (lead_time + config.REORDER_BUFFER_DAYS)


def create_delivery(batch_ctr, product, warehouse_id, supplier_id,
                    suppliers, base_demand, today):
    supplier    = suppliers[supplier_id]
    lead_time   = supplier["average_lead_time_days"]
    reliability = supplier["reliability_score"]

    # Reliability check — delay if fails
    if random.random() > reliability:
        delay = random.randint(1, 2)
    else:
        delay = 0

    expected_date = today + timedelta(days=lead_time + delay)

    batch_qty  = int(round(base_demand *
                           random.uniform(config.BATCH_COVER_MIN,
                                          config.BATCH_COVER_MAX)))
    batch_qty  = max(batch_qty, 10)   # floor of 10 units per batch

    unit_cost  = calc_purchase_cost(product["base_cost"], today)
    batch_id   = batch_ctr.next()

    shelf_life = int(product["shelf_life_days"])
    expiry_date = expected_date + timedelta(days=shelf_life)

    return {
        "batch_id":          batch_id,
        "product_id":        product["product_id"],
        "supplier_id":       supplier_id,
        "warehouse_id":      warehouse_id,
        "expected_date":     expected_date,
        "manufacture_date":  expected_date - timedelta(days=1),
        "expiry_date":       expiry_date,
        "quantity":          batch_qty,
        "unit_cost":         unit_cost,
    }


# =============================================================================
# INITIAL INVENTORY SEEDING (before Day 1)
# =============================================================================

def seed_initial_inventory(inventory, pending_deliveries, df_products,
                            warehouses, sup_prod_map, suppliers,
                            batch_ctr, receipt_ctr, goods_receipts_log):

    for wh_id, wh in warehouses.items():
        for _, product in df_products.iterrows():

            # Skip products not yet launched
            if product["launch_date"] > SIM_START:
                continue

            # Skip perishables that need cold storage in non-cold warehouse
            needs_cold = product["category"] in \
                         ["Milk", "Fresh Juice", "Yogurt", "Ready Meals"]
            if needs_cold and wh["cold_storage_flag"] == 0:
                continue

            num_batches = random.randint(config.INITIAL_BATCHES_MIN,
                                         config.INITIAL_BATCHES_MAX)
            supplier_id = get_primary_supplier(product["product_id"],
                                               sup_prod_map)
            supplier    = suppliers[supplier_id]
            base_demand = product["base_daily_demand"]
            shelf_life  = int(product["shelf_life_days"])

            for b in range(num_batches):
                # Receipt date is 1–3 days before sim start
                days_before = random.randint(1, 3)
                receipt_date = SIM_START - timedelta(days=days_before)
                expiry_date  = receipt_date + timedelta(days=shelf_life)

                # Skip if already expired before sim starts
                if expiry_date <= SIM_START:
                    continue

                qty       = int(round(base_demand *
                                      random.uniform(config.BATCH_COVER_MIN,
                                                     config.BATCH_COVER_MAX)))
                qty       = max(qty, 10)
                unit_cost = calc_purchase_cost(product["base_cost"],
                                               receipt_date)
                batch_id  = batch_ctr.next()
                receipt_id = receipt_ctr.next()

                batch = {
                    "batch_id":          batch_id,
                    "supplier_id":       supplier_id,
                    "quantity_remaining": qty,
                    "receipt_date":       receipt_date,
                    "expiry_date":        expiry_date,
                    "unit_cost":          unit_cost,
                }
                inventory[wh_id][product["product_id"]].append(batch)

                goods_receipts_log.append({
                    "receipt_id":            receipt_id,
                    "batch_id":              batch_id,
                    "product_id":            product["product_id"],
                    "supplier_id":           supplier_id,
                    "warehouse_id":          wh_id,
                    "receipt_date":          receipt_date.isoformat(),
                    "manufacture_date":      (receipt_date - timedelta(days=1)).isoformat(),
                    "expiry_date":           expiry_date.isoformat(),
                    "quantity_received":     qty,
                    "purchase_price_per_unit": unit_cost,
                    "total_batch_cost":      round(qty * unit_cost, 2),
                })


# =============================================================================
# MAIN SIMULATION LOOP
# =============================================================================

def run_simulation():

    # ── Load master data ─────────────────────────────────────────────────────
    df_products, warehouses, suppliers, sup_prod_map = load_master_data()

    # Assign a fixed base daily demand to each product (random, stable)
    base_demand_map = {
        row["product_id"]: random.randint(config.DEMAND_MIN, config.DEMAND_MAX)
        for _, row in df_products.iterrows()
    }
    # Attach to df_products for seeding convenience
    df_products = df_products.copy()
    df_products["base_daily_demand"] = df_products["product_id"].map(base_demand_map)

    # ── ID counters ──────────────────────────────────────────────────────────
    batch_ctr   = Counter("B")
    receipt_ctr = Counter("GR")
    sale_ctr    = Counter("S")
    adj_ctr     = Counter("ADJ")
    stockout_ctr = Counter("SO")

    # ── Output logs (list of dicts → DataFrames at end) ──────────────────────
    goods_receipts_log = []
    sales_log          = []
    sale_batch_map_log = []
    adjustments_log    = []
    stockouts_log      = []

    # ── In-memory state ──────────────────────────────────────────────────────
    inventory          = make_inventory()
    pending_deliveries = []   # list of delivery dicts scheduled for future dates
    promo_state        = init_promo_state(df_products["product_id"].tolist())

    # Track which products are currently active on a given day
    # (handles late-launch products)
    launched_products = set(
        df_products[df_products["launch_date"] <= SIM_START]["product_id"]
    )

    # ── Seed initial inventory ───────────────────────────────────────────────
    print("Seeding initial inventory...")
    seed_initial_inventory(
        inventory, pending_deliveries, df_products,
        warehouses, sup_prod_map, suppliers,
        batch_ctr, receipt_ctr, goods_receipts_log
    )

    # ── Daily loop ───────────────────────────────────────────────────────────
    print(f"Running simulation: {config.SIM_DAYS} days...\n")

    for day_num in range(config.SIM_DAYS):
        today = SIM_START + timedelta(days=day_num)

        if day_num % 30 == 0:
            print(f"  Day {day_num+1:3d} — {today}  "
                  f"| Sales: {len(sales_log):,}  "
                  f"| Receipts: {len(goods_receipts_log):,}  "
                  f"| Adjustments: {len(adjustments_log):,}")

        # Check for newly launched products
        for _, product in df_products.iterrows():
            if (product["product_id"] not in launched_products and
                    product["launch_date"] <= today):
                launched_products.add(product["product_id"])

        # Active products today
        active_products = df_products[
            df_products["product_id"].isin(launched_products)
        ]

        # ── STEP 1: Receive scheduled deliveries ─────────────────────────────
        still_pending = []
        for delivery in pending_deliveries:
            if delivery["expected_date"] <= today:
                pid = delivery["product_id"]
                wid = delivery["warehouse_id"]

                batch = {
                    "batch_id":           delivery["batch_id"],
                    "supplier_id":        delivery["supplier_id"],
                    "quantity_remaining": delivery["quantity"],
                    "receipt_date":       today,
                    "expiry_date":        delivery["expiry_date"],
                    "unit_cost":          delivery["unit_cost"],
                }
                inventory[wid][pid].append(batch)

                receipt_id = receipt_ctr.next()
                goods_receipts_log.append({
                    "receipt_id":              receipt_id,
                    "batch_id":                delivery["batch_id"],
                    "product_id":              pid,
                    "supplier_id":             delivery["supplier_id"],
                    "warehouse_id":            wid,
                    "receipt_date":            today.isoformat(),
                    "manufacture_date":        delivery["manufacture_date"].isoformat(),
                    "expiry_date":             delivery["expiry_date"].isoformat(),
                    "quantity_received":       delivery["quantity"],
                    "purchase_price_per_unit": delivery["unit_cost"],
                    "total_batch_cost":        round(
                        delivery["quantity"] * delivery["unit_cost"], 2),
                })
            else:
                still_pending.append(delivery)
        pending_deliveries = still_pending

        # ── STEP 2: Remove expired batches ────────────────────────────────────
        for wh_id in list(inventory.keys()):
            for pid in list(inventory[wh_id].keys()):
                live_batches  = []
                for batch in inventory[wh_id][pid]:
                    if batch["expiry_date"] <= today:
                        if batch["quantity_remaining"] > 0:
                            adj_id = adj_ctr.next()
                            adjustments_log.append({
                                "adjustment_id":   adj_id,
                                "adjustment_date": today.isoformat(),
                                "warehouse_id":    wh_id,
                                "product_id":      pid,
                                "batch_id":        batch["batch_id"],
                                "adjustment_type": "Expiry",
                                "quantity_adjusted": batch["quantity_remaining"],
                                "reason_notes":    "Batch expired — auto write-off",
                            })
                    else:
                        live_batches.append(batch)
                inventory[wh_id][pid] = live_batches

        # ── STEP 3 & 4: Generate demand, process sales ────────────────────────
        for wh_id, wh in warehouses.items():
            region = wh["region"]

            for _, product in active_products.iterrows():
                pid        = product["product_id"]
                category   = product["category"]
                base_demand = base_demand_map[pid]

                # Cold storage check — skip if warehouse can't handle it
                needs_cold = category in \
                             ["Milk", "Fresh Juice", "Yogurt", "Ready Meals"]
                if needs_cold and wh["cold_storage_flag"] == 0:
                    continue

                # Update promotion state for this product
                promo = update_promo_state(promo_state, pid)

                # Calculate total demand for today
                total_demand = calc_daily_demand(
                    base_demand, today, region,
                    promo["active"], promo["boost"]
                )

                # How much stock do we have?
                total_stock = get_total_stock(inventory, wh_id, pid)

                if total_stock == 0:
                    # Full stockout — record event, no sale
                    stockouts_log.append({
                        "stockout_id":      stockout_ctr.next(),
                        "stockout_date":    today.isoformat(),
                        "warehouse_id":     wh_id,
                        "product_id":       pid,
                        "quantity_demanded": total_demand,
                        "quantity_supplied": 0,
                        "shortfall":        total_demand,
                    })
                    continue

                # Split daily demand into 1–3 separate transactions
                # (realistic: multiple customer orders in a day)
                num_transactions = random.randint(1, 3)
                demand_splits = []
                remaining = total_demand
                for t in range(num_transactions):
                    if t == num_transactions - 1:
                        demand_splits.append(remaining)
                    else:
                        chunk = random.randint(1, max(1, remaining - (num_transactions - t - 1)))
                        demand_splits.append(chunk)
                        remaining -= chunk

                total_qty_sold = 0

                for txn_demand in demand_splits:
                    if txn_demand <= 0:
                        continue

                    avail = get_total_stock(inventory, wh_id, pid)
                    if avail <= 0:
                        break

                    qty_sold    = min(txn_demand, avail)
                    is_stockout = qty_sold < txn_demand

                    # Selling price with noise
                    noise = random.uniform(1 - config.PRICE_NOISE_PCT,
                                           1 + config.PRICE_NOISE_PCT)
                    sell_price = round(float(product["base_price"]) * noise, 2)

                    sale_id = sale_ctr.next()
                    sales_log.append({
                        "sale_id":               sale_id,
                        "sale_date":             today.isoformat(),
                        "warehouse_id":          wh_id,
                        "product_id":            pid,
                        "quantity_sold":         qty_sold,
                        "selling_price_per_unit": sell_price,
                        "discount_percent":      promo["discount"] if promo["active"] else 0.0,
                        "promotion_flag":        1 if promo["active"] else 0,
                    })

                    # ── Deduct stock — random batch selection ─────────────────
                    # Batches are shuffled randomly before deduction.
                    # A sale may pull from any available batch, not just oldest.
                    batches = inventory[wh_id][pid][:]
                    random.shuffle(batches)
                    qty_to_deduct = qty_sold

                    for batch in batches:
                        if qty_to_deduct <= 0:
                            break
                        take = min(batch["quantity_remaining"], qty_to_deduct)

                        if take > 0:
                            sale_batch_map_log.append({
                                "sale_id":             sale_id,
                                "batch_id":            batch["batch_id"],
                                "quantity_from_batch": take,
                                "unit_cost_at_sale":   batch["unit_cost"],
                            })

                        batch["quantity_remaining"] -= take
                        qty_to_deduct              -= take

                    inventory[wh_id][pid] = batches
                    total_qty_sold += qty_sold

                    if is_stockout:
                        stockouts_log.append({
                            "stockout_id":       stockout_ctr.next(),
                            "stockout_date":     today.isoformat(),
                            "warehouse_id":      wh_id,
                            "product_id":        pid,
                            "quantity_demanded": txn_demand,
                            "quantity_supplied": qty_sold,
                            "shortfall":         txn_demand - qty_sold,
                        })

        # ── STEP 5: Evaluate reorders ─────────────────────────────────────────
        for wh_id, wh in warehouses.items():
            for _, product in active_products.iterrows():
                pid      = product["product_id"]
                category = product["category"]

                needs_cold = category in \
                             ["Milk", "Fresh Juice", "Yogurt", "Ready Meals"]
                if needs_cold and wh["cold_storage_flag"] == 0:
                    continue

                supplier_id = get_primary_supplier(pid, sup_prod_map)
                supplier    = suppliers[supplier_id]
                lead_time   = supplier["average_lead_time_days"]
                base_demand = base_demand_map[pid]

                coverage = get_coverage_days(inventory, wh_id, pid, base_demand)

                if should_reorder(coverage, lead_time):
                    delivery = create_delivery(
                        batch_ctr, product, wh_id, supplier_id,
                        suppliers, base_demand, today
                    )
                    pending_deliveries.append(delivery)

        # ── STEP 6: Shrinkage ─────────────────────────────────────────────────
        for wh_id in list(inventory.keys()):
            for pid in list(inventory[wh_id].keys()):
                if random.random() < config.SHRINKAGE_DAILY_PROB:
                    # Pick a random batch to apply shrinkage to
                    live = [b for b in inventory[wh_id][pid]
                            if b["quantity_remaining"] > 0]
                    if not live:
                        continue

                    batch = random.choice(live)
                    rate  = random.uniform(config.SHRINKAGE_RATE_MIN,
                                           config.SHRINKAGE_RATE_MAX)
                    shrink_qty = max(1, int(round(
                        batch["quantity_remaining"] * rate)))

                    batch["quantity_remaining"] = max(
                        0, batch["quantity_remaining"] - shrink_qty)

                    adjustments_log.append({
                        "adjustment_id":     adj_ctr.next(),
                        "adjustment_date":   today.isoformat(),
                        "warehouse_id":      wh_id,
                        "product_id":        pid,
                        "batch_id":          batch["batch_id"],
                        "adjustment_type":   "Shrinkage",
                        "quantity_adjusted": shrink_qty,
                        "reason_notes":      "Routine shrinkage loss",
                    })

    # ── End of simulation ────────────────────────────────────────────────────
    print(f"\nSimulation complete.\n")

    return (goods_receipts_log, sales_log, sale_batch_map_log,
            adjustments_log, stockouts_log)


# =============================================================================
# SAVE OUTPUT
# =============================================================================

def save_outputs(goods_receipts_log, sales_log, sale_batch_map_log,
                 adjustments_log, stockouts_log):

    os.makedirs(config.OUTPUT_DIR, exist_ok=True)

    df_gr  = pd.DataFrame(goods_receipts_log)
    df_s   = pd.DataFrame(sales_log)
    df_sbm = pd.DataFrame(sale_batch_map_log)
    df_adj = pd.DataFrame(adjustments_log)
    df_so  = pd.DataFrame(stockouts_log)

    df_gr.to_csv(config.OUTPUT_FILES["goods_receipts"], index=False)
    df_s.to_csv(config.OUTPUT_FILES["sales"],           index=False)
    df_sbm.to_csv(config.OUTPUT_FILES["sale_batch_map"], index=False)
    df_adj.to_csv(config.OUTPUT_FILES["adjustments"],   index=False)
    df_so.to_csv(config.OUTPUT_FILES["stockouts"],      index=False)

    print("── Output summary ───────────────────────────────────────────────")
    print(f"  fact_goods_receipts    → {len(df_gr):,} rows")
    print(f"  fact_sales             → {len(df_s):,} rows")
    print(f"  fact_sale_batch_map    → {len(df_sbm):,} rows")
    print(f"  fact_inventory_adj     → {len(df_adj):,} rows")
    print(f"  fact_stockout_events   → {len(df_so):,} rows")
    print(f"\n  Files saved to: {config.OUTPUT_DIR}")


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    results = run_simulation()
    save_outputs(*results)
