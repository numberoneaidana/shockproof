from __future__ import annotations

from typing import Optional

import httpx

from .config import PLAID_BASE, PLAID_CLIENT_ID, PLAID_SECRET


class PlaidClient:
    """Thin async wrapper. Falls back to mock mode when keys are absent."""

    def __init__(self) -> None:
        self.enabled = bool(PLAID_CLIENT_ID and PLAID_SECRET)

    async def _post(self, path: str, payload: dict) -> dict:
        async with httpx.AsyncClient(timeout=20) as client:
            r = await client.post(
                f"{PLAID_BASE}{path}",
                json={"client_id": PLAID_CLIENT_ID, "secret": PLAID_SECRET, **payload},
            )
            r.raise_for_status()
            return r.json()

    async def create_link_token(self, user_id: str) -> dict:
        if not self.enabled:
            return {"link_token": f"link-sandbox-mock-{user_id}", "mock": True}
        return await self._post(
            "/link/token/create",
            {
                "user": {"client_user_id": user_id},
                "client_name": "Budget Shock Simulator",
                "products": ["transactions"],
                "country_codes": ["US"],
                "language": "en",
            },
        )

    async def exchange_public_token(self, public_token: str) -> dict:
        if not self.enabled:
            return {"access_token": f"access-sandbox-mock-{public_token}", "item_id": "mock-item"}
        return await self._post("/item/public_token/exchange", {"public_token": public_token})

    async def sync_transactions(self, access_token: str, cursor: Optional[str]) -> dict:
        if not self.enabled:
            raise RuntimeError("Plaid not configured; use mock ingestion.")
        return await self._post(
            "/transactions/sync",
            {"access_token": access_token, "cursor": cursor or "", "count": 500},
        )


plaid = PlaidClient()