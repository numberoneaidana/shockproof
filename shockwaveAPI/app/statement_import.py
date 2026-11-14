"""app/statement_import.py"""
from __future__ import annotations

import csv
import hashlib
import io
import re
from collections import Counter
from datetime import datetime

DATE_HEADERS = ["transaction date", "posting date", "post date", "posted date", "date"]
DESC_HEADERS = ["description", "details", "payee", "merchant", "name", "memo"]
AMOUNT_HEADERS = ["amount", "transaction amount"]
DEBIT_HEADERS = ["debit", "withdrawal", "withdrawals", "money out"]
CREDIT_HEADERS = ["credit", "deposit", "deposits", "money in"]
DATE_FORMATS = ["%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y", "%m-%d-%Y", "%b %d, %Y", "%b %d"]

TRANSFER_WORDS = re.compile(
    r"(online transfer|transfer to|transfer from|xfer|payment thank you|autopay payment|"
    r"credit card payment|ach pmt|mobile payment|payment - thank)", re.I)


class StatementError(ValueError):
    pass


def _norm(h: str) -> str:
    return re.sub(r"\s+", " ", (h or "").strip().lower())


def _find(headers: list[str], wanted: list[str]) -> int | None:
    normed = [_norm(h) for h in headers]
    for w in wanted:
        if w in normed:
            return normed.index(w)
    return None


def _parse_date(s: str) -> str:
    s = (s or "").strip().replace("–", "-").replace("—", "-").replace(".", "")

    # Handle "Nov -01" -> "Nov 01"
    s = re.sub(r"([A-Z][a-z]{2})-\s*", r"\1 ", s)
    s = re.sub(r"([A-Z][a-z]{2})\s+(\d)", r"\1 \2", s)

    for f in DATE_FORMATS:
        try:
            dt = datetime.strptime(s, f)
            if f == "%b %d":
                dt = dt.replace(year=datetime.now().year)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue

    # Handle MM/DD missing a year
    if len(s) <= 5:
        sep = "/" if "/" in s else ("-" if "-" in s else None)
        if sep:
            parts = s.split(sep)
            if len(parts) == 2 and all(p.isdigit() for p in parts):
                year = datetime.now().year
                month = int(parts[0])
                if month > datetime.now().month:
                    year -= 1
                return f"{year}-{int(parts[0]):02d}-{int(parts[1]):02d}"
    raise ValueError(f"unrecognised date {s!r}")


def _parse_money(s: str) -> float | None:
    s = (s or "").strip()
    if not s:
        return None
    neg = s.startswith("(") and s.endswith(")") or s.startswith("-") or s.endswith("-")
    cleaned = re.sub(r"[^\d.]", "", s)
    if not cleaned:
        return None
    v = float(cleaned)
    return -v if neg else v


def _dedupe(parsed: list[tuple[str, float, str]]) -> list[dict]:
    seen: Counter = Counter()
    out = []
    for date, amt, desc in parsed:
        key = (date, round(amt, 2), desc.lower())
        n = seen[key]
        seen[key] += 1
        tid = hashlib.sha1(f"{date}|{amt:.2f}|{desc.lower()}|{n}".encode()).hexdigest()[:20]
        out.append({"txn_id": f"imp_{tid}", "date": date, "amount": round(amt, 2),
                    "merchant_raw": desc, "pending": False})
    return out


# ---------- CSV ----------

def parse_statement_csv(raw: bytes, *, card_account: bool | None = None) -> list[dict]:
    text = raw.decode("utf-8-sig", errors="replace")
    rows = list(csv.reader(io.StringIO(text)))
    rows = [r for r in rows if any(c.strip() for c in r)]
    if not rows:
        raise StatementError("The file is empty.")

    hi = 0
    for i, row in enumerate(rows[:30]):
        if _find(row, DATE_HEADERS) is not None and (
            _find(row, AMOUNT_HEADERS) is not None
            or (_find(row, DEBIT_HEADERS) is not None and _find(row, CREDIT_HEADERS) is not None)
        ):
            hi = i
            break

    headers, body = rows[hi], rows[hi + 1:]
    d_i = _find(headers, DATE_HEADERS)
    desc_i = _find(headers, DESC_HEADERS)
    amt_i = _find(headers, AMOUNT_HEADERS)
    deb_i = _find(headers, DEBIT_HEADERS)
    cre_i = _find(headers, CREDIT_HEADERS)

    parsed: list[tuple[str, float, str]] = []
    for r in body:
        if len(r) <= max(i for i in (d_i, desc_i, amt_i, deb_i, cre_i) if i is not None):
            continue
        try:
            date = _parse_date(r[d_i])
            if amt_i is not None:
                amt = _parse_money(r[amt_i])
            else:
                debit, credit = _parse_money(r[deb_i]), _parse_money(r[cre_i])
                amt = (abs(credit) if credit else 0.0) - (abs(debit) if debit else 0.0)
                if debit is None and credit is None:
                    amt = None
            if amt is None:
                continue
        except ValueError:
            continue
        parsed.append((date, amt, re.sub(r"\s+", " ", r[desc_i]).strip()))

    if not parsed:
        raise StatementError("Found the table but couldn't read any transactions.")

    if card_account is None and amt_i is not None:
        has_balance = any("balance" in _norm(h) for h in headers)
        has_category = any(_norm(h) == "category" for h in headers)
        positives = sum(1 for _, a, _ in parsed if a > 0)
        card_account = (not has_balance) and has_category and positives > 0.6 * len(parsed)
    if card_account:
        parsed = [(d, -a, m) for d, a, m in parsed]

    return _dedupe(parsed)


# ---------- PDF ----------

def parse_statement_pdf(raw: bytes, *, card_account: bool | None = None) -> list[dict]:
    try:
        import pdfplumber
    except ImportError:
        raise StatementError("PDF support is not installed on the server.")

    try:
        pdf = pdfplumber.open(io.BytesIO(raw))
    except Exception as e:
        raise StatementError(f"Couldn't open PDF: {e}")

    text = ""
    try:
        for page in pdf.pages:
            text += (page.extract_text() or "") + "\n"
    finally:
        pdf.close()

    # Clean HTML tags
    text = re.sub(r"</tr>", "\n", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"[ \t]+", " ", text)

    rows = []
    # Regex supports MM/DD/YYYY and "Nov -01"
    line_re = re.compile(
        r"^\s*([A-Z][a-z]{2}\s*[-–]?\s*\d{1,2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?|\d{4}-\d{2}-\d{2})\s+(.+?)\s+([\(]?\$?-?\d[\d,]*(?:\.\d{2})?[\)]?)(?:\s+[\(]?\$?-?\d[\d,]*(?:\.\d{2})?[\)]?)?\s*$"
    )

    for line in text.split("\n"):
        line = line.strip()
        if not line: continue
        m = line_re.match(line)
        if m:
            date_s, desc_s, amt_s = m.groups()
            try:
                date = _parse_date(date_s)
            except ValueError:
                continue

            amt = _parse_money(amt_s)
            if amt is not None:
                # If it's explicitly negative, keep it. Otherwise, use keywords.
                if amt_s.startswith("-") or amt_s.startswith("("):
                    amt = -abs(amt)
                elif re.search(r"(withdrawal|debit|payment|check|pos|fee|charge)", desc_s, re.I):
                    amt = -abs(amt)
                else:
                    amt = abs(amt)
                rows.append((date, amt, desc_s.strip()))

    if not rows:
        raise StatementError("Couldn't find any transactions in this PDF.")

    if card_account is None:
        positives = sum(1 for _, a, _ in rows if a > 0)
        card_account = positives > 0.6 * len(rows)
    if card_account:
        rows = [(d, -a, m) for d, a, m in rows]

    return _dedupe(rows)


def find_transfers(rows_by_account: dict[str, list[dict]], window_days: int = 3) -> set[str]:
    flat = [(acct, t) for acct, rows in rows_by_account.items() for t in rows]
    inflows: dict[float, list[tuple[str, dict]]] = {}
    for acct, t in flat:
        if t["amount"] > 0:
            inflows.setdefault(round(t["amount"], 2), []).append((acct, t))

    matched: set[str] = set()
    used: set[str] = set()
    for acct, t in flat:
        if t["amount"] >= 0: continue
        d0 = datetime.strptime(t["date"], "%Y-%m-%d")
        for acct2, cand in inflows.get(round(-t["amount"], 2), []):
            if acct2 == acct or cand["txn_id"] in used: continue
            gap = abs((datetime.strptime(cand["date"], "%Y-%m-%d") - d0).days)
            if gap <= window_days:
                matched.update([t["txn_id"], cand["txn_id"]])
                used.add(cand["txn_id"])
                break
    return matched


def looks_like_transfer(desc: str) -> bool:
    return bool(TRANSFER_WORDS.search(desc))