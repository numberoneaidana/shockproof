from __future__ import annotations

import random
from datetime import date, timedelta

from .models import Txn


def generate(account_id: str, months: int = 14, seed: int = 7) -> list[Txn]:
    """Generate a realistic 14-month US household transaction history."""
    rng = random.Random(seed)
    today = date.today()
    start = date(today.year, today.month, 1) - timedelta(days=30 * months)
    txns: list[Txn] = []

    def add(d: date, amt: float, raw: str) -> None:
        if d > today:
            return
        txns.append(
            Txn(
                txn_id=f"mock-{len(txns):06d}",
                account_id=account_id,
                date=d,
                amount=round(amt, 2),
                merchant_raw=raw,
            )
        )

    # --- Paychecks: biweekly Fridays, $3,180 net ---
    d = start
    while d.weekday() != 4:
        d += timedelta(days=1)
    while d <= today:
        add(d, 3180.00 + rng.uniform(-15, 15), "ACME CORP DIRECT DEP PAYROLL")
        d += timedelta(days=14)

    # --- Month-anchored recurring bills ---
    cursor = date(start.year, start.month, 1)
    while cursor <= today:
        y, m = cursor.year, cursor.month
        add(date(y, m, 1), -1850.00, "SKYLINE APARTMENTS RENT PAYMENT")
        add(date(y, m, 5), -15.49, "NETFLIX.COM")
        add(date(y, m, 8), -11.99, "SPOTIFY USA")
        add(date(y, m, 9), -39.99, "PLANET FITNESS")
        add(date(y, m, 12), -75.00 + rng.uniform(-8, 8), "COMCAST XFINITY INTERNET")
        add(date(y, m, 15), -210.00 + rng.uniform(-90, 140), "CITY POWER & LIGHT UTILITY")
        add(date(y, m, 18), -85.00, "T-MOBILE WIRELESS")
        add(date(y, m, 22), -2.99, "APPLE.COM/BILL ICLOUD")
        # groceries: ~4 trips/month
        for week in range(4):
            day = 3 + week * 7 + rng.randint(-1, 2)
            try:
                add(date(y, m, day), -rng.uniform(65, 145),
                    rng.choice(["WHOLE FOODS MKT", "TRADER JOE'S", "KROGER #4412"]))
            except ValueError:
                pass
        # gas / transit
        for _ in range(rng.randint(2, 5)):
            day = rng.randint(1, 28)
            add(date(y, m, day), -rng.uniform(28, 68),
                rng.choice(["SHELL OIL 57443", "CHEVRON 0091882", "UBER TRIP"]))
        # dining
        for _ in range(rng.randint(3, 8)):
            day = rng.randint(1, 28)
            add(date(y, m, day), -rng.uniform(9, 62),
                rng.choice(["STARBUCKS STORE 1234", "CHIPOTLE 0881",
                            "DOORDASH*THAI PALACE", "MCDONALD'S F1122"]))
        # shopping
        for _ in range(rng.randint(1, 4)):
            day = rng.randint(1, 28)
            add(date(y, m, day), -rng.uniform(18, 160),
                rng.choice(["AMAZON MKTPLACE PMTS", "TARGET 00021883", "IKEA BROOKLYN"]))
        # occasional medical copay
        if rng.random() < 0.25:
            add(date(y, m, rng.randint(1, 28)), -rng.uniform(20, 180),
                rng.choice(["CVS/PHARMACY #04412", "URGENT CARE OF AMERICA",
                            "DOWNTOWN DENTAL ASSOC"]))
        # occasional car repair
        if rng.random() < 0.12:
            add(date(y, m, rng.randint(1, 28)), -rng.uniform(180, 900),
                "FIRESTONE COMPLETE AUTO CARE")

        # 6-month auto insurance premium ("the random $612")
        if m in (1, 7):
            add(date(y, m, 15), -612.00, "GEICO AUTO INSURANCE PREMIUM")
        # annual car registration
        if m == 4:
            add(date(y, m, 20), -215.00, "NY STATE DMV REGISTRATION FEE")
        # annual renters insurance
        if m == 9:
            add(date(y, m, 2), -184.00, "LEMONADE RENTERS INSURANCE")

        cursor = date(y + (m == 12), (m % 12) + 1, 1)

    txns.sort(key=lambda t: t.date)
    return txns