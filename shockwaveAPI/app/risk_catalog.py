from __future__ import annotations

import math
from dataclasses import dataclass, field, asdict


@dataclass
class RiskEvent:
    key: str
    label: str
    category: str
    annual_probability: float        # chance per year the event occurs at least once
    median_cost: float               # gross cost, before insurance
    p90_cost: float                  # 90th-percentile gross cost
    coverage: float                  # fraction covered by insurance / benefits
    duration_months_mean: float      # how long the impact lasts
    income_loss_fraction: float      # fraction of monthly income lost during duration
    correlation_group: str
    essential: bool = True

    @property
    def mu(self) -> float:
        return math.log(max(self.median_cost, 1.0))

    @property
    def sigma(self) -> float:
        if self.p90_cost <= self.median_cost:
            return 0.5
        return (math.log(self.p90_cost) - math.log(max(self.median_cost, 1.0))) / 1.2816

    def to_dict(self) -> dict:
        d = asdict(self)
        d["mu"] = round(self.mu, 3)
        d["sigma"] = round(self.sigma, 3)
        return d


RISK_CATALOG: list[RiskEvent] = [
    # ---------------- Health ----------------
    RiskEvent("medical_er_visit", "ER visit / urgent care", "Health", 0.18, 1800, 9000, 0.80, 1, 0.15, "health"),
    RiskEvent("hospitalization", "Hospitalization / surgery", "Health",
              0.025, 10000, 35000, 0.85, 2, 0.30, "health"),
    RiskEvent("chronic_illness", "New chronic illness", "Health", 0.02, 8000, 40000, 0.80, 12, 0.20, "health"),
    RiskEvent("mental_health_crisis", "Mental health crisis", "Health", 0.03, 4000, 20000, 0.80, 2, 0.30, "health"),
    RiskEvent("pregnancy_birth", "Pregnancy / childbirth", "Health", 0.04, 5000, 15000, 0.85, 1, 0.20, "health"),
    RiskEvent("dental_vision", "Dental / vision procedure", "Health", 0.35, 600, 4000, 0.40, 1, 0.0, "health", essential=False),
    RiskEvent("long_term_care", "Long-term care need", "Health",
              0.0008, 60000, 150000, 0.40, 12, 0.0, "health"),
    RiskEvent("disability_short_term", "Short-term disability", "Health", 0.05, 3000, 12000, 0.50, 4, 0.50, "health"),

    # ---------------- Income ----------------
    RiskEvent("layoff", "Layoff / job loss", "Income",
              0.07, 0, 0, 0.0, 4, 1.00, "income"),
    RiskEvent("furlough_reduced_hours", "Furlough / reduced hours", "Income", 0.08, 0, 0, 0.0, 3, 0.35, "income"),
    RiskEvent("business_income_drop", "Business / gig income drop", "Income",
              0.02, 0, 0, 0.0, 6, 0.50, "income"),
    RiskEvent("death_of_earner", "Death of earner", "Income", 0.004, 15000, 40000, 0.30, 12, 1.00, "income"),

    # ---------------- Property ----------------
    RiskEvent("home_repair_major", "Major home repair (roof/HVAC)", "Property", 0.12, 3500, 15000, 0.30, 1, 0.0, "property"),
    RiskEvent("appliance_failure", "Appliance failure", "Property", 0.25, 800, 3500, 0.10, 1, 0.0, "property", essential=False),
    RiskEvent("water_damage_flood", "Water damage / flood", "Property", 0.03, 20000, 90000, 0.35, 4, 0.0, "property"),
    RiskEvent("house_fire", "House fire", "Property",
              0.002, 50000, 150000, 0.85, 6, 0.15, "property"),
    RiskEvent("hurricane", "Hurricane / major storm", "Property", 0.04, 15000, 70000, 0.60, 3, 0.10, "property"),
    RiskEvent("wildfire", "Wildfire", "Property",
              0.002, 20000, 60000, 0.70, 4, 0.10, "property"),
    RiskEvent("earthquake", "Earthquake", "Property",
              0.001, 30000, 100000, 0.40, 6, 0.10, "property"),
    RiskEvent("theft_burglary", "Theft / burglary", "Property", 0.02, 3000, 15000, 0.60, 1, 0.0, "property", essential=False),
    RiskEvent("hoa_special_assessment", "HOA / condo special assessment", "Property",
              0.02, 5000, 20000, 0.0, 1, 0.0, "property"),
    # ---------------- Transportation ----------------
    RiskEvent("auto_accident", "Auto accident", "Transportation", 0.06, 4000, 20000, 0.70, 1, 0.10, "property"),
    RiskEvent("auto_repair_major", "Major auto repair", "Transportation", 0.15, 1500, 6000, 0.20, 1, 0.0, "property"),
    RiskEvent("vehicle_theft", "Vehicle theft", "Transportation", 0.005, 12000, 35000, 0.80, 1, 0.05, "property"),

    # ---------------- Legal / admin ----------------
    RiskEvent("lawsuit_liability", "Lawsuit / liability claim", "Legal",
              0.003, 8000, 40000, 0.50, 6, 0.0, "legal"),
    RiskEvent("irs_tax_bill", "IRS audit / back taxes", "Legal", 0.06, 3000, 20000, 0.0, 1, 0.0, "legal"),
    RiskEvent("identity_theft", "Identity theft / fraud", "Legal", 0.05, 1200, 8000, 0.30, 2, 0.0, "legal", essential=False),

    # ---------------- Systemic ----------------
    RiskEvent("recession_income_shock", "Recession income shock", "Systemic",
              0.08, 0, 0, 0.0, 9, 0.30, "systemic"),
    RiskEvent("inflation_spike", "Inflation spike", "Systemic", 0.15, 2400, 8000, 0.0, 12, 0.0, "systemic"),
    RiskEvent("interest_rate_spike", "Interest-rate spike (variable debt)", "Systemic", 0.10, 1800, 6000, 0.0, 12, 0.0, "systemic"),
    RiskEvent("government_shutdown", "Gov shutdown / benefit delay", "Systemic", 0.05, 2000, 7000, 0.30, 2, 0.30, "systemic", essential=False),

    # ---------------- Family / personal ----------------
    RiskEvent("divorce", "Divorce / separation", "Personal",
              0.008, 12000, 35000, 0.0, 6, 0.10, "personal"),
    RiskEvent("childcare_disruption", "Childcare disruption", "Personal", 0.05, 2500, 9000, 0.10, 3, 0.10, "personal"),
    RiskEvent("eldercare", "Eldercare responsibility", "Personal", 0.04, 6000, 30000, 0.10, 12, 0.0, "personal"),
    RiskEvent("pet_emergency", "Pet medical emergency", "Personal", 0.10, 1500, 6000, 0.20, 1, 0.0, "personal", essential=False),

    # ---------------- Environment / cyber ----------------
    RiskEvent("utility_outage", "Extended utility outage", "Environment", 0.05, 400, 2000, 0.0, 1, 0.0, "systemic", essential=False),
    RiskEvent("fraud_scam", "Fraud / scam loss", "Cyber", 0.08, 900, 6000, 0.30, 1, 0.0, "legal", essential=False),
]

RISK_BY_KEY: dict[str, RiskEvent] = {r.key: r for r in RISK_CATALOG}

# Within-group correlation (how tightly events in the same group co-occur)
RHO_WITHIN = {
    "health": 0.40,
    "income": 0.55,
    "property": 0.45,
    "legal": 0.30,
    "systemic": 0.50,
    "personal": 0.25,
}

# Cross-group correlation matrix
GROUPS = ["health", "income", "property", "legal", "systemic", "personal"]
GROUP_CORR = {
    ("health", "income"): 0.20,
    ("health", "systemic"): 0.15,
    ("health", "property"): 0.05,
    ("health", "legal"): 0.10,
    ("health", "personal"): 0.10,
    ("income", "systemic"): 0.45,
    ("income", "property"): 0.20,
    ("income", "legal"): 0.10,
    ("income", "personal"): 0.20,
    ("property", "systemic"): 0.25,
    ("property", "legal"): 0.10,
    ("property", "personal"): 0.05,
    ("legal", "systemic"): 0.10,
    ("legal", "personal"): 0.15,
    ("systemic", "personal"): 0.15,
}


def group_corr_matrix() -> "np.ndarray":  # noqa: F821
    import numpy as np
    n = len(GROUPS)
    C = np.eye(n)
    for i, a in enumerate(GROUPS):
        for j, b in enumerate(GROUPS):
            if i >= j:
                continue
            r = GROUP_CORR.get((a, b), GROUP_CORR.get((b, a), 0.10))
            C[i, j] = C[j, i] = r
    return C