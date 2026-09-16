import logging
import os

import requests
from flask import current_app

from app.services.priority import compute_priority, resolve_assignee_env_keys

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


class ChatwootClient:
    def __init__(self):
        self.base_url = current_app.config["CHATWOOT_BASE_URL"]
        self.token = current_app.config["CHATWOOT_API_TOKEN"]

    @property
    def _headers(self):
        return {
            "api_access_token": self.token,
            "Content-Type": "application/json",
        }

    def _request(self, method: str, path: str, **kwargs):
        if not self.token:
            raise ValueError("CHATWOOT_API_TOKEN manquant")

        url = f"{self.base_url}{path}"
        response = requests.request(method, url, headers=self._headers, timeout=15, **kwargs)
        response.raise_for_status()
        return response

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

    def _read_default_agent_id(self) -> int | None:
        path = os.getenv("DEFAULT_AGENT_ID_PATH", "/shared/default_agent_id")
        if os.path.isfile(path):
            value = open(path, encoding="utf-8").read().strip()
            if value.isdigit():
                return int(value)
        return None

    def resolve_assignee_id(self, account_id: int, analysis: dict) -> int | None:
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
        priority = compute_priority(analysis, payload)

        intent = analysis.get("intent", "autre")
        stage = analysis.get("pipeline_stage", "nouveau")
        labels = [
            INTENT_LABELS.get(intent, "intent-autre"),
            PIPELINE_LABELS.get(stage, "pipeline-nouveau"),
            priority["priority_label"],
        ]
        self.update_labels(account_id, conversation_id, labels)
        self.set_priority(account_id, conversation_id, priority["chatwoot_priority"])

        assignee_id = self.resolve_assignee_id(account_id, analysis)
        if assignee_id:
            self.assign_agent(account_id, conversation_id, assignee_id)

        reasons = ", ".join(priority["priority_reasons"]) or "aucune"
        note = (
            "ConvertTrack IA\n"
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
            self.add_private_note(account_id, conversation_id, note)
        except Exception as exc:
            logger.warning("Note privée non ajoutée: %s", exc)

        return {
            **analysis,
            **priority,
            "assignee_id": assignee_id,
        }
