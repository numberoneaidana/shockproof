from __future__ import annotations

import uuid
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app import db
from app.cashflow import build_baseline, daily_forecast
from app.categorizer import categorize, normalize_merchant
from app.config import DEFAULT_HORIZON_MONTHS, DEFAULT_N_PATHS
from app.mock_data import generate
from app.models import (
    CashflowBaseline, RecurringSeries, SimulationRequest, StressTestRequest,
)
from app.plaid_client import plaid
from app.recurrence import detect_recurring
from app.risk_catalog import RISK_BY_KEY, RISK_CATALOG
from app.simulation import STRESS_SCENARIOS, run_simulation

app = FastAPI(title="Budget Shock Simulator", version="1.0.0")
from .import_router import router as import_router
app.include_router(import_router)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

# Run schema init at import time so every entrypoint
# (uvicorn, TestClient, pytest, scripts) has tables ready.
db.init_db()


@app.on_event("startup")
def _startup() -> None:
    db.init_db()


# --------------------------------------------------------------------------
# Health & catalog
# --------------------------------------------------------------------------

@app.get("/health")
def health() -> dict:
    return {"ok": True, "plaid_live": plaid.enabled}


@app.get("/api/risks")
def list_risks(category: Optional[str] = Query(default=None)) -> dict:
    items = [r.to_dict() for r in RISK_CATALOG
             if category is None or r.category.lower() == category.lower()]
    return {
        "count": len(items),
        "categories": sorted({r.category for r in RISK_CATALOG}),
        "risks": items,
    }


# --------------------------------------------------------------------------
# Layer 1 — linking & ingestion
# --------------------------------------------------------------------------

class ExchangeBody(BaseModel):
    public_token: str
    institution: str = "Mock Bank"
    account_id: Optional[str] = None


@app.post("/api/link/create")
async def create_link(user_id: str = "demo-user") -> dict:
    return await plaid.create_link_token(user_id)


@app.post("/api/link/exchange")
async def exchange(body: ExchangeBody) -> dict:
    if plaid.enabled:
        res = await plaid.exchange_public_token(body.public_token)
        access_token, item_id = res["access_token"], res["item_id"]
    else:
        access_token, item_id = f"access-sandbox-mock-{uuid.uuid4().hex[:8]}", "mock-item"

    account_id = body.account_id or f"acct_{uuid.uuid4().hex[:10]}"
    db.upsert_account(account_id, item_id, access_token, body.institution)
    return {"account_id": account_id, "item_id": item_id, "mock": not plaid.enabled}


@app.post("/api/accounts/{account_id}/sync")
async def sync(account_id: str, months: int = Query(default=14, ge=3, le=36)) -> dict:
    acct = db.get_account(account_id)
    if acct is None:
        raise HTTPException(404, "account not found")

    if plaid.enabled:
        res = await plaid.sync_transactions(acct["access_token"], acct["cursor"])
        raw = res.get("added", [])
        txns = []
        for t in raw:
            cat, sub, ess = categorize(t.get("merchant_name") or t["name"], -t["amount"])
            txns.append({
                "txn_id": t["transaction_id"],
                "account_id": account_id,
                "date": t["date"],
                "amount": -t["amount"],
                "merchant_raw": t.get("merchant_name") or t["name"],
                "merchant": normalize_merchant(t.get("merchant_name") or t["name"]),
                "category": cat, "subcategory": sub,
                "is_essential": ess, "pending": t.get("pending", False),
            })
        from .models import Txn
        txns = [Txn(**x) for x in txns]
        db.set_cursor(account_id, res.get("next_cursor", ""))
    else:
        txns = generate(account_id, months=months)

    inserted = db.insert_txns(txns)
    return {"account_id": account_id, "fetched": len(txns), "inserted": inserted}


# --------------------------------------------------------------------------
# Layer 1 — derived profile
# --------------------------------------------------------------------------

def _profile(account_id: str) -> tuple[CashflowBaseline, list[RecurringSeries]]:
    txns = db.load_txns(account_id)
    if not txns:
        raise HTTPException(400, "no transactions; call /sync first")

    # categorize on read (handles rows inserted before rules changed)
    for t in txns:
        if t.category == "Uncategorized":
            t.category, t.subcategory, t.is_essential = categorize(t.merchant_raw, t.amount)
        if not t.merchant:
            t.merchant = normalize_merchant(t.merchant_raw)
    txns = [t for t in txns if t.category != "Transfer"]
    recurring = detect_recurring(txns)

    # Liquid balance proxy: most recent month's net + a configurable buffer.
    # (In production: pull real balances from /accounts/balance/get.)
    liquid = 8500.0
    return build_baseline(txns, recurring, liquid), recurring


@app.get("/api/accounts/{account_id}/profile")
def profile(account_id: str) -> dict:
    baseline, recurring = _profile(account_id)
    forecast = daily_forecast(
        recurring, baseline.monthly_variable_mean, baseline.monthly_variable_std,
        baseline.liquid_balance, days=60,
    )
    return {
        "baseline": baseline.model_dump(),
        "recurring": [r.model_dump(mode="json") for r in recurring],
        "overdraft_forecast": forecast,
    }


@app.get("/api/accounts/{account_id}/recurring")
def recurring_only(account_id: str) -> dict:
    _, recurring = _profile(account_id)
    return {"count": len(recurring),
            "series": [r.model_dump(mode="json") for r in recurring]}


@app.get("/api/accounts/{account_id}/transactions")
def transactions(account_id: str, limit: int = 200) -> dict:
    txns = db.load_txns(account_id)[-limit:]
    return {"count": len(txns), "transactions": [t.model_dump(mode="json") for t in txns]}


# --------------------------------------------------------------------------
# Layer 2 — simulation
# --------------------------------------------------------------------------

@app.post("/api/simulate")
def simulate(req: SimulationRequest) -> dict:
    baseline, _ = _profile(req.account_id)

    if req.n_paths == DEFAULT_N_PATHS and req.horizon_months == 60:
        pass  # defaults already applied by pydantic

    result = run_simulation(baseline, req)
    result["inputs"] = {
        "account_id": req.account_id,
        "life_events": [le.model_dump() for le in req.life_events],
        "forced_events": [fe.model_dump() for fe in req.forced_events],
        "risks_included": len(req.risk_keys) if req.risk_keys else len(RISK_CATALOG),
        "risks_excluded": req.exclude_risk_keys,
    }
    return result


@app.post("/api/stress-test")
def stress_test(req: StressTestRequest) -> dict:
    baseline, _ = _profile(req.account_id)
    keys = req.scenario_keys or list(STRESS_SCENARIOS)

    out = []
    for key in keys:
        sc = STRESS_SCENARIOS.get(key)
        if sc is None:
            continue

        life_events = []
        for le in sc.get("life_events", []):
            le = dict(le)
            if "expense_delta_pct_of_fixed" in le:
                pct = le.pop("expense_delta_pct_of_fixed")
                le["expense_delta"] = baseline.monthly_fixed * pct
            from .models import LifeEvent
            life_events.append(LifeEvent(**le))

        from .models import ForcedEvent
        forced = [ForcedEvent(**e) for e in sc.get("events", [])]

        sim_req = SimulationRequest(
            account_id=req.account_id,
            horizon_months=req.horizon_months,
            n_paths=800,
            seed=42,
            starting_balance=req.starting_balance,
            life_events=life_events,
            forced_events=forced,
            risk_keys=[],             # isolate the scenario
        )
        res = run_simulation(baseline, sim_req)
        s = res["summary"]
        out.append({
            "key": key,
            "label": sc["label"],
            "probability_of_ruin": s["probability_of_ruin"],
            "median_end_balance": s["median_end_balance"],
            "p5_end_balance": s["p5_end_balance"],
            "median_min_balance": s["median_min_balance"],
            "median_months_to_ruin": s["median_months_to_ruin"],
        })

    out.sort(key=lambda x: -x["probability_of_ruin"])
    return {"scenarios": out}