# Boutigui — Plan d'implémentation fintech (hackathon 28–29 septembre 2026)

Écrit le 20 septembre 2026. 8 jours. Ce plan est classé par valeur/effort,
pas par ordre d'apparition dans le roadmap. Chaque étape est cochable.

Principe directeur : **ne rien construire qui ne serve pas la démo de 5
minutes ou la crédibilité technique face à un jury fintech.**

---

## Étape 0 — Réparer `AGENTS.md`

- [x] L'en-tête dit « This is NOT the Next.js you know » et renvoie vers
      `node_modules/next/dist/docs/`. Ce dépôt est en Flutter. Tout agent
      lit ce fichier en premier.

## Étape 1 — `supabase/fintech_patch.sql` (le socle)

Deux trous réels, tous les deux côté base :

- [x] **1.1 Intégrité des montants.** Aujourd'hui `unit_price`, `subtotal`
      et `total` viennent du client (`order_service.dart:81` et `:148`) et
      la base ne vérifie que `>= 0`. Un client modifié peut commander à
      1 MRU. Déclencheur sur `order_items` : relire le prix depuis
      `products`, recalculer `subtotal`, recalculer `orders.total`.
- [x] **1.2 Statut de paiement.** L'énumération `status` actuelle n'a
      aucun état de paiement, et l'élargir casserait l'espace Livreur qui
      s'appuie dessus. Donc colonnes séparées : `payment_status`
      (`submitted` / `verified` / `rejected`), `payment_provider`,
      `payment_verified_at`.
- [x] **1.3 Qui a le droit.** Seuls la vendeuse propriétaire et l'admin
      changent `payment_status`. Étendre le déclencheur
      `client_order_update_guard` aux nouvelles colonnes.
- [x] **1.4 Index** pour les requêtes du tableau de bord.

## Étape 2 — Câblage Dart du socle

- [x] `OrderModel` : `paymentStatus`, `paymentProvider`, `paymentVerifiedAt`.
- [x] Le checkout enregistre le fournisseur choisi (on l'affiche déjà, on
      ne le stockait pas).
- [x] La vendeuse marque « référence vérifiée » depuis sa liste de
      commandes.
- [x] Badge de statut de paiement (couleur **+** texte, jamais la couleur
      seule — cf. accessibilité).

## Étape 3 — `supabase/demo_seed.sql`

Avant le tableau de bord, pas après : on construit contre de vraies formes
de données.

- [x] 1 boutique démo (Maison Aïcha, Mode, Nouakchott, Bankily).
- [x] ~15 produits, prix réalistes en MRU.
- [x] ~60 commandes sur 90 jours, avec un **vrai biais hebdomadaire** pour
      que « votre jour le plus actif est vendredi » soit une observation
      vraie et pas un texte codé en dur.
- [x] 3 fournisseurs de paiement répartis, quelques commandes en attente.
- [x] Idempotent, comme tous les autres fichiers SQL du dépôt.

## Étape 4 — `lib/services/analytics_service.dart`

Dérivé de `orders` / `order_items`, **aucune table d'analytics**.

- [x] Chiffre d'affaires, nombre de commandes, clientes distinctes, panier
      moyen, évolution vs période précédente.
- [x] Série temporelle des ventes (par jour).
- [x] Répartition par fournisseur de paiement.
- [x] Meilleures ventes / produits qui ralentissent.
- [x] Activité par jour de semaine.

## Étape 5 — Tableau de bord vendeuse

- [x] `lib/features/vendor/vendor_dashboard_screen.dart`.
- [x] Graphique en ligne dessiné au `CustomPainter` — **pas de nouvelle
      dépendance** : `google_fonts` a déjà coûté une journée en septembre,
      `fl_chart` peut coûter la même chose sur Flutter 3.27.
- [x] États vide / chargement / erreur (le jury verra au moins un des trois).

## Étape 6 — Indice de préparation financière

- [x] Formule **visible à l'écran**, quatre sous-scores traçables chacun à
      un fait comptable. Pas de boîte noire : un jury fintech demandera
      comment le chiffre est calculé.
- [x] Formulation prudente : « peut aider un partenaire financier à mieux
      comprendre votre activité », jamais « prêt garanti ».

## Étape 7 — Boutigui Insights

- [x] Phrases générées en Dart à partir des statistiques réelles.
- [x] **Pas d'appel API depuis le client** : l'app est déployée sur le web
      (`netlify.toml`), une clé dans le bundle contredirait le discours
      sécurité de la présentation.
- [x] Étiqueter honnêtement ce qui est observé et ce qui est suggéré.

## Étape 8 — Finition du parcours de paiement

- [x] Le checkout est en anglais en dur alors que la démo est en français.
- [x] Instructions de paiement numérotées (cf. §13 du roadmap).
- [x] Passer les nouvelles chaînes par `lib/core/strings.dart`.

---

## Hors périmètre (assumé)

Tableau de bord d'impact dans l'app (→ une diapo), portail institution
financière, vérification automatique, expansion régionale, refonte RTL
au-delà de l'existant, table `payment_transactions` (les colonnes sur
`orders` suffisent et évitent la désynchronisation).

---

## État au 20 septembre 2026

Code écrit et vérifié : `flutter analyze` reste à 49 remarques, exactement
le niveau d'avant ces changements (aucune régression), et
`flutter build web --release` passe.

### Ce qu'il reste à faire, et que je ne peux pas faire à votre place

1. **Jouer les trois fichiers SQL dans Supabase**, dans cet ordre :
   `fintech_patch.sql`, puis `fintech_tests.sql` (il s'annule tout seul,
   il ne fait que vérifier), puis `demo_seed.sql`.
   Rien de ce qui précède ne fonctionne tant que le patch n'est pas joué :
   l'app retombe sur des valeurs par défaut et ne plante pas, mais le
   tableau de bord sera vide et les montants resteront ceux du client.
2. **Créer le compte vendeuse démo depuis l'application** (inscription
   normale), puis mettre son adresse en haut de `demo_seed.sql` avant de
   le jouer. Le compte doit pouvoir se connecter pendant la démo, donc il
   lui faut un vrai mot de passe chiffré par Supabase Auth.
3. **Répéter la démo en 5 minutes.** C'est la partie qui n'est pas du
   code et c'est celle que le jury note.

### Ce qui est volontairement resté dehors

- Le tableau de bord d'impact dans l'app : une diapo suffit, et des
  chiffres de plateforme inventés dans un produit se voient.
- La table `payment_transactions` du roadmap : les colonnes sur `orders`
  couvrent le besoin sans risquer la désynchronisation à huit jours.
- Tout appel à un modèle d'IA depuis le client.

### Défaut connu, non corrigé

`AGENTS.md` demande de lire dix fichiers dans `context/` et un dossier
`docs/specs/`. Ni `context/` ni `docs/` n'existent dans ce dépôt. L'en-tête
Next.js a été corrigé ; cette liste-là ne l'a pas été, parce qu'elle
appartient au squelette des skills `/audit` et `/sync` et que c'est à eux
de la remplir ou de la retirer.
