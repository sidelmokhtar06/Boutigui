# Boutigui

**Le commerce mauritanien, connecté à la finance.**

Une place de marché mauritanienne avec une couche fintech : les
commerçantes vendent en ligne, encaissent par mobile money, suivent leur
activité, et transforment cette activité en un dossier qu'un partenaire
financier peut lire.

Construit pour le **Hackathon Fintech Mauritanie** (28–29 septembre 2026,
Nouakchott).

---

## Ce que fait l'application

| | |
|---|---|
| **Vendre** | Boutiques, produits, panier, commandes, favoris |
| **Encaisser** | Code marchand Bankily / Masrvi / Sedad, référence de transaction |
| **Livrer** | Espace livreuse, courses géolocalisées |
| **Comprendre** | Tableau de bord : ventes, clientes, encaissements par service |
| **Grandir** | Indice de préparation financière et dossier d'activité en PDF |

Français, arabe et anglais, avec sens de lecture droite-à-gauche.

## La couche paiement

L'argent ne transite **jamais** par Boutigui : la cliente paie la
commerçante depuis sa propre application bancaire, avec le code marchand de
la boutique. L'application enregistre la référence de transaction.

Quatre garde-fous, tous côté base de données :

1. **Aucune commande sans paiement** — la référence est obligatoire à la
   création, pas ajoutée après coup.
2. **Une référence ne sert qu'une fois** — index unique en base. C'est ce
   qui remplace la capture d'écran, qu'on pouvait retoucher et renvoyer.
3. **Les montants sont recalculés côté serveur** — chaque prix est relu
   depuis `products`, chaque total recalculé depuis les lignes. Un client
   modifié ne peut pas commander à 1 MRU.
4. **L'écart de montant est visible** — la commerçante relève ce qu'elle a
   reçu ; un écart avec le total dû est signalé.

`supabase/fintech_tests.sql` démontre les neuf règles dans une transaction
annulée à la fin.

## Préparation financière

Un indicateur d'activité sur 100 points, en quatre volets de 25 :
régularité, volume de commandes, paiements confirmés, complétude du profil.

**La formule est affichée à l'écran et reprise dans le dossier PDF.** Seule
l'activité commerciale entre dans le calcul — aucun attribut personnel.

Ce n'est ni un score de crédit, ni une décision de financement. Boutigui
n'est ni une banque, ni un prêteur, ni un établissement de paiement.

## Technique

Flutter (Dart) + Supabase (PostgreSQL, Auth, Storage, RLS). Déployé sur le
web et sur Android.

```bash
cp .env.local.example .env.local   # puis renseigner URL et clé anon
./run_local.sh serve               # compile puis sert sur :8080
./run_local.sh dev                 # rechargement à chaud
```

Les migrations SQL se collent à la main dans l'éditeur SQL de Supabase,
dans l'ordre indiqué par [`supabase/AGENTS.md`](supabase/AGENTS.md).

## Documentation

- [`AGENTS.md`](AGENTS.md) — contexte du dépôt
- [`supabase/AGENTS.md`](supabase/AGENTS.md) — ordre des migrations, pièges RLS
- [`lib/services/AGENTS.md`](lib/services/AGENTS.md) — couche de données
- [`FINTECH_PLAN.md`](FINTECH_PLAN.md) — plan de la couche fintech

## Sécurité

La clé `service_role` n'est jamais utilisée côté client. Seule la clé
`anon` publique l'est, et elle arrive par `--dart-define` — jamais écrite
dans le dépôt. Row Level Security est actif sur toutes les tables.
