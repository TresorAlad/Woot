import json
import logging
import os

import requests
from flask import current_app

from app.services.account_settings import account_settings_service
from app.services.priority import (
    compute_priority,
    resolve_assignee_env_keys,
    resolve_assignee_from_config,
)
from app.services.workspace_config import WorkspaceConfigStore

logger = logging.getLogger(__name__)

INTENT_LABELS = {
    "prix": "intent-prix",
    "disponibilite": "intent-disponibilite",
    "livraison": "intent-livraison",
    "info": "intent-info",
    "autre": "intent-autre",
}

PIPELINE_LABELS = {
    "nouveau": "pipeline-nouveau",
    "interet": "pipeline-interet",
    "prix": "pipeline-prix",
    "relance": "pipeline-relance",
    "converti": "pipeline-converti",
    "perdu": "pipeline-perdu",
}

TOKEN_PATH = os.getenv("CHATWOOT_API_TOKEN_PATH", "/shared/chatwoot_api_token")
ACCOUNT_TOKENS_PATH = os.getenv("ACCOUNT_TOKENS_PATH", "/shared/account_tokens.json")


class ChatwootClient:
    def __init__(self, account_id: int | None = None):
        self.base_url = current_app.config["CHATWOOT_BASE_URL"]
        self.account_id = account_id
        self.token = self._resolve_token(account_id)

    @staticmethod
    def _read_token_file(path: str) -> str:
        if os.path.isfile(path):
            return open(path, encoding="utf-8").read().strip()
        return ""

    @classmethod
    def _resolve_token(cls, account_id: int | None) -> str:
        env_token = current_app.config.get("CHATWOOT_API_TOKEN") or os.getenv("CHATWOOT_API_TOKEN", "")
        if env_token:
            return env_token

        file_token = cls._read_token_file(TOKEN_PATH)
        if file_token:
            current_app.config["CHATWOOT_API_TOKEN"] = file_token
            return file_token

        if account_id and os.path.isfile(ACCOUNT_TOKENS_PATH):
            try:
                tokens = json.loads(open(ACCOUNT_TOKENS_PATH, encoding="utf-8").read())
                account_token = tokens.get(str(account_id), "")
                if account_token:
                    return account_token
            except (json.JSONDecodeError, OSError) as exc:
                logger.warning("Impossible de lire %s: %s", ACCOUNT_TOKENS_PATH, exc)

        return ""

    @property
    def _headers(self):
        token = self.token or self._resolve_token(self.account_id)
        return {
            "api_access_token": token,
            "Content-Type": "application/json",
        }

    def _request(self, method: str, path: str, **kwargs):
        token = self.token or self._resolve_token(self.account_id)
        if not token:
            raise ValueError("CHATWOOT_API_TOKEN manquant")

        self.token = token
        url = f"{self.base_url}{path}"
        response = requests.request(method, url, headers=self._headers, timeout=15, **kwargs)
        response.raise_for_status()
        return response

    def update_account_settings(self, account_id: int, settings: dict):
        self._request("PATCH", f"/api/v1/accounts/{account_id}", json=settings)
        account_settings_service.invalidate(account_id)

    def update_labels(self, account_id: int, conversation_id: int, labels: list[str]):
        self._request(
            "POST",
            f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/labels",
            json={"labels": labels},
        )

    def add_private_note(self, account_id: int, conversation_id: int, content: str):
        self._request(
            "POST",
            f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages",
            json={"content": content, "private": True},
        )

    def assign_agent(self, account_id: int, conversation_id: int, assignee_id: int):
        self._request(
            "POST",
            f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/assignments",
            json={"assignee_id": assignee_id},
        )

    def set_priority(self, account_id: int, conversation_id: int, priority: str):
        self._request(
            "POST",
            f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/toggle_priority",
            json={"priority": priority},
        )

    def create_campaign(self, account_id: int, payload: dict) -> dict:
        response = self._request("POST", f"/api/v1/accounts/{account_id}/campaigns", json=payload)
        return response.json()

    def _read_default_agent_id(self) -> int | None:
        path = os.getenv("DEFAULT_AGENT_ID_PATH", "/shared/default_agent_id")
        if os.path.isfile(path):
            value = open(path, encoding="utf-8").read().strip()
            if value.isdigit():
                return int(value)
        return None

    def resolve_assignee_id(self, account_id: int, analysis: dict) -> int | None:
        config_assignee = resolve_assignee_from_config(account_id, analysis)
        if config_assignee:
            return config_assignee

        for env_key in resolve_assignee_env_keys(analysis):
            raw = os.getenv(env_key, "").strip()
            if raw.isdigit():
                return int(raw)

        default_id = self._read_default_agent_id()
        if default_id:
            return default_id

        response = self._request("GET", f"/api/v1/accounts/{account_id}/agents")
        agents = response.json()
        if not agents:
            return None
        return agents[0]["id"]

    def apply_analysis(self, account_id: int, conversation_id: int, analysis: dict, payload: dict | None = None):
        payload = payload or {}
        client = ChatwootClient(account_id=account_id)
        config = WorkspaceConfigStore().get(account_id)
        automation_mode = account_settings_service.get_automation_mode(account_id, client)

        priority = compute_priority(analysis, payload, account_id=account_id)

        intent = analysis.get("intent", "autre")
        stage = analysis.get("pipeline_stage", "nouveau")
        labels = [
            INTENT_LABELS.get(intent, "intent-autre"),
            PIPELINE_LABELS.get(stage, "pipeline-nouveau"),
            priority["priority_label"],
        ]
        client.update_labels(account_id, conversation_id, labels)
        client.set_priority(account_id, conversation_id, priority["chatwoot_priority"])

        assignee_id = client.resolve_assignee_id(account_id, analysis)
        if assignee_id:
            client.assign_agent(account_id, conversation_id, assignee_id)

        reasons = ", ".join(priority["priority_reasons"]) or "aucune"
        note = (
            "ConvertTrack IA\n"
            f"Workspace: {config.get('account_name') or account_id}\n"
            f"Mode: {automation_mode}\n"
            f"Intent: {intent}\n"
            f"Pipeline: {stage}\n"
            f"Priorite: {priority['priority']} (score {priority['priority_score']})\n"
            f"Client actif: {'oui' if priority['client_actif'] else 'non'}\n"
            f"Signaux: {reasons}\n"
            f"Confiance: {analysis.get('confidence', 0.0)}\n"
        )
        if assignee_id:
            note += f"Assigne a l'agent #{assignee_id}\n"
        note += f"\nSuggestion:\n{analysis.get('suggested_reply', '')}"

        try:
            client.add_private_note(account_id, conversation_id, note)
        except Exception as exc:
            logger.warning("Note privee non ajoutee: %s", exc)

        return {
            **analysis,
            **priority,
            "assignee_id": assignee_id,
            "automation_mode": automation_mode,
            "auto_sent": False,
        }
