# Workspaces Woot - guide multi-departement

## Modele

- **Plateforme** : toutes les capacites sont actives (Captain, canaux, ConvertTrack, teams, labels).
- **Workspace (Account)** : espace isole cree par le proprietaire, avec ses propres providers et regles.
- **Acces** : un agent ne voit que les workspaces ou le proprietaire l'a invite.

## Creer un workspace

1. Dashboard → switcher de compte → **New Account**
2. Le setup ConvertTrack s'execute automatiquement :
   - labels intent/pipeline/priorite
   - webhook message_created
   - features Captain + canaux
3. Choisir le type de workspace dans les settings (marketing, support, reclamations, custom)

Variables utiles a la creation :

```bash
CONVERTTRACK_AUTO_SETUP=true
CONVERTTRACK_WORKSPACE_TYPE=support
```

## Connecter les providers (par workspace)

Chaque workspace connecte **ses propres credentials** via Settings → Inboxes → Add channel :

| Provider | Canal | Notes |
|---|---|---|
| WhatsApp | Whatsapp | Meta Business API du workspace |
| Facebook | Facebook Page | OAuth page propre |
| Instagram | Instagram | Lie au compte FB du workspace |
| Email | Email | IMAP/SMTP propre |
| Widget web | Website | URL propre |

Les credentials ne sont jamais partages entre workspaces.

## Inviter des agents

Settings → Agents → **Add Agent**

- L'agent recoit une invitation par email
- Il n'a acces qu'a **ce workspace**
- Pour un second workspace, le proprietaire doit l'inviter a nouveau
- Le switcher n'apparait que si l'agent appartient a 2+ workspaces

## Modes IA par workspace

Setting `converttrack_automation_mode` :

| Mode | Comportement |
|---|---|
| `classification` (defaut) | ConvertTrack classe, priorise, suggere en note privee. Captain ne repond pas. |
| `agentic` | Captain repond automatiquement. ConvertTrack enrichit (labels, priorite). |
| `hybrid` | ConvertTrack classe et priorise; Captain repond automatiquement avec le contexte. |

API ConvertTrack :

```bash
curl -X PATCH http://127.0.0.1:5000/api/workspaces/1/config \
  -H "Content-Type: application/json" \
  -d '{"automation_mode":"agentic","workspace_type":"support"}'
```

## Catalogues produits (Captain)

Dans les settings du workspace, ajouter `converttrack_catalog_sources` : liste d'URLs JSON.

Captain utilise l'outil **Product Lookup** pour interroger ces catalogues (prix, stock, livraison).

## Federation contacts (optionnel)

Pour les organisations multi-workspaces qui veulent une timeline client unifiee :

```bash
curl http://127.0.0.1:5000/api/federation/contacts/client@example.com
```

## Campagnes multicanal (API)

```bash
curl -X POST http://127.0.0.1:5000/api/workspaces/1/campaigns \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Promo ete",
    "message": "Decouvrez nos offres",
    "channels": [
      {"type": "whatsapp", "inbox_id": 1},
      {"type": "email", "inbox_id": 2}
    ],
    "audience": {"labels": ["pipeline-interet"]}
  }'
```

L'orchestrateur cree un `CampaignRun` et queue chaque canal. L'envoi effectif s'appuie sur les inboxes deja connectees au workspace.
