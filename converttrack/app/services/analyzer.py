import json
import logging
from typing import Any

from app.services.rodium import RodiumClient

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """Tu es l'assistant IA de ConvertTrack pour des PME.
Analyse le message client et reponds UNIQUEMENT en JSON valide, sans markdown.
Schema:
{
  "intent": "prix|disponibilite|livraison|info|autre",
  "pipeline_stage": "nouveau|interet|prix|relance|converti|perdu",
  "suggested_reply": "brouillon de reponse en francais",
  "confidence": 0.0
}
Regles:
- intent=prix si le client demande un tarif
- intent=disponibilite si stock/disponibilite
- intent=livraison si delais/expedition
- intent=info pour questions generales
- pipeline_stage=nouveau pour un premier contact
- suggested_reply: courte, professionnelle, en francais
"""

FALLBACK_RESULT = {
    "intent": "autre",
    "pipeline_stage": "nouveau",
    "suggested_reply": "",
    "confidence": 0.0,
}


def analyze_message(message_content: str) -> dict[str, Any]:
    try:
        content = RodiumClient().chat_completion(
            [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": message_content},
            ]
        )

        if content.startswith("```"):
            content = content.strip("`")
            if content.startswith("json"):
                content = content[4:].strip()

        result = json.loads(content)
        return {
            "intent": result.get("intent", "autre"),
            "pipeline_stage": result.get("pipeline_stage", "nouveau"),
            "suggested_reply": result.get("suggested_reply", ""),
            "confidence": float(result.get("confidence", 0.0)),
        }
    except Exception as exc:
        logger.warning("Analyse LLM fallback: %s", exc)
        return dict(FALLBACK_RESULT)
