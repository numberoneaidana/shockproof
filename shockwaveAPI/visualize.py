"""visualize.py — generate the 3 charts you'll use in the pitch."""
import matplotlib.pyplot as plt
from fastapi.testclient import TestClient
from app.main import app

EXCLUDE = ["long_term_care", "earthquake", "wildfire", "house_fire",
           "lawsuit_liability", "divorce", "business_income_drop",
           "hoa_special_assessment", "eldercare"]

with TestClient(app) as client:
    aid = client.post("/api/link/exchange", json={"public_token": "x"}).json()["account_id"]
    client.post(f"/api/accounts/{aid}/sync?months=14")

    # ---- Chart 1: P(ruin) vs starting balance ----
    balances = [5000, 8500, 15000, 20000, 30000, 50000, 75000]
    ruins = []
    for b in balances:
        r = client.post("/api/simulate", json={
            "account_id": aid, "horizon_months": 60, "n_paths": 2000,
            "seed": 42, "starting_balance": b, "exclude_risk_keys": EXCLUDE,
        }).json()
        ruins.append(r["summary"]["probability_of_ruin"] * 100)

    fig, ax = plt.subplots(figsize=(8, 4))
    ax.plot([b/1000 for b in balances], ruins, "o-", color="#2563eb", linewidth=2)
    ax.axvline(8.5, color="#dc2626", linestyle="--", label="You are here ($8.5k)")
    ax.axhline(1.0, color="#16a34a", linestyle=":", label="Target (<1% ruin)")
    ax.set_xlabel("Emergency fund ($ thousands)")
    ax.set_ylabel("P(ruin) over 5 years (%)")
    ax.set_title("Every $10k of savings buys ~1 percentage point of ruin risk")
    ax.legend()
    ax.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig("chart1_emergency_fund.png", dpi=150)

    # ---- Chart 2: Fan chart ----
    r = client.post("/api/simulate", json={
        "account_id": aid, "horizon_months": 60, "n_paths": 5000,
        "seed": 42, "exclude_risk_keys": EXCLUDE,
    }).json()
    fan = r["fan_chart"]
    months = fan["months"]

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.fill_between(months, fan["p5"], fan["p95"], alpha=0.15, color="#2563eb", label="5–95%")
    ax.fill_between(months, fan["p25"], fan["p75"], alpha=0.30, color="#2563eb", label="25–75%")
    ax.plot(months, fan["p50"], color="#2563eb", linewidth=2, label="Median")
    ax.axhline(0, color="black", linewidth=0.5)
    ax.set_xlabel("Month")
    ax.set_ylabel("Balance ($)")
    ax.set_title("5,000 simulated futures (60 months)")
    ax.legend()
    ax.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig("chart2_fan.png", dpi=150)

    # ---- Chart 3: Risk attribution bar (conditional severity) ----
    drivers = r["top_drivers"][:6]
    labels = [d["label"] for d in drivers]
    deltas = [d["delta_ruin"] * 100 for d in drivers]
    p_occurs = [d["p_occurs_in_horizon"] * 100 for d in drivers]

    fig, ax = plt.subplots(figsize=(10, 4.5))
    colors = ["#dc2626" if d > 5 else "#f59e0b" if d > 1 else "#9ca3af" for d in deltas]
    bars = ax.barh(labels[::-1], deltas[::-1], color=colors[::-1])
    for bar, p in zip(bars, p_occurs[::-1]):
        ax.text(bar.get_width() + 0.5, bar.get_y() + bar.get_height() / 2,
                f"fires {p:.0f}% of paths", va="center", fontsize=9, color="#4b5563")
    ax.set_xlabel("Worse ruin probability WHEN this risk fires (percentage points)")
    ax.set_title("Conditional severity — how bad is it when it happens?")
    ax.grid(alpha=0.3, axis="x")
    ax.set_xlim(0, max(deltas) * 1.35)
    plt.tight_layout()
    plt.savefig("chart3_drivers.png", dpi=150)

    print("Wrote: chart1_emergency_fund.png, chart2_fan.png, chart3_drivers.png")