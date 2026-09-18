import logging
import os
from copy import deepcopy
from typing import Any

from app.services.json_file_store import read_json, write_json

logger = logging.getLogger(__name__)

DEFAULT_CONFIG: dict[str, Any] = {
    "workspace_type": "custom",
    "automation_mode": "classification",
    "priority_weights": {
        "intent_prix": 40,
        "pipeline_relance": 35,
        "pipeline_interet_prix": 25,
        "client_actif": 30,
        "high_confidence": 10,
        "intent_logistics": 15,
        "converted_lost_cap": 15,
    },
    "priority_thresholds": {
        "haute": 60,
        "moyenne": 35,
    },
    "assignee_agents": {},
    "catalog_sources": [],
    "inbox_automation_modes": {},
    "hybrid_confidence_threshold": 0.85,
}

WORKSPACE_TYPES = {
    "marketing": {
        "workspace_type": "marketing",
        "priority_weights": {
            "intent_prix": 45,
            "pipeline_relance": 30,
            "pipeline_interet_prix": 30,
            "client_actif": 25,
            "high_confidence": 10,
            "intent_logistics": 10,
            "converted_lost_cap": 15,
        },
    },
    "support": {
        "workspace_type": "support",
        "priority_weights": {
            "intent_prix": 20,
            "pipeline_relance": 25,
            "pipeline_interet_prix": 20,
            "client_actif": 35,
            "high_confidence": 10,
            "intent_logistics": 25,
            "converted_lost_cap": 15,
        },
    },
    "reclamations": {
        "workspace_type": "reclamations",
        "priority_weights": {
            "intent_prix": 15,
            "pipeline_relance": 40,
            "pipeline_interet_prix": 20,
            "client_actif": 35,
            "high_confidence": 10,
            "intent_logistics": 20,
            "converted_lost_cap": 10,
        },
    },
}


class WorkspaceConfigStore:
    def __init__(self, path: str | None = None):
        self.path = path or os.getenv("WORKSPACE_CONFIG_PATH", "/shared/workspace_configs.json")

    def _load(self) -> dict[str, dict[str, Any]]:
        return read_json(self.path, {})

    def _save(self, data: dict[str, dict[str, Any]]) -> None:
        write_json(self.path, data)

    def get(self, account_id: int) -> dict[str, Any]:
        key = str(account_id)
        stored = deepcopy(self._load().get(key, {}))
        config = deepcopy(DEFAULT_CONFIG)
        config.update(stored)
        return config

    def upsert(self, account_id: int, updates: dict[str, Any]) -> dict[str, Any]:
        data = self._load()
        key = str(account_id)
        current = deepcopy(DEFAULT_CONFIG)
        current.update(data.get(key, {}))
        current.update(updates)
        data[key] = current
        self._save(data)
        return current

    def setup_workspace(
        self,
        account_id: int,
        account_name: str = "",
        workspace_type: str = "custom",
        automation_mode: str = "classification",
        catalog_sources: list[str] | None = None,
    ) -> dict[str, Any]:
        template = WORKSPACE_TYPES.get(workspace_type, {})
        updates = {
            "account_name": account_name,
            "workspace_type": template.get("workspace_type", workspace_type),
            "automation_mode": automation_mode,
        }
        if catalog_sources is not None:
            updates["catalog_sources"] = catalog_sources
        if "priority_weights" in template:
            updates["priority_weights"] = template["priority_weights"]
        return self.upsert(account_id, updates)
