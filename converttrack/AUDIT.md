# Audit code - Woot fork

Date : 2026-09-16

## Supprime (Safe)

| Element | Raison |
|---------|--------|
| `settings/captain/*` | Route orpheline, doublon Captain Settings sidebar |
| `/api/dashboard` Flask | Endpoint debug sans reference |
| Residus UI ConvertTrack | Phase 1 precedente (routes, i18n, sidebar) |
| Commentaire ConvertTrack dans ChannelItem | Rebrand Woot |

## Consolide

| Element | Action |
|---------|--------|
| Paywall self-hosted | Couche unique `usePolicy.js` + bootstrap Captain |
| Image Docker | `woot:latest` (ex chatwoot-converttrack) |
| Dockerfile Python | PyPI direct (ex wheels --no-index) |

## Keep - ne pas supprimer

| Element | Raison |
|---------|--------|
| `enterprise/` (~556 fichiers) | Backend Captain, SLA, voice EE, etc. |
| `converttrack/` webhook chain | Flux messages production |
| `Voice.vue`, `WhatsappCall.vue` | Reutilisables si reactivation canal |
| Optimisations GlobalConfig/Neon | Perf login/dashboard |
| `ChannelItem`, `Email.vue` customisations | UX self-hosted |

## Enterprise - cartographie

### Utilise (bootstrap + UI)

- Captain : assistants, documents, FAQs, scenarios, tools, copilot
- Feature flags : captain_integration, custom_tools, captain_tasks, channel_*

### Dormant (disponible, non supprime)

- SLA, reporting events, SAML SSO, billing cloud, Shopify, OpenSearch

## Verify restant (non bloquant)

- Tag image : aligner `make docker` si utilise
- Chemin config dashboard vs GlobalConfigService.load (ENV vs DB seed)
