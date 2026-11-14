"""End-to-end demo: ingest -> profile -> simulate -> stress test."""
from fastapi.testclient import TestClient

from app.main import app

# NOTE: TestClient must be used as a context manager so FastAPI's
# startup/lifespan event fires and db.init_db() actually creates tables.
with TestClient(app) as client:

    print("1) Creating link token ...")
    print(client.post("/api/link/create").json())

    print("\n2) Exchanging public token ...")
    acct = client.post("/api/link/exchange", json={"public_token": "public-sandbox-mock"}).json()
    aid = acct["account_id"]
    print(acct)

    print("\n3) Syncing 14 months of transactions ...")
    print(client.post(f"/api/accounts/{aid}/sync?months=14").json())

    print("\n4) Cash-flow baseline + recurring series ...")
    prof = client.get(f"/api/accounts/{aid}/profile").json()
    b = prof["baseline"]
    for k, v in b.items():
        print(f"   {k:32s} {v}")

    print("\n   Recurring series detected:")
    for r in prof["recurring"][:12]:
        print(f"   {r['merchant'][:28]:28s} {r['cadence']:11s} "
              f"{r['avg_amount']:>10.2f}  conf={r['confidence']:.2f}")

    print(f"\n   Overdraft risk in next 60d: {prof['overdraft_forecast']['overdraft_risk']} "
          f"(min {prof['overdraft_forecast']['min_balance']})")

    print("\n5) Monte Carlo simulation (5,000 paths, 60 months) ...")
    sim = client.post("/api/simulate", json={
        "account_id": aid,
        "horizon_months": 60,
        "n_paths": 5000,
        "seed": 42,
        "starting_balance": 20000,  # 6-month emergency fund
        "ruin_floor": -2000,  # modest overdraft/credit buffer
        "exclude_risk_keys": [  # not applicable to a healthy 28yo renter
            "long_term_care",
            "earthquake",
            "wildfire",
            "house_fire",
            "lawsuit_liability",
            "divorce",
            "business_income_drop",
            "hoa_special_assessment",
            "eldercare",
        ],
        "life_events": [
            {"label": "First child", "month": 14, "expense_delta": 1250, "one_time_cost": 3000},
            {"label": "Car replacement", "month": 24, "expense_delta": 420, "one_time_cost": 4000},
        ],
    }).json()

    s = sim["summary"]
    print(f"   P(ruin):              {s['probability_of_ruin']:.1%}")
    print(f"   Median end balance:   ${s['median_end_balance']:,.0f}")
    print(f"   5th pct end balance:  ${s['p5_end_balance']:,.0f}")
    print(f"   Expected shortfall:   ${s['expected_shortfall_5pct']:,.0f}")
    print(f"   Expected shock cost:  ${s['expected_total_shock_cost']:,.0f}")

    print("\n   Top risk drivers (delta ruin vs. baseline):")
    for d in sim["top_drivers"]:
        print(f"   {d['label'][:34]:34s} {d['delta_ruin']:+.3f}  "
              f"(p={d['p_occurs_in_horizon']:.2f})")

    print("\n6) Deterministic stress tests ...")
    st = client.post("/api/stress-test", json={"account_id": aid, "horizon_months": 36}).json()
    for sc in st["scenarios"]:
        print(f"   {sc['label'][:44]:44s} P(ruin)={sc['probability_of_ruin']:.1%}")