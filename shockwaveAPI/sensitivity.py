"""sensitivity.py — sweep one variable at a time and print the impact."""
import time
from fastapi.testclient import TestClient
from app.main import app

EXCLUDE = [
    "long_term_care", "earthquake", "wildfire", "house_fire",
    "lawsuit_liability", "divorce", "business_income_drop",
    "hoa_special_assessment", "eldercare",
]

BASE = {
    "horizon_months": 60,
    "n_paths": 2000,          # faster; rerun key winners at 5000
    "seed": 42,
    "exclude_risk_keys": EXCLUDE,
}

LIFE_EVENTS = [
    {"label": "First child", "month": 14, "expense_delta": 1250, "one_time_cost": 3000},
    {"label": "Car replacement", "month": 24, "expense_delta": 420, "one_time_cost": 4000},
]


def run(client, aid, **overrides):
    payload = {"account_id": aid, **BASE, **overrides}
    r = client.post("/api/simulate", json=payload).json()
    s = r["summary"]
    return s["probability_of_ruin"], s["median_end_balance"], s["p5_end_balance"]


def table(title, rows, fmt_cols=("P(ruin)", "median end", "p5 end")):
    print(f"\n{'='*70}\n  {title}\n{'='*70}")
    print(f"  {'value':<14}  {fmt_cols[0]:>9}  {fmt_cols[1]:>13}  {fmt_cols[2]:>13}")
    print(f"  {'-'*14}  {'-'*9:>9}  {'-'*13:>13}  {'-'*13:>13}")
    for label, ruin, med, p5 in rows:
        print(f"  {label:<14}  {ruin:>8.2%}  ${med:>12,.0f}  ${p5:>12,.0f}")


with TestClient(app) as client:
    aid = client.post("/api/link/exchange", json={"public_token": "x"}).json()["account_id"]
    client.post(f"/api/accounts/{aid}/sync?months=14")

    # ---------- 1. Starting balance ----------
    print("\nRunning starting-balance sweep ...")
    rows = []
    for bal in [5000, 8500, 15000, 20000, 30000, 50000, 75000]:
        ruin, med, p5 = run(client, aid, starting_balance=bal, life_events=LIFE_EVENTS)
        rows.append((f"${bal:,}", ruin, med, p5))
    table("Starting balance sweep (60mo, 2k paths)", rows)

    # ---------- 2. Horizon ----------
    print("\nRunning horizon sweep ...")
    rows = []
    for h in [12, 24, 36, 60, 120]:
        ruin, med, p5 = run(client, aid, horizon_months=h, life_events=LIFE_EVENTS)
        rows.append((f"{h} months", ruin, med, p5))
    table("Horizon sweep (starting balance $8,500)", rows)

    # ---------- 3. Ruin floor ----------
    print("\nRunning ruin-floor sweep ...")
    rows = []
    for floor in [0, -1000, -2500, -5000]:
        ruin, med, p5 = run(client, aid, ruin_floor=floor, life_events=LIFE_EVENTS)
        rows.append((f"${floor:,}", ruin, med, p5))
    table("Ruin floor sweep (negative = overdraft/credit tolerance)", rows)

    # ---------- 4. Path-count convergence ----------
    print("\nRunning convergence check (proves 5000 is enough) ...")
    rows = []
    for n in [500, 1000, 2000, 5000, 10000]:
        t0 = time.time()
        ruin, med, p5 = run(client, aid, n_paths=n, life_events=LIFE_EVENTS)
        dt = time.time() - t0
        rows.append((f"n={n} ({dt:.1f}s)", ruin, med, p5))
    table("Path-count convergence (seed=42)", rows)