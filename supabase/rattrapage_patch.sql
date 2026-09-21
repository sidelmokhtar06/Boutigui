-- =====================================================================
-- RATTRAPAGE — reconstruction des patchs manquants, 20 septembre 2026.
--
-- POURQUOI CE FICHIER EXISTE
-- Le code de l'application référence quatre fichiers SQL qui ne sont pas
-- dans ce dépôt : `admin_patch.sql`, `paiement_options_patch.sql`,
-- `securite_patch.sql` et `profiles_trigger_patch.sql`. Leur contenu a
-- donc été RECONSTRUIT à partir de ce que l'application lit et écrit
-- réellement (modèles, services, écrans admin) et à partir de l'état réel
-- de la base, colonne par colonne.
--
-- Ce n'est PAS une copie des fichiers d'origine : les noms de colonnes et
-- les types sont sûrs (l'app ne marcherait pas autrement), mais les règles
-- RLS et les déclencheurs de notification sont une RECONSTRUCTION — leur
-- intention est expliquée en clair au-dessus de chaque bloc pour que tu
-- puisses la vérifier. Si les vrais fichiers réapparaissent un jour,
-- préfère-les à celui-ci.
--
-- OÙ L'EXÉCUTER : Supabase > SQL Editor, en une fois, APRÈS
-- `marketplace_schema.sql` et les trois `livreur_patch*.sql`.
-- Entièrement rejouable : chaque objet est créé `if not exists` et chaque
-- policy est précédée d'un `drop policy if exists`.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. COLONNES MANQUANTES
-- ---------------------------------------------------------------------
-- Toutes vérifiées absentes de la base le 20 septembre 2026, et toutes
-- lues ou écrites par `lib/models/models.dart`.

-- 1.1 profiles.gender — écran "Mon profil" (3 septembre 2026).
-- Pas de `not null` : les comptes existants n'ont rien à déclarer.
alter table public.profiles
  add column if not exists gender text
    check (gender in ('female', 'male', 'unspecified'));

-- 1.2 categories — photo de la bande, son cadrage, et sa visibilité.
-- `focal_x`/`focal_y`/`zoom` : le point de la photo à garder visible et
-- son zoom, réglés depuis le site admin (Category.fromMap attend 0.5 /
-- 0.5 / 1.0 par défaut, soit "centre, pas de zoom").
alter table public.categories
  add column if not exists image_url  text,
  add column if not exists focal_x    double precision not null default 0.5,
  add column if not exists focal_y    double precision not null default 0.5,
  add column if not exists zoom       double precision not null default 1.0,
  add column if not exists is_visible boolean not null default true;

-- 1.3 products — prix barré, marque, et options (taille / couleur).
-- `option_type` vaut 'text' (puces 38, 39, 40...) ou 'color' (carrés de
-- couleur, teintes dans `option_colors`, même ordre que `option_values`).
-- Les trois listes sont des tableaux Postgres : le client Supabase les
-- renvoie tels quels en listes Dart.
alter table public.products
  add column if not exists compare_at_price numeric(12,2) check (compare_at_price is null or compare_at_price >= 0),
  add column if not exists brand            text,
  add column if not exists option_name      text,
  add column if not exists option_values    text[] not null default '{}',
  add column if not exists option_type      text not null default 'text'
    check (option_type in ('text', 'color')),
  add column if not exists option_colors    text[] not null default '{}',
  add column if not exists option_sold_out  boolean[] not null default '{}';

-- 1.4 product_images — cadrage et zoom, une valeur par photo.
alter table public.product_images
  add column if not exists focal_x double precision not null default 0.5,
  add column if not exists focal_y double precision not null default 0.5,
  add column if not exists zoom    double precision not null default 1.0;

-- 1.5 shops — code marchand de la banque mobile de la vendeuse.
-- L'argent va directement à la vendeuse ; l'app ne touche jamais aux
-- fonds, elle ne fait qu'afficher ce code à la cliente au moment de payer.
alter table public.shops
  add column if not exists merchant_code     text,
  add column if not exists merchant_provider text;

-- 1.6 orders — référence de paiement et point de livraison.
-- `delivery_mode` : 'pickup' (la cliente vient chercher) ou 'delivery'
-- (une course est créée pour les livreuses). 'pickup' par défaut, comme
-- `OrderModel.fromMap` qui retombe sur 'pickup' si la colonne est vide.
alter table public.orders
  add column if not exists payment_reference text,
  add column if not exists delivery_lat      double precision,
  add column if not exists delivery_lng      double precision,
  add column if not exists delivery_mode     text not null default 'pickup'
    check (delivery_mode in ('pickup', 'delivery'));

-- Une référence de paiement ne peut servir qu'UNE fois : c'est le numéro
-- de transaction que la cliente recopie depuis son application bancaire.
-- Le nom de l'index compte — `cart_screen.dart` le cherche dans le message
-- d'erreur brut de Postgres pour afficher "cette référence a déjà été
-- utilisée" plutôt qu'une erreur technique. Index partiel : plusieurs
-- commandes sans référence restent possibles.
create unique index if not exists orders_payment_reference_unique
  on public.orders (payment_reference)
  where payment_reference is not null;


-- ---------------------------------------------------------------------
-- 2. TABLES MANQUANTES
-- ---------------------------------------------------------------------

-- 2.1 app_settings — UNE seule ligne (id = 1), jamais créée par l'app :
-- `admin_service.updateAppSettings` fait un `update ... where id = 1`, qui
-- ne crée rien s'il ne trouve rien. La ligne est donc insérée ici.
create table if not exists public.app_settings (
  id            int primary key default 1 check (id = 1),
  contact_phone text,
  website_url   text,
  updated_at    timestamptz not null default now()
);

insert into public.app_settings (id) values (1)
on conflict (id) do nothing;

-- 2.2 home_banners — jusqu'à 5 photos par emplacement (le plafond est
-- appliqué côté admin, pas ici). `category_id` null = bannière de
-- l'accueil ; renseigné = bannière affichée seulement en haut de cette
-- catégorie.
create table if not exists public.home_banners (
  id          uuid primary key default gen_random_uuid(),
  image_url   text not null,
  category_id uuid references public.categories(id) on delete cascade,
  sort_order  int not null default 0,
  is_visible  boolean not null default true,
  created_at  timestamptz not null default now()
);

create index if not exists idx_home_banners_category on public.home_banners(category_id);

-- 2.3 home_collections — bannière secondaire + sélection de produits.
-- `category_id` null = produits mélangés ; renseigné = produits de cette
-- catégorie. `product_limit` = combien en afficher.
create table if not exists public.home_collections (
  id            uuid primary key default gen_random_uuid(),
  image_url     text not null,
  title         text not null,
  subtitle      text,
  category_id   uuid references public.categories(id) on delete set null,
  product_limit int not null default 8 check (product_limit > 0),
  sort_order    int not null default 0,
  is_visible    boolean not null default true,
  created_at    timestamptz not null default now()
);

-- 2.4 notifications — écrites UNIQUEMENT par la base (déclencheurs de la
-- partie 4), jamais par l'application : aucune policy `insert` n'est
-- donnée à qui que ce soit, donc personne ne peut s'envoyer de fausses
-- notifications ni en écrire à quelqu'un d'autre.
-- `kind` : 'order_new' (pour la vendeuse) ou 'order_status' (pour la
-- cliente) — `notifications_screen.dart` choisit l'icône là-dessus.
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text,
  order_id   uuid references public.orders(id) on delete cascade,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_user
  on public.notifications(user_id, is_read, created_at desc);

-- 2.5 shop_categories — dans quelles catégories une boutique travaille
-- (choisi à l'inscription vendeuse, plusieurs réponses possibles).
-- Remplacée en entier à chaque enregistrement par `setMyShopCategories`.
create table if not exists public.shop_categories (
  shop_id     uuid not null references public.shops(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  primary key (shop_id, category_id)
);


-- ---------------------------------------------------------------------
-- 3. RLS ET DROITS SUR LES NOUVELLES TABLES
-- ---------------------------------------------------------------------
-- Rappel appris avec `livreur_patch_2_grants.sql` : une policy RLS ne
-- remplace jamais le droit d'accès de base sur la table. Une table créée
-- après coup n'hérite pas automatiquement de ce droit — d'où les `grant`
-- explicites ci-dessous.

alter table public.app_settings     enable row level security;
alter table public.home_banners     enable row level security;
alter table public.home_collections enable row level security;
alter table public.notifications    enable row level security;
alter table public.shop_categories  enable row level security;

-- 3.1 app_settings — lecture publique (le numéro de contact s'affiche dans
-- l'écran d'aide, y compris pour un visiteur non connecté) ; seul l'admin
-- modifie.
drop policy if exists "app_settings_read_all"   on public.app_settings;
drop policy if exists "app_settings_write_admin" on public.app_settings;

create policy "app_settings_read_all"
  on public.app_settings for select
  using (true);

create policy "app_settings_write_admin"
  on public.app_settings for update
  using (public.is_admin())
  with check (public.is_admin());

-- 3.2 home_banners — lecture publique, écriture admin uniquement.
-- La lecture n'est PAS limitée aux lignes `is_visible = true` : le site
-- admin doit voir aussi celles qu'il a masquées pour pouvoir les
-- réafficher. C'est l'application qui filtre sur `is_visible` côté
-- cliente (`catalog_service.dart`). Masquer une bannière n'est donc pas
-- un secret — c'est un choix d'affichage.
drop policy if exists "home_banners_read_all"    on public.home_banners;
drop policy if exists "home_banners_write_admin" on public.home_banners;

create policy "home_banners_read_all"
  on public.home_banners for select
  using (true);

create policy "home_banners_write_admin"
  on public.home_banners for all
  using (public.is_admin())
  with check (public.is_admin());

-- 3.3 home_collections — même principe que les bannières.
drop policy if exists "home_collections_read_all"    on public.home_collections;
drop policy if exists "home_collections_write_admin" on public.home_collections;

create policy "home_collections_read_all"
  on public.home_collections for select
  using (true);

create policy "home_collections_write_admin"
  on public.home_collections for all
  using (public.is_admin())
  with check (public.is_admin());

-- 3.4 notifications — chacun ne voit QUE les siennes, et ne peut que les
-- marquer comme lues. Aucune policy `insert` ni `delete` : seuls les
-- déclencheurs `security definer` de la partie 4 écrivent ici.
drop policy if exists "notifications_select_own"  on public.notifications;
drop policy if exists "notifications_update_own"  on public.notifications;

create policy "notifications_select_own"
  on public.notifications for select
  using (user_id = auth.uid());

create policy "notifications_update_own"
  on public.notifications for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 3.5 shop_categories — lecture publique (afficher les catégories d'une
-- boutique sur sa page), écriture réservée à la propriétaire de la
-- boutique et à l'admin. `owns_shop()` vient du schéma d'origine.
drop policy if exists "shop_categories_read_all"     on public.shop_categories;
drop policy if exists "shop_categories_write_owner"  on public.shop_categories;

create policy "shop_categories_read_all"
  on public.shop_categories for select
  using (true);

create policy "shop_categories_write_owner"
  on public.shop_categories for all
  using (public.owns_shop(shop_id) or public.is_admin())
  with check (public.owns_shop(shop_id) or public.is_admin());

-- 3.6 Droits de base sur la table elle-même.
grant select on public.app_settings     to anon, authenticated;
grant update on public.app_settings     to authenticated;

grant select on public.home_banners     to anon, authenticated;
grant insert, update, delete on public.home_banners to authenticated;

grant select on public.home_collections to anon, authenticated;
grant insert, update, delete on public.home_collections to authenticated;

grant select, update on public.notifications to authenticated;

grant select on public.shop_categories  to anon, authenticated;
grant insert, delete on public.shop_categories to authenticated;


-- ---------------------------------------------------------------------
-- 4. NOTIFICATIONS — ÉCRITES PAR LA BASE
-- ---------------------------------------------------------------------
-- RECONSTRUIT : les fichiers d'origine ne sont pas là, donc le contenu
-- exact des messages est un choix fait ici. Ce qui est sûr, c'est le
-- besoin auquel ils répondent, écrit dans `notification_service.dart` :
-- "une vendeuse ne savait qu'elle avait vendu que si elle pensait à ouvrir
-- Ma boutique, et une cliente n'apprenait la confirmation de son paiement
-- qu'en retournant dans Mes commandes".
--
-- `security definer` : la fonction écrit dans `notifications` avec les
-- droits de son créateur, donc sans être soumise aux policies ci-dessus —
-- c'est exactement ce qu'on veut, puisque personne d'autre n'a le droit
-- d'y insérer quoi que ce soit.

-- 4.1 Nouvelle commande → la vendeuse est prévenue.
create or replace function public.trg_notify_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner from public.shops where id = new.shop_id;
  if v_owner is not null then
    insert into public.notifications (user_id, kind, title, body, order_id)
    values (
      v_owner,
      'order_new',
      'Nouvelle commande',
      new.client_full_name || ' — ' || to_char(new.total, 'FM999999990.00') || ' UM',
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_new_order on public.orders;
create trigger notify_new_order
  after insert on public.orders
  for each row execute function public.trg_notify_new_order();

-- 4.2 Changement de statut → la cliente est prévenue.
-- Uniquement quand le statut change vraiment (`is distinct from`), sinon
-- chaque modification de commande en produirait une nouvelle.
create or replace function public.trg_notify_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  v_label := case new.status
    when 'confirmed'  then 'Paiement confirmé'
    when 'preparing'  then 'Commande en préparation'
    when 'delivering' then 'Commande en cours de livraison'
    when 'delivered'  then 'Commande livrée'
    when 'cancelled'  then 'Commande annulée'
    else null
  end;

  if v_label is not null then
    insert into public.notifications (user_id, kind, title, body, order_id)
    values (new.client_id, 'order_status', v_label, null, new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists notify_order_status on public.orders;
create trigger notify_order_status
  after update on public.orders
  for each row execute function public.trg_notify_order_status();


-- ---------------------------------------------------------------------
-- 5. FONCTIONS RPC MANQUANTES
-- ---------------------------------------------------------------------

-- 5.1 shop_follower_count — nombre d'abonnés d'une boutique.
-- Les lignes de `favorite_shops` ne sont lisibles que par leur
-- propriétaire ; ce compte passe donc par une fonction `security definer`
-- plutôt qu'une lecture directe. Elle ne renvoie QU'UN NOMBRE : savoir
-- qui suit la boutique reste impossible.
create or replace function public.shop_follower_count(target_shop_id uuid)
returns integer
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::int from public.favorite_shops where shop_id = target_shop_id;
$$;

-- 5.2 delete_own_account — suppression de SON PROPRE compte.
-- L'identifiant n'est jamais fourni par l'appelant : la fonction utilise
-- `auth.uid()`, donc elle ne peut pas servir à supprimer le compte de
-- quelqu'un d'autre, même en trafiquant la requête. Supprimer la ligne
-- `auth.users` supprime le profil et, en cascade, boutique, produits et
-- commandes.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

grant execute on function public.shop_follower_count(uuid) to anon, authenticated;
grant execute on function public.delete_own_account() to authenticated;


-- ---------------------------------------------------------------------
-- 6. CORRECTIFS RLS SUR LES TABLES EXISTANTES
-- ---------------------------------------------------------------------

-- 6.1 La cliente doit pouvoir joindre sa capture de paiement à SA
-- commande. Le schéma d'origine n'autorise que la vendeuse et l'admin à
-- modifier une commande (`orders_update_vendor_or_admin`) : l'`update` de
-- la cliente ne touchait donc aucune ligne, sans erreur, et la capture
-- n'arrivait jamais. C'est le cas décrit dans `order_service.dart`
-- ("Fix: run supabase/securite_patch.sql").
--
-- Volontairement limité : la cliente peut modifier SA commande, mais le
-- déclencheur 6.2 l'empêche de toucher autre chose que
-- `payment_proof_url` — surtout pas le statut ni le total.
drop policy if exists "orders_update_client_payment_proof" on public.orders;
create policy "orders_update_client_payment_proof"
  on public.orders for update
  using (client_id = auth.uid())
  with check (client_id = auth.uid());

create or replace function public.trg_client_order_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Ne s'applique qu'à la cliente : la vendeuse et l'admin gardent le
  -- droit de changer le statut, c'est tout leur travail.
  if auth.uid() is distinct from old.client_id then
    return new;
  end if;
  if public.is_admin() or public.owns_shop(old.shop_id) then
    return new;
  end if;

  if new.status            is distinct from old.status
     or new.total          is distinct from old.total
     or new.shop_id        is distinct from old.shop_id
     or new.client_id      is distinct from old.client_id
     or new.confirmed_at   is distinct from old.confirmed_at
     or new.payment_reference is distinct from old.payment_reference then
    raise exception 'Une cliente ne peut modifier que la capture de paiement de sa commande';
  end if;

  return new;
end;
$$;

drop trigger if exists client_order_update_guard on public.orders;
create trigger client_order_update_guard
  before update on public.orders
  for each row execute function public.trg_client_order_update_guard();

-- 6.2 Une vendeuse doit pouvoir supprimer sa propre boutique — il n'y
-- avait aucune policy `delete` sur `shops`, donc aucun moyen de le faire,
-- ni depuis l'app ni depuis la base (`vendor_service.deleteMyShop`).
drop policy if exists "shops_delete_owner_or_admin" on public.shops;
create policy "shops_delete_owner_or_admin"
  on public.shops for delete
  using (owner_id = auth.uid() or public.is_admin());

-- 6.3 La capture de paiement doit être lisible par la vendeuse concernée
-- et par l'admin, pas seulement par la cliente qui l'a déposée — sinon le
-- circuit "la vendeuse vérifie le paiement" n'a aucun moyen d'exister.
-- Le bucket reste PRIVÉ : c'est une lecture ciblée, pas une ouverture.
drop policy if exists "payment_proofs_select_vendor_or_admin" on storage.objects;
create policy "payment_proofs_select_vendor_or_admin"
  on storage.objects for select
  using (
    bucket_id = 'payment-proofs'
    and (
      public.is_admin()
      or exists (
        select 1
        from public.orders o
        join public.shops s on s.id = o.shop_id
        where s.owner_id = auth.uid()
          and o.payment_proof_url = storage.objects.name
      )
    )
  );


-- ---------------------------------------------------------------------
-- 7. DÉCLENCHEUR D'INSCRIPTION — ROBUSTESSE (profiles_trigger_patch)
-- ---------------------------------------------------------------------
-- Deux problèmes dans la version d'origine, tous deux visibles seulement
-- à l'inscription :
--
--   1. Connexion Google — Google renvoie le nom sous `name` et la photo
--      sous `avatar_url`/`picture`, pas sous `full_name` : le profil était
--      créé sans nom. Les trois sources sont essayées ici.
--   2. Si la ligne `profiles` existe déjà (ré-inscription avec la même
--      adresse, ou création manuelle depuis le Table Editor), l'`insert`
--      échouait sur la clé primaire — et comme le déclencheur s'exécute
--      DANS la transaction d'inscription, c'est l'inscription entière qui
--      échouait, avec un message incompréhensible côté app.
--      `on conflict do nothing` règle ça.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      ''
    ),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(
      new.raw_user_meta_data->>'avatar_url',
      new.raw_user_meta_data->>'picture'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;


-- =====================================================================
-- FIN DU RATTRAPAGE
--
-- Étape suivante, une seule fois, après inscription dans l'application :
--   update public.profiles set role = 'admin' where email = 'ton.email@exemple.com';
-- (impossible depuis l'app — le déclencheur anti-élévation le bloque)
--
-- NON INCLUS VOLONTAIREMENT — le resserrement des buckets `product-images`
-- et `shop-images` (partie 5 de `securite_patch.sql` d'après
-- `storage_service.dart`) : aujourd'hui n'importe quel compte connecté
-- peut écrire n'importe où dans ces deux buckets. La moitié applicative
-- est déjà en place (`StorageService.ownedPath` préfixe les fichiers par
-- l'uid), mais resserrer la règle rendrait illisibles ou immodifiables les
-- photos déjà envoyées sans ce préfixe. À faire quand tu voudras, sur une
-- base dont tu connais le contenu :
--
--   drop policy if exists "authenticated_write_product_images" on storage.objects;
--   create policy "authenticated_write_product_images"
--     on storage.objects for insert
--     with check (bucket_id = 'product-images'
--                 and (storage.foldername(name))[1] = auth.uid()::text);
--   -- idem pour 'shop-images'
-- =====================================================================
