# Ce qui a été construit pour le hackathon

**20 – 21 septembre 2026.** Point de départ : une place de marché Flutter +
Supabase fonctionnelle (boutiques, produits, commandes, livraison, admin,
trois langues). Point d'arrivée : la même application, avec une couche
financière, une identité refaite, et l'application renommée **MESK →
Boutigui**.

Ce fichier liste ce qui a changé et pourquoi. Il est écrit pour être lu
par quelqu'un qui n'était pas là.

---

## 1. Intégrité des paiements

### Le trou de départ

`order_service.checkout` envoyait `unit_price`, `subtotal` et `total`
depuis le téléphone. La base ne vérifiait que `>= 0`. **Un client modifié
pouvait commander n'importe quoi à 1 MRU**, et la vendeuse voyait une
commande qui semblait payée.

### Ce qui a été fait — `supabase/fintech_patch.sql`

| Règle | Mécanisme |
|---|---|
| Chaque ligne est retarifée | Déclencheur sur `order_items` : le prix est relu depuis `products`, jamais accepté du client |
| `orders.total` est recalculé | Somme des lignes, après chaque insertion/modification/suppression |
| Le total envoyé à la création vaut zéro | Déclencheur sur `orders` ; seul le recalcul le remplit |
| Un produit ne se commande pas via une autre boutique | Vérifié dans le même déclencheur |
| La cliente ne touche à rien après coup | `client_order_update_guard` étendu aux colonnes de paiement |

**Piège rencontré, à connaître :** le recalcul du total écrit dans
`orders`, ce qui réveille le garde qui interdit justement à une cliente de
modifier le total. Les deux communiquent par un drapeau local à la
transaction (`mesk.total_recompute`). Toucher à l'un impose de vérifier
l'autre.

### Le dernier trou — `supabase/payment_amount_patch.sql`

Une référence pouvait être authentique, unique, **et correspondre à une
transaction d'un tout autre montant** : payer 100 MRU, soumettre cette
référence pour une commande de 50 000. Les deux contrôles existants la
laissaient passer.

Aucun fournisseur mauritanien n'expose d'API de vérification : le
rapprochement automatique est hors de portée. Ce qui est à portée : la
vendeuse a le montant sous les yeux au moment où elle retrouve la
référence. On le lui demande, on le compare, l'écart devient visible.

**Le contrôle reste humain ; ce qui change, c'est qu'il est enregistré.**

### La preuve — `supabase/fintech_tests.sql`

Neuf assertions dans une transaction annulée à la fin : rien n'est écrit.
Le résultat sort sous forme de tableau (l'éditeur SQL de Supabase
n'affiche pas les `raise notice`). Exécutable devant un jury.

---

## 2. Statut de paiement

Colonnes **séparées** plutôt qu'une énumération `status` élargie :
`payment_status`, `payment_provider`, `payment_verified_at`,
`payment_amount_received`. La colonne `status` décrit l'avancement de la
commande et l'espace Livreur s'appuie dessus — l'élargir aurait cassé
`livreur_patch.sql`.

Pas d'état « en attente de paiement » : sans référence, aucune commande
n'est créée.

La vendeuse confirme depuis le détail de la commande. **Le libellé par
défaut reste « Référence soumise — à vérifier »** : rien ne vérifie
automatiquement, et l'écrire autrement serait un mensonge affiché à la
cliente.

Un bug corrigé au passage : l'écran des commandes affichait une coche
« vérifié » à côté de **chaque** référence, y compris celles qu'une
vendeuse avait marquées introuvables.

---

## 3. Comprendre son activité

**`lib/services/analytics_service.dart`** — tout est dérivé de `orders` /
`order_items`. Aucune table de statistiques : une valeur stockée finit
toujours par diverger de la commande qu'elle résume.

**`lib/features/vendor/vendor_dashboard_screen.dart`** — chiffre
d'affaires, commandes, clientes, évolution, courbe des ventes, répartition
par service de paiement, meilleures ventes, périodes de 7 / 30 / 90 jours,
états vide / chargement / erreur.

La courbe est dessinée au `CustomPainter` : **aucune dépendance
graphique**. `google_fonts` avait déjà coûté une journée en septembre pour
incompatibilité de version.

### Indice de préparation financière

Quatre volets de 25 points, chacun rattaché à un fait comptable
vérifiable : régularité, volume, paiements confirmés, complétude du
profil.

**La formule est affichée.** Un jury fintech demande toujours comment un
score est calculé ; « c'est notre algorithme » est une mauvaise réponse.
Aucun attribut personnel n'entre dans le calcul.

### Boutigui Insights

Phrases générées **en Dart** à partir des statistiques réelles, étiquetées
*Observation* ou *Suggestion*.

Pas d'appel à un modèle : l'application est déployée sur le web, une clé
d'API dans le bundle serait lisible par n'importe qui — ce qui
contredirait exactement le discours sécurité de la présentation.

---

## 4. Dossier d'activité (PDF)

**`lib/features/vendor/business_profile_screen.dart`** et
**`lib/services/business_profile_pdf.dart`**.

Un score affiché dans une application ne se transmet pas : une banque ne
reçoit pas un écran. Le bouton « Générer mon dossier » produit un document
A4 — identité, historique, paiements, indice avec son détail, avertissement
— et ouvre le partage du système (WhatsApp, e-mail, fichiers).

Première version : copie dans le presse-papier. Remplacée après retour :
trop faible pour un dossier d'entreprise.

Aucune police n'est embarquée (Helvetica intégrée au format PDF) : zéro
octet ajouté à l'application, au prix de l'arabe. Le dossier est en
français, langue des dossiers bancaires en Mauritanie.

---

## 5. Inclusion

**`supabase/inclusion_patch.sql`** — `shops.women_led`, facultatif,
déclaré par la propriétaire, plus une fonction `inclusion_stats()` qui ne
renvoie que des **comptes** : impossible de savoir, depuis l'application,
ce qu'une boutique donnée a déclaré.

Boutigui est ouvert à tous les entrepreneurs mauritaniens ; les femmes en
sont le public principal.

**Cette colonne n'entre jamais dans l'indice financier.** Faire peser un
attribut personnel protégé sur un signal qui peut orienter un financement,
c'est de la discrimination à l'octroi de crédit. La règle est écrite dans
le SQL, dans le Dart, et sous la case à cocher.

Le pourcentage est calculé sur les boutiques qui ont **répondu**, et
masqué en dessous de trois déclarations : un pourcentage sur deux cas
n'est pas une statistique.

---

## 6. Connexion par e-mail

L'inscription était passée en **Google uniquement** le 15 septembre, pour
une bonne raison : une adresse saisie à la main n'est jamais vérifiée.
Mais cela fermait la porte à qui n'a pas de compte Google actif.

`AuthService.signIn` et `signUp` n'avaient jamais été supprimés — seule
l'interface l'avait été. Elle a été reconstruite : bascule
connexion / inscription, validation en français **avant** l'appel réseau,
messages d'erreur du serveur traduits, renvoi du message de confirmation.

**L'objection d'origine se traite côté Supabase** : activer « Confirm
email » rend l'adresse aussi vérifiée qu'avec Google.

---

## 7. Interface

Refonte à partir des maquettes fournies, dans une palette verte ajoutée
**à côté** des jetons existants (`AppTheme.green`, `greenDeep`,
`greenTint`, `sage`) — le reste de l'application n'est pas touché.

| Écran | Ce qui change |
|---|---|
| Accueil | En-tête blanc avec mot-symbole et recherche, bannière en carte 4:3, grille de catégories, grille de produits, bandeau de réassurance, panneau d'impact |
| Catégories | Bandes pleine largeur → grille de cartes, partagée avec l'accueil (`CategoryCard`) |
| Compte | En-tête dégradé avec photo et rôle, lignes en cartes avec sous-titres, carte d'assistance |
| Mon profil | Champs encadrés, photo de profil, hiérarchie des boutons, indicatif fixe |
| Commandes | Cartes du système de design, statut de paiement réel |
| Aide | Carte d'en-tête, moyens de contact en cartes |
| Paiement | Traduit en français, cinq étapes numérotées |

### Bugs d'interface corrigés

- **La bannière se rognait elle-même** : image carrée dans une boîte dont
  la hauteur dépendait de l'écran, donc un rognage différent sur chaque
  téléphone. « New Arrivals » s'affichait « ew Arrival ». Format fixe 4:3.
- **La barre de recherche ouvrait une seconde barre de recherche** au lieu
  d'accepter la frappe.
- **L'indicatif téléphonique se dupliquait** : un numéro enregistré
  « 22242000000 » devenait « +222 22242000000 » à chaque enregistrement.
- **Des valeurs hexadécimales du thème SOMBRE** subsistaient depuis le
  passage au clair du 3 septembre, rendant un bouton désactivé illisible.
- **Une phrase moitié française moitié anglaise** sur l'écran d'aide.
- **Aucune marque nulle part** : `app_name` valait littéralement « Shop ».

### Photo de profil

`avatar_url` existait depuis le début et l'écran Compte l'affichait déjà —
mais **rien ne permettait d'en déposer une**. Ajoutée, avec envoi immédiat
au choix de l'image.

---

## 8. Renommage MESK → Boutigui

34 remplacements dans 12 fichiers : mot-symbole, `app_name` (fr/ar/en),
dossier PDF, avertissements, messages de confirmation, classe
`MeskInsights` → `BoutiguiInsights`.

**Deux exceptions volontaires**, à ne pas « corriger » :

- `mesk.total_recompute` — variable de session PostgreSQL, invisible, et
  **déjà en place dans la base**. La renommer imposerait de rejouer le
  patch pour aucun bénéfice visible.
- `@mesk.mr` dans `demo_seed.sql` — ces comptes **existent déjà en base**.
  Le nettoyage du script les repère par ce motif ; le changer laisserait
  quinze clientes orphelines à chaque réexécution.

---

## 9. Outillage

- **`run_local.sh`** — lancement local économe en mémoire. Mesuré :
  `--release` demande **3 120 Mo**, le profil léger **1 202 Mo**, pour
  200 ko de JavaScript en plus. Un plafond de tas
  (`--old_gen_heap_size=700`) évite que le noyau tue la compilation sur une
  machine chargée.
- **`undo_design.sh`** — restauration des retouches d'interface.
- **`FINTECH_PLAN.md`** — le plan, avec ce qui a été écarté et pourquoi.
- **`AGENTS.md`** — l'en-tête annonçait « This is NOT the Next.js you
  know » dans un dépôt Flutter sans `node_modules`.

### Dépendances ajoutées

`pdf ^3.13.1` et `printing ^5.15.1`, pour le dossier. Compatibilité
vérifiée par une compilation web complète **avant** d'écrire la moindre
ligne qui s'en sert.

---

## Ce qui n'a pas été fait, et pourquoi

- **Aucune IA générative.** Les analyses sont déterministes et
  vérifiables. C'est un choix : près d'un signal financier, un
  raisonnement auditable vaut mieux qu'un modèle.
- **Aucune vérification automatique des paiements** — aucun fournisseur
  mauritanien ne l'expose.
- **Pas de table `payment_transactions`** — les colonnes sur `orders`
  couvrent le besoin sans risquer la désynchronisation.
- **Pas de notes produit** — aucune donnée derrière.
- **Pas de portail institution financière, pas d'expansion régionale** —
  ce sont des diapositives, pas du code.

## Reste à faire

1. Les photos : 1 seule image pour 16 produits, aucune photo de catégorie.
2. Les trois champs à remplir sur la dernière diapositive.
3. Répéter le parcours complet : achat → tableau de bord → dossier.
