-- =====================================================================
-- correctifs_patch.sql — 21 septembre 2026
--
-- À coller dans l'éditeur SQL de Supabase APRÈS `payment_amount_patch.sql`
-- (dernier fichier de la liste de `supabase/AGENTS.md`). Rejouable sans
-- risque, comme tous les fichiers de ce dossier.
--
-- Huit trous trouvés par une relecture complète du dépôt. Dans l'ordre de
-- gravité :
--
--  1. UN LIVREUR POUVAIT S'AUTO-APPROUVER. `livreur_patch_3_approval.sql`
--     ajoute `driver_profiles.status` pour que l'admin valide chaque
--     livreur — mais la policy `driver_profiles_update_own` de
--     `livreur_patch.sql` autorise le titulaire à modifier N'IMPORTE
--     QUELLE colonne de sa propre ligne, `status` comprise, et aucun
--     déclencheur ne s'y opposait. N'importe quel compte connecté pouvait
--     donc s'inscrire livreur, se passer lui-même en 'approved', voir le
--     tableau des courses et appeler `get_delivery_contact` — qui renvoie
--     le NOM, le TÉLÉPHONE et l'ADRESSE de la cliente. Le schéma protège
--     pourtant déjà les deux cas identiques (`prevent_self_role_change`
--     pour `profiles.role`, `prevent_self_shop_activation` pour
--     `shops.is_visible`) : il manquait le troisième.
--
--  2. UNE CLIENTE POUVAIT GONFLER SA COMMANDE APRÈS COUP.
--     `order_items_insert_client_own_order` ne vérifie que l'appartenance
--     de la commande, jamais son état : on pouvait donc ajouter des
--     lignes à une commande déjà vérifiée, voire déjà livrée, et
--     `order_total_recompute` remontait le total docilement — ce qui
--     fausse au passage l'écart de `payment_amount_patch.sql`.
--
--  3. LE STOCK N'ÉTAIT JAMAIS DÉCRÉMENTÉ. `products.stock` existait, le
--     panier s'y limitait CÔTÉ APPLICATION (cart_controller.dart), et
--     c'est tout : deux clientes pouvaient acheter le même dernier
--     article, rien ne passait jamais en rupture tout seul, et un client
--     modifié commandait 1000 pièces d'un article qui en avait 1.
--     `fintech_patch.sql` retarifiait bien le prix, mais n'a jamais
--     regardé la quantité.
--
--  4. UNE CLIENTE NE POUVAIT PAS ANNULER SA COMMANDE.
--     `order_service.cancelOrder` existe et le bouton est à l'écran, mais
--     `client_order_update_guard` refuse tout changement de `status` par
--     la cliente : le bouton remontait une erreur Postgres brute en
--     français au lieu d'annuler.
--
--  5. UNE VENDEUSE POUVAIT RÉÉCRIRE LES AVIS SUR SES PROPRES PRODUITS.
--     La policy s'appelle « vendor_moderation » mais n'interdit aucune
--     colonne : une note de 1 étoile pouvait devenir 5.
--
--  6. RIEN N'EMPÊCHAIT UN COMPTE D'AVOIR DEUX BOUTIQUES, alors que
--     `vendor_service.fetchMyShop` lit avec `.maybeSingle()` — qui lève
--     une exception dès la deuxième. La vendeuse perdait alors l'accès à
--     sa boutique en silence.
--
--  7. LA VALIDATION DU PANIER N'ÉTAIT PAS ATOMIQUE. `checkout` faisait
--     trois appels HTTP séparés par boutique ; un échec au milieu
--     laissait une commande sans ses lignes. D'où `create_order`
--     ci-dessous, qui fait tout en une seule transaction.
--
--  8. UN LIVREUR POUVAIT SAUTER LE TRAVAIL DE LA VENDEUSE.
--     `accept_delivery_request` passait la commande en 'delivering' sans
--     jamais regarder si la vendeuse l'avait seulement confirmée.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. UN LIVREUR NE S'APPROUVE PAS LUI-MÊME
-- ---------------------------------------------------------------------
--
-- Même idiome que `prevent_self_role_change` (marketplace_schema.sql,
-- 4.2) : la règle ne s'applique QUE depuis l'application (`auth.uid()`
-- renseigné). Depuis l'éditeur SQL, `auth.uid()` est nul, donc Emina peut
-- toujours approuver un livreur à la main si le site admin est
-- indisponible.
create or replace function public.prevent_self_driver_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and new.status is distinct from old.status
     and not public.is_admin() then
    raise exception 'Seul un administrateur peut approuver ou refuser un livreur.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_self_driver_approval on public.driver_profiles;
create trigger trg_prevent_self_driver_approval
  before update on public.driver_profiles
  for each row execute function public.prevent_self_driver_approval();

-- Ceinture ET bretelles : un compte qui s'inscrit livreur ne choisit pas
-- non plus son statut de départ. Sans ça, l'insertion initiale pouvait
-- naître directement 'approved' — le déclencheur ci-dessus ne regarde que
-- les UPDATE.
create or replace function public.force_driver_pending_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.status := 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_force_driver_pending_on_insert on public.driver_profiles;
create trigger trg_force_driver_pending_on_insert
  before insert on public.driver_profiles
  for each row execute function public.force_driver_pending_on_insert();


-- ---------------------------------------------------------------------
-- 2. ON N'AJOUTE PAS DE LIGNES À UNE COMMANDE DÉJÀ PARTIE
-- ---------------------------------------------------------------------
--
-- Une ligne de commande ne s'ajoute que pendant la validation du panier,
-- c'est-à-dire sur une commande qui vient de naître : statut 'pending' et
-- paiement pas encore vérifié. Après, la commande est un document
-- comptable, plus un brouillon.
drop policy if exists "order_items_insert_client_own_order" on public.order_items;
create policy "order_items_insert_client_own_order"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_id
        and o.client_id = auth.uid()
        and o.status = 'pending'
        and o.payment_status = 'submitted'
    )
  );


-- ---------------------------------------------------------------------
-- 3. LE STOCK
-- ---------------------------------------------------------------------

-- 3.1 Réservation à l'insertion d'une ligne de commande.
--
-- `for update` verrouille la ligne produit jusqu'à la fin de la
-- transaction : deux clientes qui valident au même instant le dernier
-- article sont sérialisées par PostgreSQL, et la seconde voit un stock
-- déjà décrémenté au lieu de lire la même valeur que la première.
--
-- Le message d'erreur est LOAD BEARING : `cart_screen.dart` cherche la
-- chaîne 'STOCK_INSUFFISANT' dedans pour afficher une phrase lisible
-- plutôt qu'une erreur technique — même principe que le nom de l'index
-- `orders_payment_reference_unique`. Ne pas le renommer sans changer
-- l'application.
--
-- Volontairement limité à l'INSERT : rien dans l'application ne modifie
-- une ligne de commande après coup (la partie 2 ci-dessus l'interdit
-- même à la cliente). Une quantité changée à la main dans l'éditeur SQL
-- ne réajustera donc pas le stock.
create or replace function public.trg_order_item_stock_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  available int;
begin
  -- `product_id` est `on delete set null` : une ligne dont le produit a
  -- été supprimé n'a plus de stock à réserver.
  if new.product_id is null then
    return new;
  end if;

  select stock into available
    from public.products
   where id = new.product_id
     for update;

  if available is null then
    raise exception 'Produit introuvable pour cette ligne de commande';
  end if;

  if available < new.quantity then
    raise exception 'STOCK_INSUFFISANT % (reste %)', new.product_name, available;
  end if;

  update public.products
     set stock = stock - new.quantity
   where id = new.product_id;

  return new;
end;
$$;

-- `order_item_price_guard` (fintech_patch.sql) est aussi un BEFORE INSERT
-- sur cette table. PostgreSQL les déclenche dans l'ordre ALPHABÉTIQUE de
-- leur nom : 'order_item_price_guard' puis 'order_item_stock_guard'. Les
-- deux sont indépendants (l'un écrit le prix, l'autre lit la quantité),
-- mais autant que l'ordre soit celui qu'on croit.
drop trigger if exists order_item_stock_guard on public.order_items;
create trigger order_item_stock_guard
  before insert on public.order_items
  for each row execute function public.trg_order_item_stock_guard();


-- 3.2 Restitution du stock quand la commande est annulée.
--
-- Sans ça, chaque annulation grignoterait le stock définitivement.
--
-- L'agrégation par `product_id` n'est pas cosmétique : un même produit
-- peut apparaître sur DEUX lignes de la même commande (même article, deux
-- options — voir `CartLine.cartKey`, models.dart). Un `update ... from
-- order_items` direct n'en rendrait qu'une seule, PostgreSQL ne
-- rapprochant qu'une ligne source par ligne cible.
-- Et une commande annulée ne se réactive pas : son stock est déjà rendu,
-- la réactiver le compterait deux fois. Rien dans l'application ne le
-- propose, mais `orders.status` accepte les six valeurs dans n'importe
-- quel sens — autant que la base le dise plutôt que de laisser le stock
-- diverger en silence.
create or replace function public.trg_order_stock_release()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'cancelled' and new.status <> 'cancelled' then
    raise exception 'Une commande annulée ne peut pas être réactivée : son stock a été rendu. En créer une nouvelle.';
  end if;

  if old.status <> 'cancelled' and new.status = 'cancelled' then
    update public.products p
       set stock = p.stock + agg.qty
      from (
        select oi.product_id, sum(oi.quantity) as qty
          from public.order_items oi
         where oi.order_id = new.id
           and oi.product_id is not null
         group by oi.product_id
      ) agg
     where agg.product_id = p.id;
  end if;
  return new;
end;
$$;

-- BEFORE et non AFTER : le déclencheur doit pouvoir REFUSER la
-- réactivation ci-dessus, ce qu'un AFTER ne peut pas faire proprement.
drop trigger if exists order_stock_release on public.orders;
create trigger order_stock_release
  before update on public.orders
  for each row execute function public.trg_order_stock_release();


-- ---------------------------------------------------------------------
-- 4. UNE CLIENTE PEUT ANNULER TANT QUE LA VENDEUSE N'A RIEN FAIT
-- ---------------------------------------------------------------------
--
-- Reprise de `trg_client_order_update_guard` (payment_amount_patch.sql)
-- avec une seule différence : la transition 'pending' -> 'cancelled' est
-- désormais permise à la cliente. C'est exactement ce que
-- `order_service.cancelOrder` essayait de faire depuis le 6 septembre
-- 2026, et que ce garde refusait.
--
-- Toutes les autres colonnes restent interdites, y compris le total, la
-- référence et les colonnes de paiement : une cliente ne décide ni de ce
-- qu'elle doit, ni de ce qu'elle a payé.
create or replace function public.trg_client_order_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Recalcul interne du total (fintech_patch.sql, 2.2) : ce n'est pas la
  -- cliente qui écrit.
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

  -- La SEULE transition de statut permise à la cliente : annuler une
  -- commande que la vendeuse n'a pas encore prise en charge.
  if new.status is distinct from old.status
     and not (old.status = 'pending' and new.status = 'cancelled') then
    raise exception 'Une cliente ne peut annuler sa commande que tant que la boutique ne l''a pas prise en charge';
  end if;

  if new.total            is distinct from old.total
     or new.shop_id       is distinct from old.shop_id
     or new.client_id     is distinct from old.client_id
     or new.confirmed_at  is distinct from old.confirmed_at
     or new.payment_reference is distinct from old.payment_reference
     or new.payment_status    is distinct from old.payment_status
     or new.payment_provider  is distinct from old.payment_provider
     or new.payment_verified_at is distinct from old.payment_verified_at
     or new.payment_amount_received is distinct from old.payment_amount_received then
    raise exception 'Une cliente ne peut pas modifier le paiement de sa commande';
  end if;

  return new;
end;
$$;

drop trigger if exists client_order_update_guard on public.orders;
create trigger client_order_update_guard
  before update on public.orders
  for each row execute function public.trg_client_order_update_guard();


-- ---------------------------------------------------------------------
-- 5. UNE VENDEUSE MASQUE UN AVIS, ELLE NE LE RÉÉCRIT PAS
-- ---------------------------------------------------------------------
--
-- La policy d'origine (`reviews_update_author_content_or_vendor_moderation`)
-- autorisait la vendeuse à modifier TOUTES les colonnes d'un avis portant
-- sur un de ses produits, note et commentaire compris. Son nom annonçait
-- pourtant une simple modération.
--
-- Une policy RLS ne sait pas raisonner colonne par colonne : on garde donc
-- la policy telle quelle et on met la limite dans un déclencheur, comme le
-- schéma le fait déjà pour `profiles.role` et `shops.is_visible`.
drop policy if exists "reviews_update_author_content_or_vendor_moderation" on public.reviews;
drop policy if exists "reviews_update_author_or_vendor_or_admin" on public.reviews;
create policy "reviews_update_author_or_vendor_or_admin"
  on public.reviews for update
  using (
    client_id = auth.uid()
    or public.owns_product_shop(product_id)
    or public.is_admin()
  );

create or replace function public.trg_review_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Éditeur SQL et admin : pas de limite.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  if auth.uid() = old.client_id then
    -- L'autrice corrige son texte et sa note. Elle ne décide pas de la
    -- visibilité : sinon elle pourrait réafficher un avis que la vendeuse
    -- vient de masquer, et la modération ne voudrait plus rien dire.
    if new.is_visible is distinct from old.is_visible then
      raise exception 'La visibilité d''un avis est décidée par la boutique, pas par son autrice';
    end if;
    return new;
  end if;

  -- Reste la vendeuse : elle ne touche QUE `is_visible`.
  if new.rating     is distinct from old.rating
     or new.comment is distinct from old.comment
     or new.product_id is distinct from old.product_id
     or new.client_id  is distinct from old.client_id
     or new.order_id   is distinct from old.order_id then
    raise exception 'Une boutique peut masquer un avis, pas le modifier';
  end if;

  return new;
end;
$$;

drop trigger if exists review_update_guard on public.reviews;
create trigger review_update_guard
  before update on public.reviews
  for each row execute function public.trg_review_update_guard();


-- ---------------------------------------------------------------------
-- 6. UNE BOUTIQUE PAR COMPTE
-- ---------------------------------------------------------------------
--
-- `vendor_service.fetchMyShop` lit avec `.maybeSingle()`, qui lève une
-- exception dès qu'il y a deux lignes — et `RoleController.refresh`
-- l'avale, ce qui fait disparaître l'espace vendeuse sans message. La
-- contrainte manquait simplement en base.
--
-- Encadré par un bloc d'exception : si la base contient DÉJÀ un compte
-- avec deux boutiques, ce fichier doit rester rejouable et le dire, pas
-- échouer d'un bloc.
do $$
begin
  create unique index if not exists shops_owner_unique on public.shops (owner_id);
exception when unique_violation then
  raise notice 'Index shops_owner_unique NON créé : au moins un compte possède déjà plusieurs boutiques. Les fusionner ou en supprimer une, puis rejouer ce fichier.';
end $$;


-- ---------------------------------------------------------------------
-- 7. VALIDATION DU PANIER EN UNE SEULE TRANSACTION
-- ---------------------------------------------------------------------
--
-- `order_service.checkout` faisait, PAR BOUTIQUE, trois appels HTTP
-- séparés : `insert into orders`, `insert into delivery_requests`, puis
-- `insert into order_items`. Chacun sa propre transaction. Si le dernier
-- échouait — stock épuisé depuis la partie 3, réseau coupé — la commande
-- restait en base SANS SES LIGNES, donc avec un total recalculé à zéro,
-- visible par la vendeuse comme une commande vide.
--
-- Tout tient maintenant dans cette fonction, donc dans une seule
-- transaction : ou bien la commande, ses lignes et sa course existent, ou
-- bien rien n'existe.
--
-- `security invoker` (le défaut) est VOLONTAIRE : la fonction s'exécute
-- avec les droits de la cliente, donc toutes les policies RLS déjà
-- écrites continuent de s'appliquer mot pour mot. Une fonction
-- `security definer` aurait contourné la seule chose qu'on cherche à
-- garder.
--
-- Le prix n'est pas un paramètre : `order_item_price_guard` le relit dans
-- `products`. On envoie donc 0, que la base remplace.
create or replace function public.create_order(
  p_shop_id           uuid,
  p_payment_reference text,
  p_client_full_name  text,
  p_client_phone      text,
  p_client_city       text,
  p_client_address    text,
  p_delivery_lat      double precision,
  p_delivery_lng      double precision,
  p_delivery_mode     text,
  p_items             jsonb
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_order_id uuid;
  v_provider text;
  v_lat      double precision;
  v_lng      double precision;
  v_mode     text := coalesce(nullif(trim(p_delivery_mode), ''), 'pickup');
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if coalesce(trim(p_payment_reference), '') = '' then
    raise exception 'Missing payment code for a shop.';
  end if;
  if coalesce(jsonb_array_length(p_items), 0) = 0 then
    raise exception 'Commande sans article';
  end if;

  -- Service de paiement et position de la boutique, recopiés sur la
  -- commande : la vendeuse peut changer de banque plus tard, la commande
  -- doit garder le service par lequel elle a réellement été payée.
  select s.merchant_provider, s.lat, s.lng
    into v_provider, v_lat, v_lng
    from public.shops s
   where s.id = p_shop_id;

  insert into public.orders (
    client_id, shop_id, total,
    client_full_name, client_phone, client_city, client_address,
    payment_reference, payment_provider,
    delivery_lat, delivery_lng, delivery_mode
  ) values (
    auth.uid(), p_shop_id, 0,
    coalesce(p_client_full_name, ''), trim(p_client_phone),
    p_client_city, p_client_address,
    trim(p_payment_reference), v_provider,
    p_delivery_lat, p_delivery_lng, v_mode
  )
  returning id into v_order_id;

  insert into public.order_items (order_id, product_id, product_name, unit_price, quantity, subtotal)
  select v_order_id,
         (item->>'product_id')::uuid,
         item->>'product_name',
         0,
         (item->>'quantity')::int,
         0
    from jsonb_array_elements(p_items) as item
   -- Verrouillage dans un ordre DÉTERMINISTE. `order_item_stock_guard`
   -- pose un `for update` sur chaque produit ; deux paniers contenant les
   -- mêmes articles dans un ordre différent se bloqueraient mutuellement.
   -- En insérant toujours par `product_id` croissant, les verrous sont
   -- pris dans le même ordre par tout le monde : plus d'interblocage
   -- possible entre deux commandes.
   order by (item->>'product_id')::uuid;

  -- Une course n'est proposée aux livreuses que si la cliente a choisi la
  -- livraison ET partagé une position : sans ça, il n'y a pas de point
  -- d'arrivée à donner.
  if v_mode = 'delivery' and p_delivery_lat is not null and p_delivery_lng is not null then
    -- Sous-transaction : si `delivery_requests` n'existe pas encore (patch
    -- livreur pas joué), la commande est déjà payée et ne doit pas être
    -- annulée pour autant. La vendeuse garde la position sur la commande
    -- elle-même et organise la livraison comme avant.
    begin
      insert into public.delivery_requests (
        order_id, shop_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng
      ) values (
        v_order_id, p_shop_id, v_lat, v_lng, p_delivery_lat, p_delivery_lng
      );
    exception when others then
      raise notice 'Course non créée pour la commande % : %', v_order_id, sqlerrm;
    end;
  end if;

  return v_order_id;
end;
$$;

grant execute on function public.create_order(
  uuid, text, text, text, text, text, double precision, double precision, text, jsonb
) to authenticated;


-- ---------------------------------------------------------------------
-- 8. UN LIVREUR NE PREND PAS UNE COMMANDE QUE LA VENDEUSE N'A PAS PRÉPARÉE
-- ---------------------------------------------------------------------
--
-- `accept_delivery_request` passait la commande en 'delivering' sans
-- jamais regarder son statut : un livreur approuvé pouvait donc faire
-- sauter les étapes « confirmée » et « en préparation » de la vendeuse,
-- sur une commande dont le paiement n'était même pas encore vérifié.
--
-- Deux moitiés, parce qu'interdire l'acceptation ne suffit pas : sans la
-- première, le tableau des livreuses se remplirait de courses qu'aucune
-- ne peut prendre.
--
--  8.1 `delivery_requests.ready` — une course n'apparaît au tableau qu'une
--      fois la commande confirmée par la vendeuse. La colonne vit sur
--      `delivery_requests` (et pas dans une sous-requête vers `orders`)
--      POUR UNE RAISON PRÉCISE : un livreur n'a aucun droit de lecture sur
--      `orders`, et surtout Supabase Realtime n'émet un événement que
--      quand la ligne SUIVIE change. En posant le drapeau sur la course
--      elle-même, la confirmation de la vendeuse déclenche un vrai UPDATE
--      sur `delivery_requests` : le tableau des livreuses s'allume tout
--      seul, sans rechargement.
--
--  8.2 `accept_delivery_request` revérifie le statut de la commande côté
--      base — le drapeau ci-dessus est un confort d'affichage, pas une
--      garantie.
alter table public.delivery_requests
  add column if not exists ready boolean not null default false;

-- Rattrapage : les courses dont la commande est déjà confirmée restent
-- visibles, sinon ce fichier viderait le tableau des livreuses en cours.
update public.delivery_requests d
   set ready = true
  from public.orders o
 where o.id = d.order_id
   and d.ready = false
   and o.status in ('confirmed', 'preparing', 'delivering', 'delivered');

create or replace function public.trg_delivery_request_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('confirmed', 'preparing') and old.status is distinct from new.status then
    update public.delivery_requests
       set ready = true
     where order_id = new.id
       and ready = false;
  end if;
  return null;
end;
$$;

drop trigger if exists order_delivery_ready on public.orders;
create trigger order_delivery_ready
  after update on public.orders
  for each row execute function public.trg_delivery_request_ready();

-- Une cliente n'allume pas le drapeau elle-même à l'insertion : c'est la
-- confirmation de la vendeuse qui le fait, et elle seule.
create or replace function public.force_delivery_request_not_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.ready := false;
  end if;
  return new;
end;
$$;

drop trigger if exists force_delivery_request_not_ready on public.delivery_requests;
create trigger force_delivery_request_not_ready
  before insert on public.delivery_requests
  for each row execute function public.force_delivery_request_not_ready();

-- Le tableau des courses ne montre plus que les courses prêtes. Le reste
-- de la policy est repris mot pour mot de `livreur_patch_3_approval.sql`.
drop policy if exists "delivery_requests_select" on public.delivery_requests;
create policy "delivery_requests_select"
  on public.delivery_requests for select
  using (
    (status = 'pending' and ready = true and exists (
      select 1 from public.driver_profiles dp
      where dp.id = auth.uid() and dp.status = 'approved'
    ))
    or driver_id = auth.uid()
    or exists (select 1 from public.orders o where o.id = order_id and o.client_id = auth.uid())
    or exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- 8.2 Reprise de la version de `livreur_patch_3_approval.sql` avec la
-- vérification du statut de la commande en plus.
create or replace function public.accept_delivery_request(p_request_id uuid)
returns public.delivery_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    public.delivery_requests;
  v_status text;
begin
  if not exists (
    select 1 from public.driver_profiles where id = auth.uid() and status = 'approved'
  ) then
    raise exception 'Your driver account is not approved yet.';
  end if;

  select o.status into v_status
    from public.delivery_requests d
    join public.orders o on o.id = d.order_id
   where d.id = p_request_id;

  if v_status is null then
    raise exception 'This delivery no longer exists.';
  end if;
  if v_status not in ('confirmed', 'preparing') then
    raise exception 'This order is not ready for pickup yet.';
  end if;

  update public.delivery_requests
     set driver_id   = auth.uid(),
         status      = 'accepted',
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

grant execute on function public.accept_delivery_request(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 9. RATTRAPAGE DES DONNÉES DÉJÀ EN BASE
-- ---------------------------------------------------------------------

-- Les livreurs inscrits AVANT la partie 1 ont pu se mettre 'approved'
-- eux-mêmes. On ne peut pas distinguer après coup ceux qu'Emina a
-- réellement approuvés : on ne touche donc à rien automatiquement, mais
-- la requête à passer en revue est écrite ici.
--
--   select id, status, created_at from public.driver_profiles order by created_at;
--
-- Repasser en 'pending' ceux qui ne devraient pas être approuvés :
--
--   update public.driver_profiles set status = 'pending' where id = '...';

-- Le stock n'ayant jamais été décrémenté (partie 3), les valeurs
-- actuelles de `products.stock` ne reflètent pas les commandes déjà
-- passées. Rien n'est corrigé automatiquement : soustraire l'historique
-- complet punirait une vendeuse qui a déjà réajusté son stock à la main.
-- C'est à chaque boutique de repartir de son stock réel dans
-- « Ma boutique ».
