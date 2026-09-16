import os

from dotenv import load_dotenv

load_dotenv()


class Config:
    RODIUMAI_API_KEY = os.getenv("RODIUMAI_API_KEY", "")
    RODIUMAI_BASE_URL = os.getenv("RODIUMAI_BASE_URL", "https://api.rodiumai.io/v1")
    RODIUMAI_MODEL = os.getenv("RODIUMAI_MODEL", "mistral/ministral-3-14b-instruct")

    CHATWOOT_BASE_URL = os.getenv("CHATWOOT_BASE_URL", "http://127.0.0.1:3000").rstrip("/")
    CHATWOOT_API_TOKEN = os.getenv("CHATWOOT_API_TOKEN", "")

    WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")
