from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta

import numpy as np

from .models import CashflowBaseline, RecurringSeries, Txn


def _month_key(d: date) -> tuple[int, int]:
    return (d.year, d.month)


def build_baseline(
    txns: list[Txn],
    recurring: list[RecurringSeries],
    liquid_balance: float,
) -> CashflowBaseline:
    """Turn raw history + recurring series into a monthly cash-flow baseline."""

    income_series = [r for r in recurring if r.is_income and r.confidence >= 0.55]
    expense_series = [r for r in recurring if not r.is_income and r.confidence >= 0.55]

    # Fixed vs variable-recurring split
    fixed_series = [r for r in expense_series if r.amount_cv <= 0.20]
    variable_recurring = [r for r in expense_series if r.amount_cv > 0.20]

    monthly_income = sum(r.monthly_equivalent for r in income_series)
    monthly_fixed = sum(-r.monthly_equivalent for r in fixed_series)

    # Variable spend = non-recurring expenses, bucketed by month
    recurring_merchants = {r.merchant for r in recurring}
    buckets: dict[tuple[int, int], dict[str, float]] = defaultdict(
        lambda: {"income": 0.0, "expense": 0.0, "essential": 0.0}
    )

    for t in txns:
        if t.pending:
            continue
        k = _month_key(t.date)
        if t.amount > 0:
            buckets[k]["income"] += t.amount
        else:
            if t.merchant in recurring_merchants:
                continue
            buckets[k]["expense"] += -t.amount
            if t.is_essential:
                buckets[k]["essential"] += -t.amount

    if buckets:
        keys = sorted(buckets)
        # Drop partial first/last month
        if len(keys) > 3:
            keys = keys[1:-1]
        var_vals = np.array([buckets[k]["expense"] for k in keys], dtype=float)
        ess_var_vals = np.array([buckets[k]["essential"] for k in keys], dtype=float)
    else:
        var_vals = np.array([0.0])
        ess_var_vals = np.array([0.0])

    variable_mean = float(np.mean(var_vals)) if var_vals.size else 0.0
    variable_std = float(np.std(var_vals, ddof=1)) if var_vals.size > 1 else variable_mean * 0.25

    # Variable-recurring series (utilities etc.) contribute to variable spend
    variable_mean += sum(-r.monthly_equivalent for r in variable_recurring)

    net_mean = monthly_income - monthly_fixed - variable_mean
    net_std = float(np.sqrt(variable_std ** 2 + (0.02 * monthly_income) ** 2))

    essential_monthly = (
        sum(-r.monthly_equivalent for r in fixed_series if r.essential)
        + float(np.mean(ess_var_vals)) if ess_var_vals.size else 0.0
    )
    # fall back if categorization was sparse
    if essential_monthly <= 0:
        essential_monthly = monthly_fixed + 0.6 * variable_mean

    runway = (liquid_balance / essential_monthly) if essential_monthly > 0 else 0.0
    savings_rate = (net_mean / monthly_income) if monthly_income > 0 else 0.0

    return CashflowBaseline(
        monthly_income=round(monthly_income, 2),
        monthly_fixed=round(monthly_fixed, 2),
        monthly_variable_mean=round(variable_mean, 2),
        monthly_variable_std=round(variable_std, 2),
        monthly_net_mean=round(net_mean, 2),
        monthly_net_std=round(net_std, 2),
        essential_monthly=round(essential_monthly, 2),
        liquid_balance=round(liquid_balance, 2),
        emergency_runway_months=round(runway, 2),
        savings_rate=round(savings_rate, 3),
        monthly_income_volatility=round(0.02 * monthly_income, 2),
    )


def daily_forecast(
    recurring: list[RecurringSeries],
    variable_mean: float,
    variable_std: float,
    start_balance: float,
    days: int = 60,
    start: date | None = None,
) -> dict:
    """
    Deterministic day-by-day balance projection that catches *timing collisions*
    (rent clearing before the paycheck => overdraft even though the month nets positive).
    """
    start = start or date.today()
    horizon = [start + timedelta(days=i) for i in range(days)]

    daily = np.zeros(days)
    for r in recurring:
        if r.confidence < 0.5:
            continue
        d = r.next_expected
        # roll forward until inside window
        while d < start:
            step = {"weekly": 7, "biweekly": 14, "semimonthly": 15, "monthly": 30,
                    "quarterly": 91, "semiannual": 182, "annual": 365}.get(r.cadence, 30)
            d = d + timedelta(days=step)
        while d < start + timedelta(days=days):
            daily[(d - start).days] += r.avg_amount
            step = {"weekly": 7, "biweekly": 14, "semimonthly": 15, "monthly": 30,
                    "quarterly": 91, "semiannual": 182, "annual": 365}.get(r.cadence, 30)
            d = d + timedelta(days=step)

    # Smear discretionary spend evenly across the window
    daily -= variable_mean / 30.4

    balance = start_balance + np.cumsum(daily)
    idx_min = int(np.argmin(balance))

    return {
        "start_date": start.isoformat(),
        "days": days,
        "dates": [d.isoformat() for d in horizon],
        "balance": [round(float(b), 2) for b in balance],
        "min_balance": round(float(balance[idx_min]), 2),
        "min_balance_date": horizon[idx_min].isoformat(),
        "overdraft_risk": bool(balance.min() < 0),
        "first_overdraft_date": (
            horizon[int(np.argmax(balance < 0))].isoformat()
            if (balance < 0).any() else None
        ),
    }