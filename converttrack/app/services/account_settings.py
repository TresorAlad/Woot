import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

AUTOMATION_MODES = {"classification", "agentic", "hybrid"}
CACHE_TTL_SECONDS = 30


class AccountSettingsService:
    def __init__(self):
        self._cache: dict[int, tuple[float, dict[str, Any]]] = {}

    def fetch_settings(self, account_id: int, client) -> dict[str, Any]:
        cached = self._cache.get(account_id)
        now = time.time()
        if cached and now - cached[0] < CACHE_TTL_SECONDS:
            return cached[1]

        try:
            response = client._request("GET", f"/api/v1/accounts/{account_id}")
            settings = response.json().get("settings") or {}
            self._cache[account_id] = (now, settings)
            return settings
        except Exception as exc:
            logger.warning("Impossible de lire settings account %s: %s", account_id, exc)
            if cached:
                return cached[1]
            return {}

    def get_automation_mode(self, account_id: int, client, inbox_id: int | None = None) -> str:
        settings = self.fetch_settings(account_id, client)
        mode = settings.get("converttrack_automation_mode") or "classification"
        if mode not in AUTOMATION_MODES:
            return "classification"
        return mode

    def invalidate(self, account_id: int) -> None:
        self._cache.pop(account_id, None)


account_settings_service = AccountSettingsService()
