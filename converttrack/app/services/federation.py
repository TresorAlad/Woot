import logging
import os
from typing import Any

from app.services.json_file_store import read_json, write_json

logger = logging.getLogger(__name__)


class ContactFederationStore:
    def __init__(self, path: str | None = None):
        self.path = path or os.getenv("FEDERATION_STORE_PATH", "/shared/federated_contacts.json")

    def _load(self) -> dict[str, dict[str, Any]]:
        return read_json(self.path, {})

    def _save(self, data: dict[str, dict[str, Any]]) -> None:
        write_json(self.path, data)

    @staticmethod
    def _contact_key(payload: dict) -> str | None:
        sender = payload.get("sender") or {}
        conversation = payload.get("conversation") or {}
        meta_sender = (conversation.get("meta") or {}).get("sender") or {}

        for candidate in (
            sender.get("phone_number"),
            meta_sender.get("phone_number"),
            sender.get("email"),
            meta_sender.get("email"),
            sender.get("identifier"),
            meta_sender.get("identifier"),
        ):
            if candidate:
                return str(candidate).strip().lower()
        return None

    def record_event(self, account_id: int, payload: dict, analysis: dict | None = None) -> str | None:
        key = self._contact_key(payload)
        if not key:
            return None

        data = self._load()
        record = data.get(key, {
            "contact_key": key,
            "account_contacts": {},
            "timeline": [],
        })

        conversation = payload.get("conversation") or {}
        contact_id = (conversation.get("meta") or {}).get("sender", {}).get("id")
        account_contacts = record.setdefault("account_contacts", {})
        account_contacts[str(account_id)] = {
            "contact_id": contact_id,
            "conversation_id": conversation.get("id"),
        }

        event = {
            "account_id": account_id,
            "conversation_id": conversation.get("id"),
            "intent": (analysis or {}).get("intent"),
            "pipeline_stage": (analysis or {}).get("pipeline_stage"),
            "content_preview": (payload.get("content") or "")[:200],
        }
        record.setdefault("timeline", []).append(event)
        record["timeline"] = record["timeline"][-100:]
        data[key] = record
        self._save(data)
        return key

    def get_timeline(self, contact_key: str) -> dict[str, Any] | None:
        return self._load().get(contact_key.lower())
