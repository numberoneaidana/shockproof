from __future__ import annotations

import re

# (category, subcategory, essential, [regex patterns])
RULES: list[tuple[str, str, bool, list[str]]] = [
    ("Income", "Paycheck", True, [r"payroll", r"direct dep", r"dir dep", r"\badp\b",
                                  r"gusto", r"paychex", r"salary", r"employer"]),
    ("Housing", "Rent", True, [r"\brent\b", r"apartment", r"property mgmt",
                               r"leasing", r"skyline", r"realty"]),
    ("Housing", "Mortgage", True, [r"mortgage", r"loan serv", r"wells fargo home"]),
    ("Housing", "Utilities", True, [r"power", r"electric", r"water dept", r"utility",
                                    r"energy", r"gas company"]),
    ("Housing", "Internet", True, [r"comcast", r"xfinity", r"spectrum", r"fios", r"centurylink"]),
    ("Housing", "Phone", True, [r"t-mobile", r"tmobile", r"verizon wireless", r"at&t wireless",
                                r"mint mobile", r"cricket"]),
    ("Insurance", "Auto", True, [r"geico", r"state farm", r"progressive", r"allstate",
                                 r"auto ins", r"auto insurance"]),
    ("Insurance", "Home/Renters", True, [r"renters", r"homeowners", r"lemonade", r"homesite"]),
    ("Insurance", "Health", True, [r"health ins", r"blue cross", r"aetna", r"cigna",
                                   r"unitedhealth", r"kaiser"]),
    ("Groceries", "Groceries", True, [r"whole foods", r"trader joe", r"kroger", r"safeway",
                                      r"\baldi\b", r"costco", r"grocery", r"supermarket",
                                      r"publix", r"wegmans", r"food lion"]),
    ("Transportation", "Fuel", True, [r"\bshell\b", r"chevron", r"exxon", r"\bbp\b",
                                      r"speedway", r"gas station", r"circle k"]),
    ("Transportation", "Rideshare/Transit", False, [r"\buber\b", r"lyft", r"metro",
                                                    r"transit", r"parking", r"toll"]),
    ("Transportation", "Auto Maintenance", False, [r"autozone", r"jiffy lube", r"firestone",
                                                   r"discount tire", r"mechanic", r"midas"]),
    ("Food & Dining", "Restaurants", False, [r"restaurant", r"starbucks", r"chipotle",
                                             r"mcdonald", r"doordash", r"grubhub",
                                             r"uber eats", r"cafe", r"pizza", r"taco",
                                             r"deli", r"bakery"]),
    ("Subscriptions", "Streaming", False, [r"netflix", r"hulu", r"disney", r"spotify",
                                           r"\bhbo\b", r"max\.com", r"youtube premium",
                                           r"icloud", r"apple\.com/bill", r"audible"]),
    ("Subscriptions", "Software", False, [r"adobe", r"notion", r"openai", r"chatgpt", r"github"]),
    ("Health", "Medical", True, [r"clinic", r"hospital", r"pharmacy", r"\bcvs\b",
                                 r"walgreens", r"dental", r"medical", r"labcorp",
                                 r"urgent care", r"optometry"]),
    ("Health", "Fitness", False, [r"\bgym\b", r"planet fitness", r"peloton", r"equinox",
                                  r"crossfit", r"yoga"]),
    ("Shopping", "General Merchandise", False, [r"amazon", r"target", r"\bwalmart\b",
                                                r"best buy", r"ebay", r"etsy", r"ikea"]),
    ("Personal", "Pets", False, [r"petco", r"petsmart", r"\bvet\b", r"chewy", r"banfield"]),
    ("Financial", "Fees/Interest", True, [r"\bfee\b", r"interest charge", r"service charge",
                                          r"overdraft", r"atm fee"]),
    ("Financial", "Transfers", False, [r"transfer", r"zelle", r"venmo", r"cash app",
                                       r"payment to"]),
    ("Legal/Admin", "Government", True, [r"\bdmv\b", r"\birs\b", r"\btax\b", r"city of",
                                         r"county", r"registration", r"passport"]),
    ("Entertainment", "Leisure", False, [r"\bamc\b", r"ticketmaster", r"steam",
                                         r"playstation", r"nintendo", r"concert"]),
]

_COMPILED = [
    (cat, sub, ess, [re.compile(p, re.I) for p in pats])
    for cat, sub, ess, pats in RULES
]

_PREFIX_JUNK = re.compile(
    r"\b(pos|debit|credit|card|purchase|authorized|on|payment|ach|ppd|web|id|xxxxxxxx\d*)\b",
    re.I,
)
_NON_ALNUM = re.compile(r"[^a-z0-9&+ ]+")
_DIGITS = re.compile(r"\d+")


def normalize_merchant(raw: str) -> str:
    """Turn a raw bank descriptor into a stable merchant key."""
    s = raw.lower()
    s = _PREFIX_JUNK.sub(" ", s)
    s = _DIGITS.sub(" ", s)
    s = _NON_ALNUM.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s or raw.lower().strip()


def categorize(raw: str, amount: float) -> tuple[str, str, bool]:
    """Return (category, subcategory, is_essential)."""
    key = normalize_merchant(raw)
    for cat, sub, ess, pats in _COMPILED:
        for p in pats:
            if p.search(key):
                # Guard: don't tag refunds / reversals as income
                if cat == "Income" and amount < 0:
                    continue
                return cat, sub, ess
    return ("Income", "Other", True) if amount > 0 else ("Uncategorized", "Other", False)