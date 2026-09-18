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

    WORKSPACE_CONFIG_PATH = os.getenv("WORKSPACE_CONFIG_PATH", "/shared/workspace_configs.json")
    FEDERATION_STORE_PATH = os.getenv("FEDERATION_STORE_PATH", "/shared/federated_contacts.json")
    CAMPAIGN_RUNS_PATH = os.getenv("CAMPAIGN_RUNS_PATH", "/shared/campaign_runs.json")
    ACCOUNT_TOKENS_PATH = os.getenv("ACCOUNT_TOKENS_PATH", "/shared/account_tokens.json")
    CHATWOOT_API_TOKEN_PATH = os.getenv("CHATWOOT_API_TOKEN_PATH", "/shared/chatwoot_api_token")
