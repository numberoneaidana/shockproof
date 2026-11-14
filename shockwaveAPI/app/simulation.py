from __future__ import annotations

import math
from typing import Iterable

import numpy as np

from .models import CashflowBaseline, SimulationRequest
from .risk_catalog import (
    GROUPS, RHO_WITHIN, RISK_BY_KEY, RiskEvent, group_corr_matrix,
)

SQRT2 = math.sqrt(2.0)


def _norm_cdf(x: np.ndarray) -> np.ndarray:
    """
    Fast standard-normal CDF (tanh approximation, max abs error ~1e-3).
    Avoids a scipy dependency; plenty accurate for occurrence sampling.
    """
    return 0.5 * (1.0 + np.tanh(0.7978845608028654 * (x + 0.044715 * x ** 3)))


def _resolve_risks(req: SimulationRequest) -> list[RiskEvent]:
    if req.risk_keys is None:
        events = list(RISK_BY_KEY.values())
    else:
        events = [RISK_BY_KEY[k] for k in req.risk_keys if k in RISK_BY_KEY]

    p = req.profile or {}
    exclude = set(req.exclude_risk_keys)

    # --- PROFILE-BASED FILTERING ---
    age = p.get("age", 30)
    mortgage = p.get("mortgage", 0)

    # Exclude long-term care if user is young
    if age < 55:
        exclude.add("long_term_care")

    # Exclude home repairs if they have no mortgage (renter)
    if mortgage == 0:
        exclude.add("home_repair_major")
        exclude.add("hoa_special_assessment")
        exclude.add("water_damage_flood")

    # Exclude kids/pets if not in profile
    if not p.get("has_pets", False):
        exclude.add("pet_emergency")

    return [e for e in events if e.key not in exclude]
def _apply_life_events(
    base_net: np.ndarray, req: SimulationRequest
) -> np.ndarray:
    H = base_net.shape[0]
    for le in req.life_events:
        s = max(0, min(le.month, H - 1))
        e = H if le.duration_months is None else min(H, s + max(1, le.duration_months))
        if e > s:
            base_net[s:e] += le.income_delta - le.expense_delta
        if le.one_time_cost:
            base_net[s] -= le.one_time_cost
    return base_net


def _spread(shock, path_idx, start, duration, total_amount, H):
    if path_idx.size == 0:
        return
    monthly = total_amount / np.maximum(duration, 1)
    maxdur = int(duration.max())
    for k in range(maxdur):
        active = (k < duration) & ((start + k) < H)   # ← add (k < duration)
        if not active.any():
            break
        rows = path_idx[active]
        cols = start[active] + k
        np.add.at(shock, (rows, cols), monthly[active])


def run_simulation(
    profile: CashflowBaseline,
    req: SimulationRequest,
) -> dict:
    rng = np.random.default_rng(req.seed)
    H = req.horizon_months
    N = req.n_paths
    start_balance = (
        req.starting_balance if req.starting_balance is not None
        else profile.liquid_balance
    )

    t = np.arange(H, dtype=float)
    exp_mult = (1.0 + req.inflation_annual) ** (t / 12.0)
    inc_mult = (1.0 + req.wage_growth_annual) ** (t / 12.0)

    # ---------- deterministic base path ----------
    income = profile.monthly_income * inc_mult
    expenses = (profile.monthly_fixed + profile.monthly_variable_mean) * exp_mult
    base_net = income - expenses
    base_net = _apply_life_events(base_net, req)

    # ---------- per-path stochastic net cash flow ----------
    var_noise = rng.normal(0.0, profile.monthly_variable_std, (N, H)) * exp_mult
    inc_noise = rng.normal(0.0, profile.monthly_income_volatility, (N, H)) * inc_mult
    net = base_net[None, :] + var_noise + inc_noise

    # ---------- shock engine ----------
    shock = np.zeros((N, H), dtype=float)
    events = _resolve_risks(req)
    n_groups = len(GROUPS)
    group_idx = {g: i for i, g in enumerate(GROUPS)}

    L = np.linalg.cholesky(group_corr_matrix())
    z_group = rng.standard_normal((N, n_groups)) @ L.T

    attribution: list[dict] = []

    for ev in events:
        gi = group_idx[ev.correlation_group]
        rho = RHO_WITHIN.get(ev.correlation_group, 0.35)
        z_e = math.sqrt(rho) * z_group[:, gi] + math.sqrt(1 - rho) * rng.standard_normal(N)
        u_e = _norm_cdf(z_e)

        p_h = 1.0 - (1.0 - ev.annual_probability) ** (H / 12.0)
        occ = u_e < p_h
        n_occ = int(occ.sum())
        if n_occ == 0:
            attribution.append({
                "key": ev.key, "label": ev.label, "category": ev.category,
                "annual_probability": ev.annual_probability,
                "p_occurs_in_horizon": 0.0,
                "mean_net_cost": 0.0,
                "conditional_ruin_rate": None,
                "delta_ruin": None,
            })
            continue

        idx = np.flatnonzero(occ)
        start = rng.integers(0, H, n_occ)
        dur_mean = max(1.0, ev.duration_months_mean)
        dur = np.maximum(1, rng.poisson(dur_mean, n_occ)).astype(int)
        dur = np.minimum(dur, 36)

        # Gross cost from a lognormal fitted to (median, p90), net of insurance
        if ev.median_cost > 0:
            gross = rng.lognormal(ev.mu, ev.sigma, n_occ)
            net_cost = gross * (1.0 - ev.coverage)
        else:
            net_cost = np.zeros(n_occ)

        # Income interruption, net of unemployment benefits etc.
        if ev.income_loss_fraction > 0:
            inc_loss = (
                profile.monthly_income * ev.income_loss_fraction
            ) * np.ones(n_occ)
            _spread(shock, idx, start, dur, -inc_loss * dur, H)

        if net_cost.any():
            _spread(shock, idx, start, dur, -net_cost, H)

        attribution.append({
            "key": ev.key,
            "label": ev.label,
            "category": ev.category,
            "annual_probability": ev.annual_probability,
            "p_occurs_in_horizon": round(float(p_h), 4),
            "mean_net_cost": round(float(net_cost.mean()), 2),
            "_idx": idx,
        })

    # ---------- forced (deterministic) stress events ----------
    for fe in req.forced_events:
        idx_all = np.arange(N)
        start = np.full(N, max(0, min(fe.month, H - 1)))
        dur = np.full(N, max(1, fe.duration_months))
        if fe.gross_cost:
            _spread(shock, idx_all, start, dur,
                    -np.full(N, fe.gross_cost * (1.0 - fe.coverage)), H)
        if fe.income_loss_fraction:
            loss = profile.monthly_income * fe.income_loss_fraction * fe.duration_months
            _spread(shock, idx_all, start, dur, -np.full(N, loss), H)

    # ---------- balance paths ----------
    balance = start_balance + np.cumsum(net + shock, axis=1)
    min_balance = balance.min(axis=1)
    ruin = min_balance < req.ruin_floor
    p_ruin = float(ruin.mean())

    # ---------- ruin attribution ----------
    for a in attribution:
        idx = a.pop("_idx", None)
        if idx is None or idx.size == 0:
            a["conditional_ruin_rate"] = None
            a["delta_ruin"] = None
            continue
        cond = float(ruin[idx].mean())
        mask = np.ones(N, dtype=bool)
        mask[idx] = False
        base = float(ruin[mask].mean()) if mask.any() else p_ruin
        a["conditional_ruin_rate"] = round(cond, 4)
        a["delta_ruin"] = round(cond - base, 4)

    # ---------- summary metrics ----------
    end_balance = balance[:, -1]
    p5_end = float(np.percentile(end_balance, 5))
    worst_5 = end_balance[end_balance <= p5_end]
    es5 = float(worst_5.mean()) if worst_5.size else p5_end

    months_to_ruin = np.where(
        (balance < req.ruin_floor).any(axis=1),
        (balance < req.ruin_floor).argmax(axis=1),
        -1,
    )
    ruined_months = months_to_ruin[months_to_ruin >= 0]

    # ---------- fan chart (downsampled) ----------
    pcts = np.percentile(balance, [5, 25, 50, 75, 95], axis=0)
    step = max(1, H // 60)
    cols = list(range(0, H, step))
    if cols[-1] != H - 1:
        cols.append(H - 1)

    fan = {
        "months": cols,
        "p5": [round(float(x), 2) for x in pcts[0][cols]],
        "p25": [round(float(x), 2) for x in pcts[1][cols]],
        "p50": [round(float(x), 2) for x in pcts[2][cols]],
        "p75": [round(float(x), 2) for x in pcts[3][cols]],
        "p95": [round(float(x), 2) for x in pcts[4][cols]],
    }

    drivers = sorted(
        [a for a in attribution if a["delta_ruin"] is not None],
        key=lambda a: a["delta_ruin"],
        reverse=True,
    )[:8]

    return {
        "summary": {
            "n_paths": N,
            "horizon_months": H,
            "starting_balance": round(start_balance, 2),
            "ruin_floor": req.ruin_floor,
            "probability_of_ruin": round(p_ruin, 4),
            "median_end_balance": round(float(np.median(end_balance)), 2),
            "p5_end_balance": round(p5_end, 2),
            "p95_end_balance": round(float(np.percentile(end_balance, 95)), 2),
            "expected_shortfall_5pct": round(es5, 2),
            "median_min_balance": round(float(np.median(min_balance)), 2),
            "p5_min_balance": round(float(np.percentile(min_balance, 5)), 2),
            "median_months_to_ruin": (
                int(np.median(ruined_months)) if ruined_months.size else None
            ),
            "expected_total_shock_cost": round(float(-shock.sum(axis=1).mean()), 2),
            "monthly_net_mean": profile.monthly_net_mean,
            "monthly_net_std": profile.monthly_net_std,
        },
        "fan_chart": fan,
        "risk_attribution": attribution,
        "top_drivers": drivers,
    }


# --------------------------------------------------------------------------
# Named stress-test scenarios (deterministic, single-path style)
# --------------------------------------------------------------------------

STRESS_SCENARIOS: dict[str, dict] = {
    "job_loss_6m": {
        "label": "Lose job for 6 months",
        "events": [{"key": "layoff", "month": 0, "duration_months": 6,
                    "gross_cost": 0, "coverage": 0, "income_loss_fraction": 1.0}],
    },
    "job_loss_12m": {
        "label": "Lose job for 12 months",
        "events": [{"key": "layoff", "month": 0, "duration_months": 12,
                    "gross_cost": 0, "coverage": 0, "income_loss_fraction": 1.0}],
    },
    "medical_20k": {
        "label": "Uninsured medical bill ($20k)",
        "events": [{"key": "hospitalization", "month": 1, "duration_months": 1,
                    "gross_cost": 20000, "coverage": 0.0,
                    "income_loss_fraction": 0.0}],
    },
    "hurricane": {
        "label": "Hurricane: $25k damage + 1 month lost income",
        "events": [{"key": "hurricane", "month": 3, "duration_months": 3,
                    "gross_cost": 25000, "coverage": 0.4,
                    "income_loss_fraction": 0.3}],
    },
    "layoff_plus_medical": {
        "label": "Layoff + medical emergency (correlated)",
        "events": [
            {"key": "layoff", "month": 0, "duration_months": 5,
             "gross_cost": 0, "coverage": 0, "income_loss_fraction": 1.0},
            {"key": "hospitalization", "month": 1, "duration_months": 1,
             "gross_cost": 15000, "coverage": 0.5, "income_loss_fraction": 0.2},
        ],
    },
    "rent_increase_25pct": {
        "label": "Rent +25% for the whole horizon",
        "life_events": [{"label": "Rent increase", "month": 0,
                         "expense_delta_pct_of_fixed": 0.25}],
    },
    "car_insurance_double": {
        "label": "Auto insurance doubles (the 'random $612' problem)",
        "life_events": [{"label": "Auto insurance spike", "month": 0,
                         "expense_delta": 600 / 6}],
    },
}