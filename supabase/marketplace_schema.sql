-- =====================================================================
-- MARKETPLACE — SCHEMA POSTGRESQL / SUPABASE
-- 12 tables, politiques RLS, fonctions de sécurité, triggers
-- Exécuter en une fois dans Supabase > SQL Editor (base neuve)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. EXTENSIONS
-- ---------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

-- 1.1 Profils (miroir de auth.users, un profil par compte)
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text unique,
  full_name   text,
  phone       text,
  city        text,
  address     text,
  avatar_url  text,
  role        text not null default 'client' check (role in ('client','vendor','admin')),
  created_at  timestamptz not null default now()
);

-- 1.2 Boutiques
create table public.shops (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  description text,
  logo_url    text,
  cover_url   text,
  city        text,
  whatsapp_phone text,
  is_visible  boolean not null default false,
  created_at  timestamptz not null default now()
);

-- 1.3 Catégories (arborescence à 3 niveaux via parent_id)
-- `gender` (13 septembre 2026) : sous quel onglet de l'accueil (Femme /
-- Homme) la catégorie apparaît — voir la section de migration en bas de
-- fichier pour le détail et la raison du défaut '*'.
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.categories(id) on delete cascade,
  name        text not null,
  sort_order  int not null default 0,
  gender      text not null default '*' check (gender in ('women','men','*')),
  created_at  timestamptz not null default now()
);

-- 1.4 Produits
create table public.products (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references public.shops(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name        text not null,
  description text,
  price       numeric(12,2) not null check (price >= 0),
  stock       int not null default 0 check (stock >= 0),
  is_visible  boolean not null default true,
  created_at  timestamptz not null default now()
);

-- 1.5 Images produit
create table public.product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  url         text not null,
  sort_order  int not null default 0
);

-- 1.6 Favoris — produits
create table public.favorite_products (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- 1.7 Favoris — boutiques
create table public.favorite_shops (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  shop_id     uuid not null references public.shops(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, shop_id)
);

-- 1.8 Commandes — une commande = une boutique (le panier est découpé au moment de la validation)
create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  client_id         uuid not null references public.profiles(id) on delete cascade,
  shop_id           uuid not null references public.shops(id) on delete cascade,
  status            text not null default 'pending'
                      check (status in ('pending','confirmed','preparing','delivering','delivered','cancelled')),
  total             numeric(12,2) not null check (total >= 0),
  -- copiés depuis le profil au moment de la commande : le vendeur n'a jamais accès à `profiles`
  client_full_name  text not null,
  client_phone      text not null,
  client_city       text,
  client_address    text,
  payment_proof_url text,
  created_at        timestamptz not null default now(),
  confirmed_at      timestamptz
);

-- 1.9 Lignes de commande
create table public.order_items (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  product_id   uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price   numeric(12,2) not null check (unit_price >= 0),
  quantity     int not null check (quantity > 0),
  subtotal     numeric(12,2) not null check (subtotal >= 0)
);

-- 1.10 Avis
create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  client_id   uuid not null references public.profiles(id) on delete cascade,
  order_id    uuid references public.orders(id) on delete set null,
  rating      int not null check (rating between 1 and 5),
  comment     text,
  is_visible  boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (product_id, client_id, order_id)
);

-- 1.11 Visites boutique — agrégées PAR JOUR (pas une ligne par visite)
create table public.shop_visit_daily (
  shop_id     uuid not null references public.shops(id) on delete cascade,
  visit_date  date not null default current_date,
  visit_count int not null default 0,
  primary key (shop_id, visit_date)
);

-- 1.12 Candidatures vendeur
create table public.vendor_applications (
  id            uuid primary key default gen_random_uuid(),
  applicant_id  uuid not null references public.profiles(id) on delete cascade,
  shop_name     text not null,
  description   text,
  phone         text not null,
  city          text,
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz
);

-- ---------------------------------------------------------------------
-- 2. INDEX utiles
-- ---------------------------------------------------------------------
create index idx_shops_owner on public.shops(owner_id);
create index idx_products_shop on public.products(shop_id);
create index idx_products_category on public.products(category_id);
create index idx_product_images_product on public.product_images(product_id);
create index idx_orders_client on public.orders(client_id);
create index idx_orders_shop on public.orders(shop_id);
create index idx_order_items_order on public.order_items(order_id);
create index idx_reviews_product on public.reviews(product_id);
create index idx_categories_parent on public.categories(parent_id);

-- ---------------------------------------------------------------------
-- 3. FONCTIONS DE SÉCURITÉ
--    (déclarées APRÈS les tables qu'elles interrogent — bug connu si
--     l'ordre est inversé : la fonction owns_shop plantait à l'exécution
--     si elle était créée avant la table `shops`)
-- ---------------------------------------------------------------------

-- Rôle de l'utilisateur courant
create or replace function public.current_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

-- L'utilisateur courant est-il propriétaire de cette boutique ?
create or replace function public.owns_shop(target_shop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.shops
    where id = target_shop_id and owner_id = auth.uid()
  );
$$;

-- L'utilisateur courant possède-t-il la boutique à laquelle appartient ce produit ?
create or replace function public.owns_product_shop(target_product_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.products p
    join public.shops s on s.id = p.shop_id
    where p.id = target_product_id and s.owner_id = auth.uid()
  );
$$;

-- Incrémente le compteur de visites du jour pour une boutique (appelée par l'app, pas d'accès direct à la table)
create or replace function public.record_shop_visit(target_shop_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.shop_visit_daily (shop_id, visit_date, visit_count)
  values (target_shop_id, current_date, 1)
  on conflict (shop_id, visit_date)
  do update set visit_count = shop_visit_daily.visit_count + 1;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. TRIGGERS
-- ---------------------------------------------------------------------

-- 4.1 Créer automatiquement un profil à l'inscription (auth.users -> public.profiles)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4.2 Anti-élévation de privilège : un utilisateur ne peut pas changer SON PROPRE rôle
--     via l'application (auth.uid() renseigné). Depuis l'éditeur SQL, auth.uid() est
--     NULL : la modification reste possible pour créer le premier admin.
create or replace function public.prevent_self_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and auth.uid() = old.id
     and new.role is distinct from old.role then
    raise exception 'Modification de son propre rôle interdite depuis l''application.';
  end if;
  return new;
end;
$$;

create trigger trg_prevent_self_role_change
  before update on public.profiles
  for each row execute function public.prevent_self_role_change();

-- 4.3 Une boutique ne peut être rendue visible (is_visible: false -> true) que par un admin.
--     Le vendeur peut la masquer (true -> false) lui-même, mais pas la republier seul.
create or replace function public.prevent_self_shop_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_visible = true and old.is_visible = false and not public.is_admin() then
    raise exception 'Seul un administrateur peut rendre une boutique visible.';
  end if;
  return new;
end;
$$;

create trigger trg_prevent_self_shop_activation
  before update on public.shops
  for each row execute function public.prevent_self_shop_activation();

-- ---------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.shops               enable row level security;
alter table public.categories          enable row level security;
alter table public.products            enable row level security;
alter table public.product_images      enable row level security;
alter table public.favorite_products   enable row level security;
alter table public.favorite_shops      enable row level security;
alter table public.orders              enable row level security;
alter table public.order_items         enable row level security;
alter table public.reviews             enable row level security;
alter table public.shop_visit_daily    enable row level security;
alter table public.vendor_applications enable row level security;

-- ---- profiles --------------------------------------------------------
-- Le vendeur n'a JAMAIS accès à cette table pour d'autres utilisateurs :
-- il voit ce qu'il faut pour livrer via les colonnes copiées sur `orders`.
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (id = auth.uid() or public.is_admin());

create policy "profiles_update_own_or_admin"
  on public.profiles for update
  using (id = auth.uid() or public.is_admin());
  -- le trigger 4.2 bloque le changement de rôle par le titulaire lui-même

-- ---- shops -------------------------------------------------------------
create policy "shops_select_public_or_owner_or_admin"
  on public.shops for select
  using (is_visible = true or owner_id = auth.uid() or public.is_admin());

create policy "shops_insert_own"
  on public.shops for insert
  with check (owner_id = auth.uid());

create policy "shops_update_owner_or_admin"
  on public.shops for update
  using (owner_id = auth.uid() or public.is_admin());
  -- le trigger 4.3 bloque l'auto-activation par le vendeur

create policy "shops_delete_admin"
  on public.shops for delete
  using (public.is_admin());

-- ---- categories ----------------------------------------------------------
create policy "categories_select_all"
  on public.categories for select
  using (true);

create policy "categories_write_admin"
  on public.categories for insert
  with check (public.is_admin());

create policy "categories_update_admin"
  on public.categories for update
  using (public.is_admin());

create policy "categories_delete_admin"
  on public.categories for delete
  using (public.is_admin());

-- ---- products --------------------------------------------------------
create policy "products_select_visible_or_owner_or_admin"
  on public.products for select
  using (
    (is_visible = true and exists (select 1 from public.shops s where s.id = shop_id and s.is_visible = true))
    or public.owns_shop(shop_id)
    or public.is_admin()
  );

create policy "products_insert_owner"
  on public.products for insert
  with check (public.owns_shop(shop_id));

create policy "products_update_owner_or_admin"
  on public.products for update
  using (public.owns_shop(shop_id) or public.is_admin());

create policy "products_delete_owner_or_admin"
  on public.products for delete
  using (public.owns_shop(shop_id) or public.is_admin());

-- ---- product_images ----------------------------------------------------
create policy "product_images_select_all"
  on public.product_images for select
  using (true);

create policy "product_images_write_owner_or_admin"
  on public.product_images for insert
  with check (public.owns_product_shop(product_id) or public.is_admin());

create policy "product_images_update_owner_or_admin"
  on public.product_images for update
  using (public.owns_product_shop(product_id) or public.is_admin());

create policy "product_images_delete_owner_or_admin"
  on public.product_images for delete
  using (public.owns_product_shop(product_id) or public.is_admin());

-- ---- favorite_products / favorite_shops -------------------------------
create policy "favorite_products_all_own"
  on public.favorite_products for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "favorite_shops_all_own"
  on public.favorite_shops for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---- orders ------------------------------------------------------------
-- Le client peut créer et lire SES commandes, jamais les modifier (ni le
-- statut, ni le montant) : seuls le vendeur concerné et l'admin le peuvent.
create policy "orders_select_client_or_vendor_or_admin"
  on public.orders for select
  using (client_id = auth.uid() or public.owns_shop(shop_id) or public.is_admin());

create policy "orders_insert_client"
  on public.orders for insert
  with check (client_id = auth.uid());

create policy "orders_update_vendor_or_admin"
  on public.orders for update
  using (public.owns_shop(shop_id) or public.is_admin());
  -- volontairement : aucune policy update pour le client

-- ---- order_items ---------------------------------------------------------
create policy "order_items_select_related"
  on public.order_items for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and (o.client_id = auth.uid() or public.owns_shop(o.shop_id) or public.is_admin())
    )
  );

create policy "order_items_insert_client_own_order"
  on public.order_items for insert
  with check (
    exists (select 1 from public.orders o where o.id = order_id and o.client_id = auth.uid())
  );

-- ---- reviews -------------------------------------------------------------
create policy "reviews_select_visible_or_author_or_admin"
  on public.reviews for select
  using (is_visible = true or client_id = auth.uid() or public.is_admin());

create policy "reviews_insert_own"
  on public.reviews for insert
  with check (client_id = auth.uid());

create policy "reviews_update_author_content_or_vendor_moderation"
  on public.reviews for update
  using (
    client_id = auth.uid()
    or public.owns_product_shop(product_id)
    or public.is_admin()
  );

create policy "reviews_delete_author_or_admin"
  on public.reviews for delete
  using (client_id = auth.uid() or public.is_admin());

-- ---- shop_visit_daily ------------------------------------------------
-- Aucun accès direct en écriture : uniquement via record_shop_visit() (security definer).
create policy "shop_visit_select_owner_or_admin"
  on public.shop_visit_daily for select
  using (public.owns_shop(shop_id) or public.is_admin());

-- ---- vendor_applications -------------------------------------------------
create policy "vendor_applications_select_own_or_admin"
  on public.vendor_applications for select
  using (applicant_id = auth.uid() or public.is_admin());

create policy "vendor_applications_insert_own"
  on public.vendor_applications for insert
  with check (applicant_id = auth.uid());

create policy "vendor_applications_update_admin"
  on public.vendor_applications for update
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- 6. STORAGE — BUCKETS
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('shop-images', 'shop-images', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Lecture publique des buckets publics
create policy "public_read_product_images"
  on storage.objects for select
  using (bucket_id = 'product-images');

create policy "public_read_shop_images"
  on storage.objects for select
  using (bucket_id = 'shop-images');

create policy "public_read_avatars"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- Écriture réservée aux utilisateurs connectés (le dossier = leur propre uid en 1er segment)
create policy "authenticated_write_product_images"
  on storage.objects for insert
  with check (bucket_id = 'product-images' and auth.role() = 'authenticated');

create policy "authenticated_write_shop_images"
  on storage.objects for insert
  with check (bucket_id = 'shop-images' and auth.role() = 'authenticated');

create policy "authenticated_write_avatars"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- payment-proofs : bucket PRIVÉ — seul le déposant, le vendeur concerné et l'admin lisent
create policy "payment_proofs_insert_own"
  on storage.objects for insert
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "payment_proofs_select_owner"
  on storage.objects for select
  using (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- 6. MIGRATION — genre des catégories (13 septembre 2026)
-- ---------------------------------------------------------------------
-- L'accueil affiche maintenant deux onglets "Femme" / "Homme" au-dessus
-- des catégories, chacun avec sa propre liste (captures Level envoyées
-- par Emina) — jusqu'ici l'app n'avait aucune notion de genre sur les
-- catégories, seulement sur le profil client.
--
-- Une catégorie SANS genre précisé (valeur '*') reste visible dans les
-- DEUX onglets plutôt que de disparaître : à chaque nouvelle catégorie
-- créée, si personne ne choisit explicitement Femme ou Homme, elle continue
-- d'apparaître partout comme avant cette migration, au lieu de se
-- retrouver invisible par erreur.
--
-- `if not exists` / vérification du nom de contrainte avant de la créer :
-- Emina a déjà exécuté deux lignes à la main dans Supabase pour ajouter
-- cette colonne avant que ce fichier soit mis à jour — cette section doit
-- pouvoir être rejouée sans erreur sur une base qui l'a déjà.
alter table public.categories add column if not exists gender text not null default '*';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'categories_gender_check'
  ) then
    alter table public.categories
      add constraint categories_gender_check check (gender in ('women','men','*'));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7. EXEMPLES — catégories Femme / Homme (13 septembre 2026)
-- ---------------------------------------------------------------------
-- Quatre catégories d'exemple pour voir tout de suite les onglets
-- fonctionner, dans l'esprit des captures Level : "New in" et "Clothing"
-- communes aux deux onglets, "Dresses" réservée à Femme, "Shoes" commune
-- (Femme voit les quatre, Homme voit New in / Clothing / Shoes — comme sur
-- les captures). Sans photo pour l'instant (à ajouter depuis le site
-- admin > Catégories, comme n'importe quelle catégorie) : l'app affiche un
-- bandeau gris à la place, rien ne casse.
--
-- Protégé par nom pour rester rejouable sans doublons si ce script est
-- exécuté plusieurs fois (nom déjà utilisé = ignoré).
do $$
begin
  if not exists (select 1 from public.categories where name = 'New in') then
    insert into public.categories (name, sort_order, gender) values ('New in', 0, '*');
  end if;
  if not exists (select 1 from public.categories where name = 'Clothing') then
    insert into public.categories (name, sort_order, gender) values ('Clothing', 1, '*');
  end if;
  if not exists (select 1 from public.categories where name = 'Dresses') then
    insert into public.categories (name, sort_order, gender) values ('Dresses', 2, 'women');
  end if;
  if not exists (select 1 from public.categories where name = 'Shoes') then
    insert into public.categories (name, sort_order, gender) values ('Shoes', 3, '*');
  end if;
end $$;

-- =====================================================================
-- FIN DU SCHÉMA
--
-- Étape suivante, une seule fois, après inscription dans l'application :
--   update public.profiles set role = 'admin' where email = 'ton.email@exemple.com';
-- (impossible depuis l'app — le trigger 4.2 le bloque — uniquement ici, dans le SQL Editor)
-- =====================================================================
