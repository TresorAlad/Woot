import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any

from app.services.chatwoot import ChatwootClient
from app.services.json_file_store import read_json, write_json

logger = logging.getLogger(__name__)


class CampaignOrchestrator:
    """Orchestrateur multicanal : cree un CampaignRun et declenche les campagnes Chatwoot."""

    SUPPORTED_CHANNELS = {"whatsapp", "sms", "email", "facebook", "instagram", "website"}

    CHANNEL_INBOX_TYPE = {
        "whatsapp": "Channel::Whatsapp",
        "sms": "Channel::Sms",
        "email": "Channel::Email",
        "facebook": "Channel::FacebookPage",
        "instagram": "Channel::Instagram",
        "website": "Channel::WebWidget",
    }

    def __init__(self, path: str | None = None):
        self.path = path or os.getenv("CAMPAIGN_RUNS_PATH", "/shared/campaign_runs.json")

    def _load(self) -> dict[str, list[dict[str, Any]]]:
        return read_json(self.path, {})

    def _save(self, data: dict[str, list[dict[str, Any]]]) -> None:
        write_json(self.path, data)

    def _find_run(self, data: dict, account_id: int, run_id: str) -> tuple[int, dict[str, Any]] | None:
        runs = data.get(str(account_id), [])
        for index, run in enumerate(runs):
            if run.get("id") == run_id:
                return index, run
        return None

    def create_run(
        self,
        account_id: int,
        name: str,
        channels: list[dict[str, Any]],
        audience: dict[str, Any],
        message: str = "",
        scheduled_at: str | None = None,
    ) -> dict[str, Any]:
        normalized_channels = []
        for channel in channels:
            channel_type = (channel.get("type") or "").lower()
            if channel_type not in self.SUPPORTED_CHANNELS:
                raise ValueError(f"Canal non supporte: {channel_type}")
            normalized_channels.append({
                "type": channel_type,
                "inbox_id": channel.get("inbox_id"),
                "template_params": channel.get("template_params"),
                "status": "pending",
            })

        run = {
            "id": str(uuid.uuid4()),
            "account_id": account_id,
            "name": name,
            "message": message,
            "audience": audience,
            "channels": normalized_channels,
            "status": "processing",
            "scheduled_at": scheduled_at,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

        self.process_run(account_id, run)
        return run

    def process_run(self, account_id: int, run: dict[str, Any]) -> None:
        data = self._load()
        key = str(account_id)
        client = ChatwootClient(account_id=account_id)
        audience = run.get("audience") or {}
        label_ids = audience.get("labels")

        for channel in run["channels"]:
            inbox_id = channel.get("inbox_id")
            if not inbox_id:
                channel["status"] = "failed"
                channel["error"] = "inbox_id required"
                continue

            payload = {
                "title": run["name"],
                "message": run.get("message", ""),
                "inbox_id": inbox_id,
                "campaign_type": "one_off",
                "enabled": True,
            }
            if label_ids:
                payload["audience"] = [{"type": "Label", "id": label_id} for label_id in label_ids]
            if run.get("scheduled_at"):
                payload["scheduled_at"] = run["scheduled_at"]

            try:
                result = client.create_campaign(account_id, payload)
                channel["status"] = "queued"
                channel["campaign_id"] = result.get("id")
            except Exception as exc:
                logger.warning("Campagne %s inbox %s echouee: %s", run["id"], inbox_id, exc)
                channel["status"] = "failed"
                channel["error"] = str(exc)

        statuses = [channel["status"] for channel in run["channels"]]
        if all(status == "failed" for status in statuses):
            run["status"] = "failed"
        elif any(status == "queued" for status in statuses):
            run["status"] = "queued"
        else:
            run["status"] = "processing"

        existing = self._find_run(data, account_id, run["id"])
        if existing:
            index, _ = existing
            data[key][index] = run
        else:
            data.setdefault(key, []).append(run)
        self._save(data)

    def get_run(self, account_id: int, run_id: str) -> dict[str, Any] | None:
        match = self._find_run(self._load(), account_id, run_id)
        return match[1] if match else None
