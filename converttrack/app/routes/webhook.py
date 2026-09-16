import hashlib
import hmac
import logging

from flask import Blueprint, current_app, jsonify, request

from app.services.analyzer import analyze_message
from app.services.chatwoot import ChatwootClient

logger = logging.getLogger(__name__)

webhook_bp = Blueprint("webhook", __name__)


def verify_signature(raw_body: bytes) -> bool:
    secret = current_app.config.get("WEBHOOK_SECRET", "")
    if not secret:
        return True

    timestamp = request.headers.get("X-Chatwoot-Timestamp", "")
    signature = request.headers.get("X-Chatwoot-Signature", "")
    if not timestamp or not signature:
        return False

    expected = hmac.new(
        secret.encode("utf-8"),
        f"{timestamp}.{raw_body.decode('utf-8')}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    provided = signature.replace("sha256=", "")
    return hmac.compare_digest(expected, provided)


def should_process(payload: dict) -> bool:
    if payload.get("event") != "message_created":
        return False
    if payload.get("message_type") != "incoming":
        return False
    if payload.get("private"):
        return False
    if not payload.get("content"):
        return False
    return True


@webhook_bp.post("/webhook/chatwoot")
def chatwoot_webhook():
    raw_body = request.get_data()

    if not verify_signature(raw_body):
        logger.warning("Signature webhook Chatwoot invalide")
        return jsonify({"error": "invalid signature"}), 401

    payload = request.get_json(silent=True) or {}
    if not should_process(payload):
        return jsonify({"status": "ignored"}), 200

    conversation = payload.get("conversation") or {}
    account = payload.get("account") or conversation.get("account") or {}
    account_id = account.get("id") or conversation.get("account_id")
    conversation_id = conversation.get("id")

    if not account_id or not conversation_id:
        logger.warning("Payload incomplet: account_id=%s conversation_id=%s", account_id, conversation_id)
        return jsonify({"error": "missing ids"}), 422

    try:
        analysis = analyze_message(payload["content"])
        result = ChatwootClient().apply_analysis(
            int(account_id), int(conversation_id), analysis, payload
        )
        return jsonify({"status": "processed", "analysis": result}), 200
    except Exception as exc:
        logger.exception("Erreur traitement webhook: %s", exc)
        return jsonify({"error": str(exc)}), 500
