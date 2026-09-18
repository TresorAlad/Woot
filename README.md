# Woot

Plateforme de support client self-hosted, basee sur Chatwoot, avec Captain (IA) et le moteur ConvertTrack (webhook Python).

## Stack production

| Service | Role |
|---------|------|
| **rails** | API + dashboard (port 3000) |
| **sidekiq** | Jobs async |
| **redis** | Cache + queues |
| **converttrack** | Webhook Flask (port 5000) - analyse, labels, priorites, config multi-workspace |
| **converttrack-setup** | Bootstrap plateforme idempotent (features, labels, webhooks) |

Base de donnees : PostgreSQL (Neon recommande en production).

## Demarrage rapide (Docker)

```bash
cp .env.example .env          # configurer Neon, Redis, secrets
cp converttrack/.env.example converttrack/.env

docker build -f docker/Dockerfile -t woot:latest .
docker compose -f docker-compose.production.yaml up -d
```

Bootstrap automatique au premier demarrage via `converttrack-setup`.

## Workspaces multi-departement

Chaque **workspace (Account)** est un espace isole :

- Toutes les capacites sont actives des l'installation (Captain, canaux, ConvertTrack)
- A la creation, labels + webhook ConvertTrack sont configures automatiquement
- Chaque workspace connecte **ses propres providers** (WhatsApp, Facebook, Instagram, email)
- Les agents n'accedent qu'aux workspaces ou le proprietaire les a invites

Guide complet : [converttrack/docs/WORKSPACES.md](converttrack/docs/WORKSPACES.md)

## Modes IA

| Mode | Description |
|------|-------------|
| **classification** | IA classe et suggere, l'equipe valide (defaut) |
| **agentic** | Captain repond automatiquement |
| **hybrid** | Auto-reponse si confiance elevee, sinon suggestion |

## Rebuild frontend uniquement

Apres modification Vue/JS :

```bash
./converttrack/scripts/rebuild-chatwoot-ui.sh
```

## Flux messages ConvertTrack

```
Canal (widget, email, etc.) -> Chatwoot -> webhook ConvertTrack -> labels/notes/priorite API
```

Page test widget : `http://127.0.0.1:5000/test`

## Captain

Interface IA dans le dashboard : Overview, FAQs, Documents, Scenarios, Playground, Inboxes, Tools, Settings.

Backend Captain : dossier `enterprise/` (Enterprise Edition Chatwoot).

Outil **Product Lookup** : interroge les catalogues produits configures par workspace.

## API ConvertTrack

| Endpoint | Role |
|----------|------|
| `POST /api/workspaces/:id/setup` | Initialiser config workspace |
| `GET/PATCH /api/workspaces/:id/config` | Lire/modifier config (mode IA, priorites) |
| `GET /api/federation/contacts/:key` | Timeline client cross-workspaces |
| `POST /api/workspaces/:id/campaigns` | Creer campagne multicanal |

## Licence

Ce projet derive de [Chatwoot](https://github.com/chatwoot/chatwoot) (MIT). Voir [LICENSE](LICENSE) et [NOTICE](NOTICE).
