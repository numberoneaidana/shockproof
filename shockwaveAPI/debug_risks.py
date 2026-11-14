"""Print expected shock contribution per risk for the demo profile."""
import numpy as np
from fastapi.testclient import TestClient
from app.main import app

with TestClient(app) as client:
    aid = client.post(
        "/api/link/exchange",
        json={"public_token": "x"},
    ).json()["account_id"]
    client.post(f"/api/accounts/{aid}/sync?months=14")
    prof = client.get(f"/api/accounts/{aid}/profile").json()

    income = prof["baseline"]["monthly_income"]

    from app.risk_catalog import RISK_CATALOG

    H = 60
    total_inc, total_cost = 0.0, 0.0
    rows = []
    for ev in RISK_CATALOG:
        p_h = 1 - (1 - ev.annual_probability) ** (H / 12)

        # Income-loss contribution
        inc_contrib = 0.0
        if ev.income_loss_fraction > 0:
            inc_contrib = p_h * income * ev.income_loss_fraction * max(1, ev.duration_months_mean)

        # Cost contribution (E of lognormal, net of coverage)
        cost_contrib = 0.0
        if ev.median_cost > 0:
            E_gross = float(np.exp(ev.mu + ev.sigma ** 2 / 2))
            E_net = E_gross * (1 - ev.coverage)
            cost_contrib = p_h * E_net

        rows.append((ev.key, p_h, inc_contrib, cost_contrib, inc_contrib + cost_contrib))
        total_inc += inc_contrib
        total_cost += cost_contrib

    rows.sort(key=lambda r: -r[4])
    print(f"profile income = ${income:,.0f}/mo")
    print(f"{'risk':30s} {'p_h':>6s} {'inc':>10s} {'cost':>10s} {'contrib':>10s}")
    for k, p_h, inc, cost, tot in rows[:15]:
        print(f"{k:30s} {p_h:6.3f} {inc:>10,.0f} {cost:>10,.0f} {tot:>10,.0f}")
    print(f"{'TOTAL':30s} {'':6s} {total_inc:>10,.0f} {total_cost:>10,.0f} {total_inc+total_cost:>10,.0f}")