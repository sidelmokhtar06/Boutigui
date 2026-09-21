-- =====================================================================
-- fintech_patch.sql — 20 septembre 2026
--
-- Couche fintech : intégrité des montants côté serveur et statut de
-- paiement. À coller dans l'éditeur SQL de Supabase APRÈS
-- `rattrapage_patch.sql` (il s'appuie sur `payment_reference`, sur
-- `client_order_update_guard` et sur les colonnes `merchant_*`).
--
-- Comme tous les fichiers de ce dossier : rejouable sans risque.
--
-- Deux trous réels étaient ouverts avant ce fichier :
--
--  1. `unit_price`, `subtotal` et `orders.total` étaient entièrement
--     fournis par le client (voir `order_service.checkout`). La base ne
--     vérifiait que `>= 0`. Un client modifié pouvait donc commander
--     n'importe quoi à 1 MRU, et la vendeuse voyait une commande qui
--     semblait payée. C'est la faille la plus grave du projet.
--  2. Il n'existait aucun état de PAIEMENT. La colonne `status` décrit
--     l'avancement de la commande (préparation, livraison) et l'espace
--     Livreur s'appuie dessus — l'élargir casserait `livreur_patch.sql`.
--     D'où des colonnes séparées plutôt qu'une énumération élargie.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. STATUT DE PAIEMENT
-- ---------------------------------------------------------------------

-- Pas d'état « en attente de paiement » : `order_service.checkout` refuse
-- de créer la commande sans référence, et l'index unique
-- `orders_payment_reference_unique` refuse une référence déjà vue. Une
-- commande naît donc toujours avec une référence soumise ; ce qui reste à
-- décider, c'est si la vendeuse la retrouve bien dans son historique
-- bancaire.
--
-- `payment_provider` est recopié depuis la boutique au moment de la
-- commande, comme `client_full_name` : la vendeuse peut changer de banque
-- plus tard, la commande doit garder le service par lequel elle a été
-- payée.
alter table public.orders
  add column if not exists payment_status text not null default 'submitted'
    check (payment_status in ('submitted', 'verified', 'rejected')),
  add column if not exists payment_provider    text,
  add column if not exists payment_verified_at timestamptz;

-- Rattrapage des commandes déjà en base : celles que la vendeuse avait
-- déjà confirmées valent un paiement retrouvé.
update public.orders
   set payment_status      = 'verified',
       payment_verified_at = coalesce(confirmed_at, created_at)
 where payment_reference is not null
   and payment_status = 'submitted'
   and status in ('confirmed', 'preparing', 'delivering', 'delivered');

-- Fournisseur : on remonte celui de la boutique pour l'historique, faute
-- de mieux. Les nouvelles commandes l'enregistrent à la source.
update public.orders o
   set payment_provider = s.merchant_provider
  from public.shops s
 where s.id = o.shop_id
   and o.payment_provider is null
   and s.merchant_provider is not null;


-- ---------------------------------------------------------------------
-- 2. INTÉGRITÉ DES MONTANTS
-- ---------------------------------------------------------------------

-- 2.1 Chaque ligne de commande est retarifée par la base.
--
-- Le prix n'est PAS celui que le client envoie : il est relu dans
-- `products` au moment de l'insertion. Le client peut donc envoyer ce
-- qu'il veut, seul le prix réel de la boutique est enregistré.
--
-- On vérifie au passage qu'un produit ne peut pas être commandé à travers
-- la commande d'une autre boutique (une commande = une boutique).
create or replace function public.trg_order_item_price_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  real_price numeric(12,2);
  item_shop  uuid;
  order_shop uuid;
begin
  -- `product_id` est `on delete set null` : une vieille ligne dont le
  -- produit a été supprimé garde le prix recopié à l'achat, c'est tout
  -- l'intérêt d'avoir recopié `product_name`/`unit_price`.
  if new.product_id is null then
    new.subtotal := round(new.unit_price * new.quantity, 2);
    return new;
  end if;

  select p.price, p.shop_id into real_price, item_shop
    from public.products p
   where p.id = new.product_id;

  if real_price is null then
    raise exception 'Produit introuvable pour cette ligne de commande';
  end if;

  select o.shop_id into order_shop
    from public.orders o
   where o.id = new.order_id;

  if order_shop is distinct from item_shop then
    raise exception 'Ce produit n''appartient pas à la boutique de la commande';
  end if;

  new.unit_price := real_price;
  new.subtotal   := round(real_price * new.quantity, 2);
  return new;
end;
$$;

drop trigger if exists order_item_price_guard on public.order_items;
create trigger order_item_price_guard
  before insert or update on public.order_items
  for each row execute function public.trg_order_item_price_guard();


-- 2.2 `orders.total` est recalculé depuis les lignes, jamais accepté.
--
-- Subtilité : ce recalcul met à jour `orders`, ce qui réveille
-- `client_order_update_guard` (partie 6.1 de `rattrapage_patch.sql`) qui
-- interdit justement à une cliente de toucher au total. On pose donc un
-- drapeau local à la transaction, que le garde reconnaît. Un client ne
-- peut pas poser ce drapeau lui-même : PostgREST n'expose pas
-- `set_config`.
create or replace function public.trg_order_total_recompute()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  targets uuid[];
  target  uuid;
begin
  -- Piège PL/pgSQL : sur un DELETE, `new` n'est pas affecté et lire
  -- `new.order_id` lève « record "new" is not assigned yet ». Il faut
  -- donc tester TG_OP plutôt que faire un coalesce(new..., old...).
  if tg_op = 'DELETE' then
    targets := array[old.order_id];
  elsif tg_op = 'UPDATE' and new.order_id is distinct from old.order_id then
    targets := array[old.order_id, new.order_id];
  else
    targets := array[new.order_id];
  end if;

  perform set_config('mesk.total_recompute', 'on', true);

  foreach target in array targets loop
    update public.orders o
       set total = coalesce((
             select sum(oi.subtotal)
               from public.order_items oi
              where oi.order_id = target
           ), 0)
     where o.id = target;
  end loop;

  perform set_config('mesk.total_recompute', 'off', true);
  return null;
end;
$$;

drop trigger if exists order_total_recompute on public.order_items;
create trigger order_total_recompute
  after insert or update or delete on public.order_items
  for each row execute function public.trg_order_total_recompute();


-- 2.3 Le total envoyé à la création vaut zéro.
--
-- Les lignes de commande sont insérées APRÈS la commande elle-même (voir
-- `order_service.checkout`), donc 2.2 ne peut pas encore recalculer quoi
-- que ce soit au moment du `insert into orders`. Sans cette partie, une
-- commande sans aucune ligne garderait le total envoyé par le client.
--
-- On ne force à zéro que la cliente : l'admin et l'éditeur SQL (où
-- `auth.uid()` est nul, c'est par là que passent les données de démo)
-- gardent la main.
create or replace function public.trg_order_insert_total_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and auth.uid() = new.client_id and not public.is_admin() then
    new.total := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists order_insert_total_guard on public.orders;
create trigger order_insert_total_guard
  before insert on public.orders
  for each row execute function public.trg_order_insert_total_guard();


-- ---------------------------------------------------------------------
-- 3. QUI A LE DROIT DE TOUCHER AU PAIEMENT
-- ---------------------------------------------------------------------

-- Reprise de `trg_client_order_update_guard` (rattrapage_patch.sql, 6.1)
-- avec les trois nouvelles colonnes et le drapeau de recalcul. Même nom :
-- le déclencheur existant continue de pointer dessus.
--
-- Une cliente ne décide pas que son paiement est vérifié. C'est la
-- vendeuse qui retrouve la référence dans son application bancaire.
create or replace function public.trg_client_order_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Recalcul interne du total (2.2) : ce n'est pas la cliente qui écrit.
  if coalesce(current_setting('mesk.total_recompute', true), 'off') = 'on' then
    return new;
  end if;

  -- Ne s'applique qu'à la cliente : la vendeuse et l'admin gardent le
  -- droit de changer le statut, c'est tout leur travail.
  if auth.uid() is distinct from old.client_id then
    return new;
  end if;
  if public.is_admin() or public.owns_shop(old.shop_id) then
    return new;
  end if;

  if new.status              is distinct from old.status
     or new.total            is distinct from old.total
     or new.shop_id          is distinct from old.shop_id
     or new.client_id        is distinct from old.client_id
     or new.confirmed_at     is distinct from old.confirmed_at
     or new.payment_reference is distinct from old.payment_reference
     or new.payment_status   is distinct from old.payment_status
     or new.payment_provider is distinct from old.payment_provider
     or new.payment_verified_at is distinct from old.payment_verified_at then
    raise exception 'Une cliente ne peut pas modifier le paiement de sa commande';
  end if;

  return new;
end;
$$;

-- Le déclencheur est recréé au cas où ce fichier serait joué sur une base
-- où `rattrapage_patch.sql` a été passé mais le déclencheur perdu.
drop trigger if exists client_order_update_guard on public.orders;
create trigger client_order_update_guard
  before update on public.orders
  for each row execute function public.trg_client_order_update_guard();


-- 3.1 Horodatage automatique de la vérification, pour que la vendeuse
-- n'ait qu'un seul champ à changer depuis l'app.
create or replace function public.trg_payment_verified_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.payment_status is distinct from old.payment_status then
    new.payment_verified_at := case
      when new.payment_status = 'verified' then now()
      else null
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists payment_verified_at_stamp on public.orders;
create trigger payment_verified_at_stamp
  before update on public.orders
  for each row execute function public.trg_payment_verified_at();


-- ---------------------------------------------------------------------
-- 4. INDEX POUR LE TABLEAU DE BORD
-- ---------------------------------------------------------------------

-- Le tableau de bord lit toujours « les commandes de MA boutique sur les
-- N derniers jours ». `idx_orders_shop` seul oblige à trier ensuite.
create index if not exists orders_shop_created_idx
  on public.orders (shop_id, created_at desc);

create index if not exists orders_shop_payment_status_idx
  on public.orders (shop_id, payment_status);
