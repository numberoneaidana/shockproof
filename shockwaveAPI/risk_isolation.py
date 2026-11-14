"""risk_isolation.py — rank risks two ways."""
from fastapi.testclient import TestClient
from app.main import app
from app.risk_catalog import RISK_CATALOG

EXCLUDE = [
    "long_term_care", "earthquake", "wildfire", "house_fire",
    "lawsuit_liability", "divorce", "business_income_drop",
    "hoa_special_assessment", "eldercare",
]
BASE = {"horizon_months": 60, "n_paths": 2000, "seed": 42}


def run(client, aid, **overrides):
    r = client.post("/api/simulate", json={"account_id": aid, **BASE, **overrides}).json()
    return r["summary"]["probability_of_ruin"]


with TestClient(app) as client:
    aid = client.post("/api/link/exchange", json={"public_token": "x"}).json()["account_id"]
    client.post(f"/api/accounts/{aid}/sync?months=14")

    # Baseline (all included risks)
    p_base = run(client, aid, exclude_risk_keys=EXCLUDE)
    print(f"Baseline P(ruin) with all included risks = {p_base:.3%}\n")

    # ---- View A: isolation ----
    print(f"{'Isolation (risk alone)':<38}  {'p(ruin)':>9}   {'delta':>8}")
    print("-" * 60)
    isolation = []
    for ev in RISK_CATALOG:
        if ev.key in EXCLUDE:
            continue
        p = run(client, aid, risk_keys=[ev.key])
        isolation.append((ev.key, p, p - p_base))
    isolation.sort(key=lambda x: -x[1])
    for key, p, d in isolation[:10]:
        print(f"  {key:<36}  {p:>8.2%}   {d:>+7.2%}")

    # ---- View B: drop-one ----
    print(f"\n{'Drop-one (all minus this)':<38}  {'p(ruin)':>9}   {'delta':>8}")
    print("-" * 60)
    drop = []
    for ev in RISK_CATALOG:
        if ev.key in EXCLUDE:
            continue
        exclude = [k for k in EXCLUDE] + [ev.key]
        p = run(client, aid, exclude_risk_keys=exclude)
        drop.append((ev.key, p, p - p_base))
    drop.sort(key=lambda x: -x[2])
    for key, p, d in drop[:10]:
        print(f"  {key:<36}  {p:>8.2%}   {d:>+7.2%}")