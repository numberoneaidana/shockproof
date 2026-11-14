from __future__ import annotations

from datetime import date
from typing import Optional, Literal

from pydantic import BaseModel, Field

Cadence = Literal[
    "weekly", "biweekly", "semimonthly", "monthly",
    "quarterly", "semiannual", "annual", "irregular",
]


class Txn(BaseModel):
    txn_id: str
    account_id: str
    date: date
    amount: float                      # signed: + inflow, - outflow
    merchant_raw: str
    merchant: str = ""
    category: str = "Uncategorized"
    subcategory: str = ""
    is_essential: bool = False
    pending: bool = False


class RecurringSeries(BaseModel):
    merchant: str
    label: str
    category: str
    cadence: Cadence
    avg_amount: float                  # signed
    amount_cv: float
    occurrences: int
    monthly_equivalent: float          # signed, normalized to per-month
    last_date: date
    next_expected: date
    confidence: float
    is_income: bool
    essential: bool


class CashflowBaseline(BaseModel):
    monthly_income: float
    monthly_fixed: float
    monthly_variable_mean: float
    monthly_variable_std: float
    monthly_net_mean: float
    monthly_net_std: float
    essential_monthly: float
    liquid_balance: float
    emergency_runway_months: float
    savings_rate: float
    monthly_income_volatility: float


class LifeEvent(BaseModel):
    label: str
    month: int = 0
    duration_months: Optional[int] = None       # None => permanent
    income_delta: float = 0.0                   # + = more income / month
    expense_delta: float = 0.0                  # + = more expense / month
    one_time_cost: float = 0.0                  # charged at `month`


class ForcedEvent(BaseModel):
    key: str
    month: int = 0
    duration_months: int = 1
    gross_cost: float = 0.0
    coverage: float = 0.0
    income_loss_fraction: float = 0.0


class SimulationRequest(BaseModel):
    account_id: str
    horizon_months: int = Field(default=60, ge=6, le=360)
    n_paths: int = Field(default=5000, ge=200, le=50000)
    seed: Optional[int] = None
    starting_balance: Optional[float] = None
    risk_keys: Optional[list[str]] = None       # None => all risks
    exclude_risk_keys: list[str] = []
    risk_overrides: dict[str, dict] = {}
    life_events: list[LifeEvent] = []
    forced_events: list[ForcedEvent] = []
    inflation_annual: float = 0.025
    wage_growth_annual: float = 0.03
    ruin_floor: float = 0.0
    profile: dict = {}



class StressTestRequest(BaseModel):
    account_id: str
    scenario_keys: Optional[list[str]] = None
    starting_balance: Optional[float] = None
    horizon_months: int = 36