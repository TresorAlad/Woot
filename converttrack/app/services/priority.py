from typing import Any

from app.services.workspace_config import WorkspaceConfigStore

PRIORITY_LABELS = {
    "haute": "priorite-haute",
    "moyenne": "priorite-moyenne",
    "basse": "priorite-basse",
}

CHATWOOT_PRIORITY = {
    "haute": "urgent",
    "moyenne": "medium",
    "basse": "low",
}

INTENT_AGENT_ENV = {
    "prix": "CONVERTTRACK_AGENT_COMMERCIAL",
    "disponibilite": "CONVERTTRACK_AGENT_SUPPORT",
    "livraison": "CONVERTTRACK_AGENT_SUPPORT",
    "info": "CONVERTTRACK_AGENT_DEFAULT",
    "autre": "CONVERTTRACK_AGENT_DEFAULT",
}

PIPELINE_AGENT_ENV = {
    "relance": "CONVERTTRACK_AGENT_RELANCE",
    "prix": "CONVERTTRACK_AGENT_COMMERCIAL",
    "interet": "CONVERTTRACK_AGENT_COMMERCIAL",
}


def is_active_client(conversation: dict, payload: dict) -> bool:
    if conversation.get("first_reply_created_at"):
        return True
    if (conversation.get("unread_count") or 0) > 1:
        return True
    messages = conversation.get("messages") or []
    if len(messages) > 1:
        return True
    sender = (conversation.get("meta") or {}).get("sender") or payload.get("sender") or {}
    return bool(sender.get("last_activity_at"))


def compute_priority(analysis: dict, payload: dict, account_id: int | None = None) -> dict[str, Any]:
    intent = analysis.get("intent", "autre")
    pipeline = analysis.get("pipeline_stage", "nouveau")
    confidence = float(analysis.get("confidence", 0.0))
    conversation = payload.get("conversation") or {}
    client_actif = is_active_client(conversation, payload)

    weights = WorkspaceConfigStore().get(account_id or 0)["priority_weights"]
    thresholds = WorkspaceConfigStore().get(account_id or 0)["priority_thresholds"]

    score = 0
    reasons: list[str] = []

    if intent == "prix":
        score += weights.get("intent_prix", 40)
        reasons.append("demande_prix")
    if pipeline == "relance":
        score += weights.get("pipeline_relance", 35)
        reasons.append("a_relancer")
    if pipeline in ("interet", "prix"):
        score += weights.get("pipeline_interet_prix", 25)
    if client_actif:
        score += weights.get("client_actif", 30)
        reasons.append("client_actif")
    if confidence >= 0.85:
        score += weights.get("high_confidence", 10)
    if intent in ("disponibilite", "livraison"):
        score += weights.get("intent_logistics", 15)
    if pipeline in ("converti", "perdu"):
        score = min(score, weights.get("converted_lost_cap", 15))

    haute_threshold = thresholds.get("haute", 60)
    moyenne_threshold = thresholds.get("moyenne", 35)

    if score >= haute_threshold:
        level = "haute"
    elif score >= moyenne_threshold:
        level = "moyenne"
    else:
        level = "basse"

    return {
        "priority": level,
        "priority_score": score,
        "priority_reasons": reasons,
        "client_actif": client_actif,
        "priority_label": PRIORITY_LABELS[level],
        "chatwoot_priority": CHATWOOT_PRIORITY[level],
    }


def resolve_assignee_env_keys(analysis: dict) -> list[str]:
    pipeline = analysis.get("pipeline_stage", "nouveau")
    intent = analysis.get("intent", "autre")
    keys: list[str] = []

    pipeline_key = PIPELINE_AGENT_ENV.get(pipeline)
    if pipeline_key:
        keys.append(pipeline_key)

    intent_key = INTENT_AGENT_ENV.get(intent)
    if intent_key and intent_key not in keys:
        keys.append(intent_key)

    keys.append("CONVERTTRACK_AGENT_DEFAULT")
    return keys


def resolve_assignee_from_config(account_id: int, analysis: dict) -> int | None:
    config = WorkspaceConfigStore().get(account_id)
    assignees = config.get("assignee_agents") or {}

    for key in ("pipeline", "intent", "default"):
        if key == "pipeline":
            agent_id = assignees.get(analysis.get("pipeline_stage", ""))
        elif key == "intent":
            agent_id = assignees.get(analysis.get("intent", ""))
        else:
            agent_id = assignees.get("default")
        if agent_id:
            return int(agent_id)
    return None
