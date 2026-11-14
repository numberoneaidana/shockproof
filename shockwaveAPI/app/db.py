from __future__ import annotations

import sqlite3
from datetime import date
from typing import Iterable

from .config import DB_PATH
from .models import Txn

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id          TEXT PRIMARY KEY,
    item_id     TEXT,
    access_token TEXT,
    institution TEXT,
    cursor      TEXT,
    created_at  TEXT
);
CREATE TABLE IF NOT EXISTS transactions (
    account_id   TEXT NOT NULL,
    txn_id       TEXT NOT NULL,
    date         TEXT NOT NULL,
    amount       REAL NOT NULL,
    merchant_raw TEXT,
    merchant     TEXT,
    category     TEXT,
    subcategory  TEXT,
    is_essential INTEGER,
    pending      INTEGER,
    PRIMARY KEY (account_id, txn_id)
);
CREATE INDEX IF NOT EXISTS idx_txn_account_date
    ON transactions(account_id, date);
"""


def conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB_PATH, check_same_thread=False)
    c.row_factory = sqlite3.Row
    return c


def init_db() -> None:
    with conn() as c:
        c.executescript(SCHEMA)


def upsert_account(account_id: str, item_id: str = "", access_token: str = "",
                   institution: str = "", cursor: str = "") -> None:
    with conn() as c:
        c.execute(
            """INSERT INTO accounts (id, item_id, access_token, institution, cursor, created_at)
               VALUES (?,?,?,?,?,datetime('now'))
               ON CONFLICT(id) DO UPDATE SET
                 item_id=excluded.item_id,
                 access_token=COALESCE(NULLIF(excluded.access_token,''), accounts.access_token),
                 institution=COALESCE(NULLIF(excluded.institution,''), accounts.institution),
                 cursor=COALESCE(NULLIF(excluded.cursor,''), accounts.cursor)""",
            (account_id, item_id, access_token, institution, cursor),
        )


def get_account(account_id: str) -> sqlite3.Row | None:
    with conn() as c:
        return c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()


def set_cursor(account_id: str, cursor: str) -> None:
    with conn() as c:
        c.execute("UPDATE accounts SET cursor=? WHERE id=?", (cursor, account_id))


def insert_txns(txns: Iterable[Txn]) -> int:
    rows = [
        (t.account_id, t.txn_id, t.date.isoformat(), t.amount, t.merchant_raw,
         t.merchant, t.category, t.subcategory, int(t.is_essential), int(t.pending))
        for t in txns
    ]
    if not rows:
        return 0
    with conn() as c:
        before = c.total_changes
        c.executemany(
            """INSERT OR IGNORE INTO transactions
               (account_id, txn_id, date, amount, merchant_raw, merchant,
                category, subcategory, is_essential, pending)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            rows,
        )
        return c.total_changes - before


def delete_txns_for_account(account_id: str) -> int:
    import sqlite3
    # WARNING: Make sure this matches the DB_PATH used at the top of your db.py!
    conn = sqlite3.connect("shockproof.db")
    cur = conn.cursor()

    # Automatically find the correct table name
    table_name = "transactions"
    tables = ["transactions", "txns", "bank_txns", "mock_txns", "bank_transactions", "txn"]

    # Check which table actually exists in this database
    cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
    existing_tables = [row[0] for row in cur.fetchall()]

    for t in tables:
        if t in existing_tables:
            table_name = t
            break

    try:
        cur.execute(f"DELETE FROM {table_name} WHERE account_id = ?", (account_id,))
        n = cur.rowcount
        conn.commit()
        return n
    except Exception as e:
        print(f"Error deleting from {table_name}: {e}")
        return 0
    finally:
        conn.close()


def load_txns(account_id: str) -> list[Txn]:
    with conn() as c:
        rows = c.execute(
            "SELECT * FROM transactions WHERE account_id=? ORDER BY date", (account_id,)
        ).fetchall()
    return [
        Txn(
            txn_id=r["txn_id"],
            account_id=r["account_id"],
            date=date.fromisoformat(r["date"]),
            amount=r["amount"],
            merchant_raw=r["merchant_raw"] or "",
            merchant=r["merchant"] or "",
            category=r["category"] or "Uncategorized",
            subcategory=r["subcategory"] or "",
            is_essential=bool(r["is_essential"]),
            pending=bool(r["pending"]),
        )
        for r in rows
    ]