-- =====================================================================
-- payment_amount_patch.sql — 21 septembre 2026
--
-- À jouer APRÈS `fintech_patch.sql`. Rejouable sans risque.
--
-- LE TROU QUE CE FICHIER FERME.
--
-- Depuis `fintech_patch.sql`, le MONTANT d'une commande est incontestable :
-- la base retarife chaque ligne depuis `products` et recalcule le total.
-- Et depuis le début, une RÉFÉRENCE de paiement ne peut servir qu'une fois.
--
-- Mais rien ne reliait les deux. Une cliente pouvait payer 100 MRU par
-- Bankily, récupérer la référence de CE paiement, et la soumettre pour une
-- commande de 50 000 MRU. Les deux contrôles existants la laissaient
-- passer : la référence était bien authentique et jamais utilisée, et le
-- total bien calculé — simplement, personne ne vérifiait qu'ils parlaient
-- de la même transaction.
--
-- CE QU'ON PEUT ET NE PEUT PAS FAIRE.
--
-- Aucun fournisseur mauritanien n'expose aujourd'hui d'API permettant de
-- demander « à combien s'élève la transaction X ». Le rapprochement
-- automatique est donc hors de portée, et prétendre le contraire serait
-- mentir à la vendeuse comme au jury.
--
-- Ce qui EST à notre portée : la vendeuse a le montant sous les yeux dans
-- son application bancaire au moment où elle retrouve la référence. On le
-- lui demande, on le compare au total de la commande, et l'écart devient
-- visible au lieu de rester invisible. Le contrôle reste humain ; ce qui
-- change, c'est qu'il est désormais enregistré et vérifiable.
-- =====================================================================

alter table public.orders
  add column if not exists payment_amount_received numeric(12,2)
    check (payment_amount_received is null or payment_amount_received >= 0);

comment on column public.orders.payment_amount_received is
  'Montant réellement reçu, relevé par la vendeuse dans son application '
  'bancaire au moment de la vérification. Comparé au total de la commande '
  'pour signaler un écart. null = pas encore vérifié.';

-- Écart entre ce qui a été payé et ce qui était dû. Calculé par la base
-- plutôt que par l'application : un écart est une information comptable,
-- il ne doit pas dépendre de la version installée sur le téléphone.
create or replace function public.payment_gap(order_row public.orders)
returns numeric
language sql
immutable
as $$
  select case
    when order_row.payment_amount_received is null then null
    else round(order_row.payment_amount_received - order_row.total, 2)
  end;
$$;


-- ---------------------------------------------------------------------
-- Le garde des colonnes de paiement
-- ---------------------------------------------------------------------
--
-- Reprise de `trg_client_order_update_guard` (fintech_patch.sql, partie 3)
-- avec la nouvelle colonne. Même nom de fonction : le déclencheur existant
-- continue de pointer dessus.
--
-- Une cliente ne déclare pas elle-même ce qu'elle a payé.
create or replace function public.trg_client_order_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('mesk.total_recompute', true), 'off') = 'on' then
    return new;
  end if;

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


-- Un paiement « rejeté » ou remis en attente ne garde pas le montant d'une
-- vérification précédente : il deviendrait trompeur.
create or replace function public.trg_clear_amount_on_unverify()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.payment_status is distinct from old.payment_status
     and new.payment_status <> 'verified' then
    new.payment_amount_received := null;
  end if;
  return new;
end;
$$;

drop trigger if exists clear_amount_on_unverify on public.orders;
create trigger clear_amount_on_unverify
  before update on public.orders
  for each row execute function public.trg_clear_amount_on_unverify();
