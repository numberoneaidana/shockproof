"""app/import_router.py — POST /api/accounts/{id}/import"""
from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from app import db
from app.categorizer import categorize, normalize_merchant
from app.models import Txn
from app.statement_import import (
    StatementError, looks_like_transfer, parse_statement_csv, parse_statement_pdf,
)

router = APIRouter()
MAX_BYTES = 10 * 1024 * 1024


def _clear_account_txns(account_id: str) -> None:
    for name in ("delete_txns_for_account", "delete_transactions", "clear_txns", "delete_txns"):
        fn = getattr(db, name, None)
        if fn is not None:
            try:
                fn(account_id)
                return
            except TypeError:
                continue
    raise HTTPException(
        500,
        "app/db.py has no function to delete an account's transactions.",
    )


@router.post("/api/accounts/{account_id}/import")
async def import_statement(
    account_id: str,
    file: UploadFile = File(...),
    replace: bool = Form(False),
    card_account: bool | None = Form(None),
):
    raw = await file.read()
    if len(raw) > MAX_BYTES:
        raise HTTPException(413, "File is larger than 10 MB.")
    if db.get_account(account_id) is None:
        raise HTTPException(404, "account not found")

    fname = (file.filename or "").lower()
    is_pdf = fname.endswith(".pdf") or file.content_type == "application/pdf"

    try:
        if is_pdf:
            rows = parse_statement_pdf(raw, card_account=card_account)
        else:
            rows = parse_statement_csv(raw, card_account=card_account)
    except StatementError as e:
        raise HTTPException(422, str(e))

    transfers = 0
    for r in rows:
        cat, sub, ess = categorize(r["merchant_raw"], r["amount"])
        if looks_like_transfer(r["merchant_raw"]):
            cat, sub, ess = "Transfer", "Transfer", False
            transfers += 1
        r["merchant"] = normalize_merchant(r["merchant_raw"])
        r["category"], r["subcategory"], r["is_essential"] = cat, sub, ess
        r["account_id"] = account_id
        r["pending"] = False

    if replace:
        _clear_account_txns(account_id)

    existing = {t.txn_id for t in db.load_txns(account_id)}
    fresh = [r for r in rows if r["txn_id"] not in existing]

    db.insert_txns([Txn(**r) for r in fresh])

    return {
        "account_id": account_id,
        "rows": len(rows),
        "inserted": len(fresh),
        "skipped_duplicates": len(rows) - len(fresh),
        "transfers_excluded": transfers,
        "first_date": min(r["date"] for r in rows),
        "last_date": max(r["date"] for r in rows),
        "warning": None,
    }