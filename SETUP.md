# Marketplace — première version fonctionnelle

Client Flutter (5 sections : accueil, boutiques, catégories, panier, profil)
+ fiche produit, connexion/inscription, commande, envoi de la capture de
paiement, favoris, candidature vendeur, aide, changement de langue FR/AR/EN.

**Important, honnêtement** : cette version a été écrite dans un environnement
où le SDK Dart et pub.dev sont bloqués — exactement la même limitation que la
fois précédente. Le code a été relu et vérifié à la main (délimiteurs
équilibrés, imports résolus, cohérence des noms entre modèles / services /
écrans, API Supabase/Flutter à jour), mais **n'a pas pu être réellement
compilé ici**. La toute première commande à lancer chez toi est donc
`flutter analyze` — pas une formalité cette fois, une vraie vérification.

## 1. Installer Flutter (méthode git — pas snap)

```bash
sudo apt install -y git curl unzip xz-utils zip libglu1-mesa
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

flutter precache --web
flutter --version
```

## 2. Le projet

```bash
cd chemin/vers/marketplace
flutter create --platforms=web,android,ios .   # génère les dossiers natifs manquants — le point final compte
flutter pub get
flutter analyze
```

Corrige ce que `flutter analyze` signale avant d'aller plus loin — c'est
l'étape qui manquait la dernière fois.

## 3. Le projet Supabase

1. [supabase.com](https://supabase.com) → New Project → région `eu-west-3` (Paris).
2. **SQL Editor** → coller et lancer les fichiers de `supabase/`, **dans cet
   ordre** (chacun suppose que les précédents sont passés) :

   | # | Fichier | Ce qu'il apporte |
   |---|---|---|
   | 1 | `marketplace_schema.sql` | Tables, fonctions, triggers, policies RLS, 4 buckets |
   | 2 | `reviews_patch_purchase_required.sql` | Un avis exige une commande contenant le produit |
   | 3 | `livreur_patch.sql` | Espace Livreur (courses, profils livreur, RPC) |
   | 4 | `livreur_patch_2_grants.sql` | Droits de base manquants sur ces deux tables |
   | 5 | `livreur_patch_3_approval.sql` | Un livreur doit être approuvé par l'admin |
   | 6 | `rattrapage_patch.sql` | Reconstruction des 4 patchs absents du dépôt — voir l'en-tête du fichier |

   Le point 6 remplace `admin_patch.sql`, `paiement_options_patch.sql`,
   `securite_patch.sql` et `profiles_trigger_patch.sql`, que le code
   référence mais qui ne sont pas dans ce dépôt. **Sans lui, passer
   commande échoue** (colonnes `payment_reference` / `delivery_*`
   absentes), et l'accueil, les notifications et le site admin n'ont pas
   leurs tables.
3. **Project Settings > API** → récupère :

   | Valeur | Dans l'app ? |
   |---|---|
   | `Project URL` | oui |
   | Clé `anon` `public` | oui |
   | Clé `service_role` | **jamais** |
   | Mot de passe de la base | **jamais** |

4. Inscris-toi une première fois depuis l'application (écran Profil > Se
   connecter > Créer un compte).
5. Deviens administrateur — **uniquement possible depuis le SQL Editor**,
   le trigger anti-élévation de privilège bloque ce changement depuis l'app :

   ```sql
   update public.profiles set role = 'admin' where email = 'ton.email@exemple.com';
   ```

6. Crée une boutique de test et 3-4 produits directement dans **Table
   Editor** (`shops`, `products`, `product_images`) — pense à mettre
   `is_visible = true` sur la boutique (colonne protégée : seul un admin
   peut la faire passer à `true`, ce que tu es devenue à l'étape 5) et sur
   les produits.

## 4. Lancer l'application

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://TON-PROJET.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=TA-CLE-ANON
```

Sans ces deux valeurs, l'app affiche un écran "Configuration requise" au
lieu de planter — plus facile à diagnostiquer.

Le navigateur suffit pour tout vérifier. Android Studio n'est nécessaire que
plus tard, pour générer l'APK.

## 5. Bascule vers Cloudflare R2, plus tard

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=USE_R2=true \
  --dart-define=R2_PUBLIC_BASE_URL=https://images.tondomaine.mr
```

Aucun code à modifier — `StorageService` bascule seul.

## Ce qui est fait dans cette version

- Accueil (recherche, boutiques en vedette, nouveautés)
- Boutiques (liste paginée, fiche boutique, comptage de visite quotidien)
- Catégories (arborescence à 3 niveaux, navigation par niveau)
- Fiche produit (galerie, avis, favoris, contact WhatsApp, ajout au panier)
- Panier (découpé par boutique, quantités)
- Commande (une commande par boutique à la validation)
- Mes commandes + envoi de la capture de paiement (bucket privé)
- Favoris
- Profil (édition, déconnexion, changement de langue FR/AR/EN avec RTL)
- Candidature "Devenir vendeur"
- Aide et support

## Ce qui reste (comme dans le récap précédent)

- Espace vendeur et back-office admin : projets web séparés (Cloudflare
  Pages), pas dans ce client mobile
- Compression des images à l'upload (WebP) — pertinent côté back-office,
  qui gère l'ajout de produits
- Vérification du numéro par SMS — volontairement absente (coût Twilio,
  risque de pompage de crédit) ; le schéma est prêt si besoin plus tard
- Test de charge, sauvegarde `pg_dump` avant démo — voir le récap du projet

## Structure

```
lib/
  app_config.dart          Clés, devise, pagination, bascule R2
  core/                    money, strings (FR/AR/EN), theme, settings
  models/models.dart       Miroir du schéma PostgreSQL
  services/                auth, catalogue, panier, commandes, stockage
  features/
    shell.dart              Navigation à 5 onglets
    widgets.dart             Composants partagés
    home/ shops/ categories/ cart/ profile/ auth/ product/ orders/ vendor_apply/
supabase/
  marketplace_schema.sql    12 tables, RLS, triggers, buckets
```
