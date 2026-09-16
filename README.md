# Woot

Plateforme de support client self-hosted, basee sur Chatwoot, avec Captain (IA) et le moteur ConvertTrack (webhook Python).

## Stack production

| Service | Role |
|---------|------|
| **rails** | API + dashboard (port 3000) |
| **sidekiq** | Jobs async |
| **redis** | Cache + queues |
| **converttrack** | Webhook Flask (port 5000) - analyse messages, labels, priorites |
| **converttrack-setup** | Bootstrap idempotent (labels, webhook, inbox, Captain) |

Base de donnees : PostgreSQL (Neon recommande en production).

## Demarrage rapide (Docker)

```bash
cp .env.example .env          # configurer Neon, Redis, secrets
cp converttrack/.env.example converttrack/.env

docker build -f docker/Dockerfile -t woot:latest .
docker compose -f docker-compose.production.yaml up -d
```

Bootstrap automatique au premier demarrage via `converttrack-setup`.

## Rebuild frontend uniquement

Apres modification Vue/JS :

```bash
./converttrack/scripts/rebuild-chatwoot-ui.sh
```

## Flux messages ConvertTrack

```
Canal (widget, email, etc.) -> Chatwoot -> webhook ConvertTrack -> labels/notes API
```

Page test widget : `http://127.0.0.1:5000/test`

## Captain

Interface IA dans le dashboard : Overview, FAQs, Documents, Scenarios, Playground, Inboxes, Tools, Settings.

Backend Captain : dossier `enterprise/` (Enterprise Edition Chatwoot).

## Licence

Ce projet derive de [Chatwoot](https://github.com/chatwoot/chatwoot) (MIT). Voir [LICENSE](LICENSE) et [NOTICE](NOTICE).
