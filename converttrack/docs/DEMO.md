# Demo mockups ConvertTrack

Jeux de donnees demo pour presentation produit, sans APIs Meta/WhatsApp reelles.

## Compte cible

Uniquement le workspace ou `admin@techmentor.dev` est administrateur.

La demo est centree sur ce compte :
- InboxMember sur toutes les inboxes Demo
- ~45 % des conversations assignees a l admin (75 % des conv live)
- Captain Copilot actif des le debut du seed
- Onglet **Conversations → Moi** et **My Inbox** alimentes pour l admin

Patch rapide sur donnees existantes :

```bash
docker exec chatwoot-rails-1 env CONVERTTRACK_DEMO_EMAIL=admin@techmentor.dev \
  bundle exec rails runner /app/converttrack/scripts/patch_demo_admin.rb
```

## Lancer le seed

```bash
CONVERTTRACK_DEMO_SEED=true \
CONVERTTRACK_DEMO_EMAIL=admin@techmentor.dev \
bundle exec rake converttrack:seed_demo
```

Docker :

```bash
docker exec chatwoot-rails-1 env CONVERTTRACK_DEMO_SEED=true \
  bundle exec rails runner /app/converttrack/scripts/seed_demo.rb
```

## Contenu genere

| Element | Volume |
|---------|--------|
| Agents demo | 5 (emails `@demo.converttrack.local`, non connectables) |
| Contacts | 100 (profils, labels, attributs custom, notes) |
| Conversations classifiees | 500 (fils avec repliques, labels ConvertTrack) |
| Conversations Captain | 200 |
| Inboxes mock | WhatsApp, Email, SMS, Site Web Demo |
| Campagnes | 3 |
| Catalogue produits | `/converttrack/demo_catalog.json` |

## Timeline

- Historique sur 90 jours (rapports)
- Semaine recente
- Conversations live (dernieres minutes) avec echanges en chaine

## Preserve au re-seed

- Settings `converttrack_*`
- Labels intent/pipeline/priorite
- Inbox interne ConvertTrack (`converttrack_demo_inbox_id`)
- Webhook ConvertTrack
- Compte admin principal

## Captain Playground et Rodium

Source unique des secrets IA : `converttrack/.env` (`RODIUMAI_API_KEY`, `RODIUMAI_MODEL`, `RODIUMAI_BASE_URL`).

Au demarrage, Rails synchronise ces variables vers Captain (`InstallationConfig`) :
- Playground, copilot, embeddings
- Service ConvertTrack Python (analyse, campagnes)

Apres changement de cle dans `.env` :

```bash
docker compose -f docker-compose.production.yaml up -d converttrack rails sidekiq
```

Sync manuelle si besoin :

```bash
docker exec chatwoot-rails-1 bundle exec rails runner /app/converttrack/scripts/configure_captain_rodium.rb
```

Apres un patch ou un seed partiel, relancer `patch_demo_admin.rb` pour ajouter les 14 FAQs et 4 documents demo.

## Depannage UI

- **Chargement lent / liste vide (My Inbox, Conversations)** : avec PostgreSQL Neon distant, chaque requete ajoute ~250 ms de latence reseau. L API depasse le timeout Rack (15 s par defaut) avant d afficher la liste. Le compose production utilise `RACK_TIMEOUT_SERVICE_TIMEOUT=60`. Recreer le conteneur rails apres changement : `docker compose -f docker-compose.production.yaml up -d rails`.
- **My Inbox** : badge = compteur rapide ; liste = serialisation lourde (conversation + dernier message). Le patch admin cree **5 notifications max** pour rester sous le timeout.
- **Conversations bloquees en chargement** : arreter un seed en cours, attendre 30 s, rafraichir. Pour une demo fluide, preferer PostgreSQL local plutot que Neon.

## Ecrans a montrer

1. **Conversations** - filtres `priorite-haute`, `intent-prix`
2. **Contacts** - fiches completes, labels pipeline
3. **Agents** - 5 agents demo
4. **Campagnes** - statuts varies
5. **Captain** - overview rempli
6. **Rapports** - 90 jours de donnees
7. **ConvertTrack /test** - inbox interne separee
