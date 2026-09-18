import logging

from flask import jsonify, request

from app.services.auth import require_converttrack_secret
from app.services.campaign_orchestrator import CampaignOrchestrator
from app.services.chatwoot import ChatwootClient
from app.services.federation import ContactFederationStore
from app.services.workspace_config import WorkspaceConfigStore
from app.services.workspace_setup import setup_workspace
from flask import Blueprint

logger = logging.getLogger(__name__)

workspaces_bp = Blueprint("workspaces", __name__)

VALID_MODES = {"classification", "agentic", "hybrid"}
VALID_TYPES = {"marketing", "support", "reclamations", "custom"}


def _sync_chatwoot_settings(account_id: int, payload: dict) -> None:
    settings = {}
    if "automation_mode" in payload and payload["automation_mode"] in VALID_MODES:
        settings["converttrack_automation_mode"] = payload["automation_mode"]
    if "workspace_type" in payload and payload["workspace_type"] in VALID_TYPES:
        settings["converttrack_workspace_type"] = payload["workspace_type"]
    if "catalog_sources" in payload:
        settings["converttrack_catalog_sources"] = payload["catalog_sources"]

    if settings:
        ChatwootClient(account_id=account_id).update_account_settings(account_id, settings)


@workspaces_bp.post("/api/workspaces/<int:account_id>/setup")
@require_converttrack_secret
def workspace_setup_route(account_id: int):
    payload = request.get_json(silent=True) or {}
    automation_mode = payload.get("automation_mode", "classification")
    workspace_type = payload.get("workspace_type", "custom")
    catalog_sources = payload.get("catalog_sources")

    config = setup_workspace(
        account_id=account_id,
        account_name=payload.get("account_name", ""),
        workspace_type=workspace_type,
        automation_mode=automation_mode,
        catalog_sources=catalog_sources,
    )
    return jsonify({"status": "ok", "account_id": account_id, "config": config}), 200


@workspaces_bp.get("/api/workspaces/<int:account_id>/config")
@require_converttrack_secret
def workspace_config_get(account_id: int):
    config = WorkspaceConfigStore().get(account_id)
    return jsonify({"account_id": account_id, "config": config}), 200


@workspaces_bp.patch("/api/workspaces/<int:account_id>/config")
@require_converttrack_secret
def workspace_config_patch(account_id: int):
    payload = request.get_json(silent=True) or {}
    if payload.get("automation_mode") and payload["automation_mode"] not in VALID_MODES:
        return jsonify({"error": "invalid automation_mode"}), 422
    if payload.get("workspace_type") and payload["workspace_type"] not in VALID_TYPES:
        return jsonify({"error": "invalid workspace_type"}), 422

    config = WorkspaceConfigStore().upsert(account_id, payload)
    try:
        _sync_chatwoot_settings(account_id, payload)
    except Exception as exc:
        logger.warning("Sync Chatwoot settings account %s: %s", account_id, exc)
    return jsonify({"account_id": account_id, "config": config}), 200


@workspaces_bp.get("/api/federation/contacts/<path:contact_key>")
@require_converttrack_secret
def federation_timeline(contact_key: str):
    record = ContactFederationStore().get_timeline(contact_key)
    if not record:
        return jsonify({"error": "contact not found"}), 404
    return jsonify(record), 200


@workspaces_bp.post("/api/workspaces/<int:account_id>/campaigns")
@require_converttrack_secret
def create_multichannel_campaign(account_id: int):
    payload = request.get_json(silent=True) or {}
    channels = payload.get("channels") or []

    if not channels:
        return jsonify({"error": "channels required"}), 422

    try:
        run = CampaignOrchestrator().create_run(
            account_id=account_id,
            name=payload.get("name", "Campagne multicanal"),
            channels=channels,
            audience=payload.get("audience") or {},
            message=payload.get("message", ""),
            scheduled_at=payload.get("scheduled_at"),
        )
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 422

    return jsonify({"status": "created", "campaign_run": run}), 201


@workspaces_bp.get("/api/workspaces/<int:account_id>/campaigns/<run_id>")
@require_converttrack_secret
def get_multichannel_campaign(account_id: int, run_id: str):
    run = CampaignOrchestrator().get_run(account_id, run_id)
    if not run:
        return jsonify({"error": "campaign run not found"}), 404
    return jsonify({"campaign_run": run}), 200
