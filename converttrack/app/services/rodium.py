import requests
from flask import current_app


class RodiumClient:
    def chat_completion(self, messages: list[dict], *, temperature: float = 0.2, max_tokens: int = 500) -> str:
        api_key = current_app.config["RODIUMAI_API_KEY"]
        if not api_key:
            raise ValueError("RODIUMAI_API_KEY manquant")

        url = f"{current_app.config['RODIUMAI_BASE_URL']}/chat/completions"
        payload = {
            "model": current_app.config["RODIUMAI_MODEL"],
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        response = requests.post(url, json=payload, headers=headers, timeout=30)
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"].strip()
