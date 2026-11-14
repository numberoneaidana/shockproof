# diagnose.py
import numpy as np
from app.models import CashflowBaseline, SimulationRequest
from app.simulation import run_simulation
from app.risk_catalog import RISK_CATALOG

profile = CashflowBaseline(
    monthly_income=6354, monthly_fixed=2218, monthly_variable_mean=1208,
    monthly_variable_std=207, monthly_net_mean=2928, monthly_net_std=243,
    essential_monthly=2422, liquid_balance=8500, emergency_runway_months=3.51,
    savings_rate=0.46, monthly_income_volatility=127,
)

# Same exclusions the demo used
EXCLUDE = {"long_term_care", "earthquake", "wildfire", "house_fire",
           "lawsuit_liability", "divorce", "business_income_drop",
           "hoa_special_assessment", "eldercare"}

req = SimulationRequest(
    account_id="x", horizon_months=60, n_paths=5000, seed=42,
    exclude_risk_keys=list(EXCLUDE),
)
result = run_simulation(profile, req)

# Independent hand-sum
total = 0.0
for ev in RISK_CATALOG:
    if ev.key in EXCLUDE:
        continue
    p_h = 1 - (1 - ev.annual_probability) ** 5
    if ev.median_cost > 0:
        E_gross = np.exp(ev.mu + ev.sigma**2 / 2)
        total += p_h * E_gross * (1 - ev.coverage)
    if ev.income_loss_fraction > 0:
        total += p_h * profile.monthly_income * ev.income_loss_fraction * ev.duration_months_mean

print(f"Engine:   ${result['summary']['expected_total_shock_cost']:>12,.0f}")
print(f"Hand-sum: ${total:>12,.0f}")
print(f"Ratio:    {result['summary']['expected_total_shock_cost'] / total:.2f}x")