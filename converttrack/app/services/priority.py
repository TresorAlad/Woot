from typing import Any

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
    

def compute_priority(analysis: dict, payload: dict) -> dict[str, Any]:
    intent = analysis.get("intent", "autre")
    pipeline = analysis.get("pipeline_stage", "nouveau")
    confidence = float(analysis.get("confidence", 0.0))
    conversation = payload.get("conversation") or {}
    client_actif = is_active_client(conversation, payload)

    score = 0
    reasons: list[str] = []

    if intent == "prix":
        score += 40
        reasons.append("demande_prix")
    if pipeline == "relance":
        score += 35
        reasons.append("a_relancer")
    if pipeline in ("interet", "prix"):
        score += 25
    if client_actif:
        score += 30
        reasons.append("client_actif")
    if confidence >= 0.85:
        score += 10
    if intent in ("disponibilite", "livraison"):
        score += 15
    if pipeline in ("converti", "perdu"):
        score = min(score, 15)

    if score >= 60:
        level = "haute"
    elif score >= 35:
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
