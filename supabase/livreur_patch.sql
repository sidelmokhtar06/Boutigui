-- =====================================================================
-- ESPACE "LIVREUR" — 15 septembre 2026, demande explicite.
--
-- À exécuter une fois dans Supabase > SQL Editor, APRÈS
-- marketplace_schema.sql (et les patchs précédents déjà en place :
-- merchant_code/merchant_provider sur `shops`, delivery_lat/delivery_lng/
-- delivery_mode et payment_reference sur `orders`, déjà utilisés par
-- l'application avant ce patch — pas re-déclarés ici).
--
-- Ce que ce patch ajoute :
--   1. Un point de collecte (lat/lng) sur chaque boutique, que la vendeuse
--      renseigne une fois dans "Ma boutique" (comme la cliente le fait déjà
--      au moment de payer).
--   2. Un profil livreur très simple (`driver_profiles`) : l'existence
--      d'une ligne suffit à dire "ce compte est aussi livreur", exactement
--      comme une ligne dans `shops` suffit à dire "ce compte est aussi
--      vendeuse" (voir role_controller.dart) — pas de nouvelle colonne de
--      rôle sur `profiles`.
--   3. Un tableau de courses (`delivery_requests`) : une ligne par
--      commande à livrer, avec le point de départ (la boutique), le point
--      d'arrivée (la position donnée par la cliente au moment de payer,
--      voir `orders.delivery_lat/lng`) et la distance en kilomètres,
--      calculée CÔTÉ BASE (trigger ci-dessous) plutôt que fournie par
--      l'app, pour ne jamais dépendre d'un calcul fait sur le téléphone.
--   4. Deux fonctions RPC (`accept_delivery_request`,
--      `mark_delivery_delivered`) qui font les seules transitions de statut
--      permises, de façon atomique (impossible que deux livreurs acceptent
--      la même course), et une troisième (`get_delivery_contact`) qui est
--      le SEUL moyen d'obtenir le nom/téléphone/adresse de la cliente — et
--      seulement pour le livreur qui a accepté CETTE course précise. Tant
--      qu'une course est seulement "en attente", `delivery_requests` ne
--      contient que la boutique et un point sur la carte : aucune donnée
--      personnelle n'y est jamais stockée, donc aucune fuite possible même
--      par une faute de policy.
--   5. La réplication en temps réel sur `delivery_requests`, pour que les
--      livreuses disponibles voient une nouvelle course apparaître dès
--      qu'elle est créée, sans recharger l'écran (Supabase Realtime,
--      utilisé côté app via `stream()` / `channel()` — voir
--      lib/services/delivery_service.dart).
--
-- Limite honnête à connaître : ceci notifie les livreuses EN TEMPS RÉEL
-- tant que l'application est ouverte (comme le reste de l'app, qui n'a pas
-- de notifications push natives). Une vraie notification qui réveille le
-- téléphone même appli fermée demanderait Firebase Cloud Messaging (ou le
-- Web Push du navigateur), qui n'est pas configuré dans ce projet et
-- demanderait ses propres identifiants côté Emina.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Point de collecte de chaque boutique
-- ---------------------------------------------------------------------
alter table public.shops
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- ---------------------------------------------------------------------
-- 2. Profil livreur
-- ---------------------------------------------------------------------
create table if not exists public.driver_profiles (
  id           uuid primary key references public.profiles(id) on delete cascade,
  vehicle_type text,                 -- libre : "moto", "voiture", "vélo"...
  is_available boolean not null default false,
  created_at   timestamptz not null default now()
);

alter table public.driver_profiles enable row level security;

drop policy if exists "driver_profiles_select_own" on public.driver_profiles;
create policy "driver_profiles_select_own"
  on public.driver_profiles for select
  using (id = auth.uid() or exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'
  ));

drop policy if exists "driver_profiles_insert_own" on public.driver_profiles;
create policy "driver_profiles_insert_own"
  on public.driver_profiles for insert
  with check (id = auth.uid());

drop policy if exists "driver_profiles_update_own" on public.driver_profiles;
create policy "driver_profiles_update_own"
  on public.driver_profiles for update
  using (id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Tableau de courses — AUCUNE colonne d'identité cliente ici, par
--    construction (voir le point 4 du commentaire en tête de fichier).
-- ---------------------------------------------------------------------
create table if not exists public.delivery_requests (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  shop_id      uuid not null references public.shops(id) on delete cascade,
  pickup_lat   double precision,
  pickup_lng   double precision,
  dropoff_lat  double precision,
  dropoff_lng  double precision,
  distance_km  numeric,
  status       text not null default 'pending'
                 check (status in ('pending','accepted','delivered','cancelled')),
  driver_id    uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  delivered_at timestamptz,
  unique (order_id)
);

create index if not exists delivery_requests_status_idx on public.delivery_requests (status);
create index if not exists delivery_requests_driver_idx on public.delivery_requests (driver_id);

alter table public.delivery_requests enable row level security;

-- Lecture : le tableau des courses EN ATTENTE est ouvert à toute personne
-- connectée (c'est le principe même d'un tableau de courses à accepter),
-- plus la course déjà acceptée par CE livreur, plus la boutique et la
-- cliente concernées, plus l'admin.
drop policy if exists "delivery_requests_select" on public.delivery_requests;
create policy "delivery_requests_select"
  on public.delivery_requests for select
  using (
    status = 'pending'
    or driver_id = auth.uid()
    or exists (select 1 from public.orders o where o.id = order_id and o.client_id = auth.uid())
    or exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Création : seule la cliente propriétaire de la commande peut créer sa
-- course (fait automatiquement au moment de payer, voir
-- lib/services/order_service.dart, `checkout`).
drop policy if exists "delivery_requests_insert_client" on public.delivery_requests;
create policy "delivery_requests_insert_client"
  on public.delivery_requests for insert
  with check (exists (select 1 from public.orders o where o.id = order_id and o.client_id = auth.uid()));

-- Pas de policy UPDATE/DELETE ouverte aux clients ou aux livreurs : les
-- seules transitions permises passent par les fonctions ci-dessous
-- (`security definer`, donc elles s'exécutent avec les droits du
-- créateur des tables — typiquement `postgres`, qui n'est pas soumis aux
-- policies RLS — exactement comme `delete_own_account()` dans
-- admin_patch.sql).

-- Distance recalculée CÔTÉ BASE à chaque insertion/mise à jour des
-- coordonnées — la valeur envoyée par l'app n'est qu'indicative, jamais
-- source de vérité (formule de Haversine, rayon terrestre moyen 6371 km).
create or replace function public.trg_delivery_request_distance()
returns trigger
language plpgsql
as $$
declare
  v_r constant double precision := 6371;
  v_dlat double precision;
  v_dlng double precision;
  v_a double precision;
begin
  if new.pickup_lat is null or new.pickup_lng is null
     or new.dropoff_lat is null or new.dropoff_lng is null then
    new.distance_km := null;
    return new;
  end if;
  v_dlat := radians(new.dropoff_lat - new.pickup_lat);
  v_dlng := radians(new.dropoff_lng - new.pickup_lng);
  v_a := sin(v_dlat / 2) ^ 2
       + cos(radians(new.pickup_lat)) * cos(radians(new.dropoff_lat)) * sin(v_dlng / 2) ^ 2;
  new.distance_km := round((v_r * 2 * atan2(sqrt(v_a), sqrt(1 - v_a)))::numeric, 2);
  return new;
end;
$$;

drop trigger if exists delivery_requests_distance on public.delivery_requests;
create trigger delivery_requests_distance
  before insert or update of pickup_lat, pickup_lng, dropoff_lat, dropoff_lng
  on public.delivery_requests
  for each row execute function public.trg_delivery_request_distance();

-- ---------------------------------------------------------------------
-- 4. RPC — les seules portes d'entrée pour accepter une course, la
--    marquer livrée, ou lire le contact de la cliente.
-- ---------------------------------------------------------------------

-- Acceptation atomique : si deux livreuses appuient au même moment, une
-- seule gagne (la clause `where status = 'pending'` de l'UPDATE ne peut
-- réussir qu'une fois) — l'autre reçoit l'exception ci-dessous plutôt
-- qu'un succès trompeur.
create or replace function public.accept_delivery_request(p_request_id uuid)
returns public.delivery_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.delivery_requests;
begin
  if not exists (select 1 from public.driver_profiles where id = auth.uid()) then
    raise exception 'Only a registered driver can accept a delivery.';
  end if;

  update public.delivery_requests
     set driver_id = auth.uid(),
         status = 'accepted',
         accepted_at = now()
   where id = p_request_id
     and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'This delivery has already been taken by another driver.';
  end if;

  update public.orders set status = 'delivering' where id = v_row.order_id;

  return v_row;
end;
$$;

create or replace function public.mark_delivery_delivered(p_request_id uuid)
returns public.delivery_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.delivery_requests;
begin
  update public.delivery_requests
     set status = 'delivered',
         delivered_at = now()
   where id = p_request_id
     and driver_id = auth.uid()
     and status = 'accepted'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Delivery not found or not assigned to you.';
  end if;

  update public.orders set status = 'delivered' where id = v_row.order_id;

  return v_row;
end;
$$;

-- Seul moyen d'obtenir le nom/téléphone/adresse de la cliente : uniquement
-- pour le livreur assigné à CETTE course, jamais avant acceptation, jamais
-- pour un autre livreur.
create or replace function public.get_delivery_contact(p_request_id uuid)
returns table(client_full_name text, client_phone text, client_address text, client_city text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select o.client_full_name, o.client_phone, o.client_address, o.client_city
    from public.delivery_requests d
    join public.orders o on o.id = d.order_id
    where d.id = p_request_id
      and d.driver_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Temps réel — pour que le tableau de courses des livreuses se mette à
--    jour tout seul (nouvelle course, course prise par quelqu'un d'autre).
-- ---------------------------------------------------------------------
do $$
begin
  execute 'alter publication supabase_realtime add table public.delivery_requests';
exception when duplicate_object then
  null; -- déjà ajoutée (patch relancé une deuxième fois) : rien à faire
end $$;
