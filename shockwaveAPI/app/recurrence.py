from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from statistics import median

import numpy as np

from .models import RecurringSeries, Txn

# cadence -> (expected gap days, gap tolerance, occurrences per month)
CADENCES: list[tuple[str, float, float, float]] = [
    ("weekly", 7.0, 1.5, 52 / 12),
    ("biweekly", 14.0, 2.5, 26 / 12),
    ("semimonthly", 15.2, 2.5, 2.0),
    ("monthly", 30.4, 4.5, 1.0),
    ("quarterly", 91.3, 12.0, 4 / 12),
    ("semiannual", 182.6, 22.0, 2 / 12),
    ("annual", 365.25, 40.0, 1 / 12),
]

MIN_OCCURRENCES = {
    "weekly": 4, "biweekly": 4, "semimonthly": 4,
    "monthly": 3, "quarterly": 2, "semiannual": 2, "annual": 2,
}


def _snap_day(d: date, day: int) -> date:
    """Return the date in d's month closest to `day` (clamped to month end)."""
    import calendar
    last = calendar.monthrange(d.year, d.month)[1]
    return date(d.year, d.month, max(1, min(day, last)))


def _detect_cadence(dates: list[date], amounts: np.ndarray) -> tuple[str, float, float]:
    """Return (cadence, median_gap, gap_cv)."""
    gaps = np.array([(dates[i + 1] - dates[i]).days for i in range(len(dates) - 1)], dtype=float)
    gaps = gaps[gaps > 0]
    if gaps.size == 0:
        return "irregular", 0.0, 1.0

    med_gap = float(np.median(gaps))
    gap_cv = float(np.std(gaps) / med_gap) if med_gap else 1.0

    # Semimonthly detection: day-of-month clusters on two anchors (e.g. 1 & 15)
    doms = sorted({d.day for d in dates})
    if len(doms) >= 2:
        clusters = [d for d in doms if any(abs(d - a) <= 3 for a in (1, 15))]
        if len(clusters) >= 2 and 15 <= med_gap <= 19:
            return "semimonthly", med_gap, gap_cv

    for name, expected, tol, _ in CADENCES:
        if name == "semimonthly":
            continue
        if abs(med_gap - expected) <= tol:
            return name, med_gap, gap_cv

    return "irregular", med_gap, gap_cv


def detect_recurring(txns: list[Txn], min_confidence: float = 0.55) -> list[RecurringSeries]:
    groups: dict[str, list[Txn]] = defaultdict(list)
    for t in txns:
        if t.pending:
            continue
        groups[t.merchant or t.merchant_raw].append(t)

    out: list[RecurringSeries] = []

    for merchant, items in groups.items():
        if len(items) < 2:
            continue

        items.sort(key=lambda x: x.date)
        dates = [i.date for i in items]
        amounts = np.array([i.amount for i in items], dtype=float)
        abs_amts = np.abs(amounts)

        # Require consistent direction (all income or all expense)
        signs = {a > 0 for a in amounts}
        if len(signs) != 1:
            continue

        cadence, med_gap, gap_cv = _detect_cadence(dates, amounts)
        if cadence == "irregular":
            continue
        if len(items) < MIN_OCCURRENCES.get(cadence, 3):
            continue

        mean_amt = float(np.mean(amounts))
        cv_amt = float(np.std(abs_amts) / np.mean(abs_amts)) if np.mean(abs_amts) else 1.0

        conf = (
            min(1.0, len(items) / 6.0) * 0.40
            + (1.0 - min(gap_cv / 0.35, 1.0)) * 0.35
            + (1.0 - min(cv_amt / 0.60, 1.0)) * 0.25
        )
        if conf < min_confidence:
            continue

        per_month = next(c[3] for c in CADENCES if c[0] == cadence)
        last = dates[-1]

        if cadence == "monthly":
            anchor_day = int(round(median([d.day for d in dates])))
            nxt = _snap_day(last + timedelta(days=int(round(med_gap))), anchor_day)
        elif cadence == "semimonthly":
            # next anchor = 1st or 15th after last
            candidates = [d for d in (_snap_day(last, 1), _snap_day(last, 15)) if d > last]
            nxt = min(candidates) if candidates else last + timedelta(days=15)
        else:
            nxt = last + timedelta(days=int(round(med_gap)))

        sample = items[-1]
        out.append(
            RecurringSeries(
                merchant=merchant,
                label=merchant.title(),
                category=sample.category,
                cadence=cadence,  # type: ignore[arg-type]
                avg_amount=round(mean_amt, 2),
                amount_cv=round(cv_amt, 3),
                occurrences=len(items),
                monthly_equivalent=round(mean_amt * per_month, 2),
                last_date=last,
                next_expected=nxt,
                confidence=round(conf, 3),
                is_income=mean_amt > 0,
                essential=sample.is_essential,
            )
        )

    out.sort(key=lambda r: (-abs(r.monthly_equivalent), -r.confidence))
    return out