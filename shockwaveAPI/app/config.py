import os

PLAID_CLIENT_ID = os.getenv("PLAID_CLIENT_ID", "")
PLAID_SECRET = os.getenv("PLAID_SECRET", "")
PLAID_ENV = os.getenv("PLAID_ENV", "sandbox")
PLAID_BASE = {
    "sandbox": "https://sandbox.plaid.com",
    "production": "https://production.plaid.com",
}.get(PLAID_ENV, "https://sandbox.plaid.com")

DB_PATH = os.getenv("DB_PATH", "budget_shock.db")
DEFAULT_N_PATHS = int(os.getenv("DEFAULT_N_PATHS", "5000"))
DEFAULT_HORIZON_MONTHS = int(os.getenv("DEFAULT_HORIZON_MONTHS", "60"))