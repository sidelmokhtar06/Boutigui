-- =====================================================================
-- demo_seed.sql — 20 septembre 2026
--
-- Jeu de données de démonstration pour le hackathon. À jouer APRÈS
-- `fintech_patch.sql`.
--
-- AVANT DE LANCER CE FICHIER : créer le compte de la vendeuse démo
-- DEPUIS L'APPLICATION (inscription normale), puis mettre son adresse
-- ci-dessous. On ne fabrique pas ce compte-là en SQL parce qu'il doit
-- pouvoir SE CONNECTER pendant la démo — ce qui suppose un vrai mot de
-- passe chiffré par Supabase Auth.
--
-- Les CLIENTES de démo, elles, n'ont jamais besoin de se connecter : on
-- les crée ici avec un mot de passe vide. Le déclencheur
-- `on_auth_user_created` leur fabrique un profil automatiquement.
--
-- Rejouable : le script efface d'abord sa propre boutique de démo
-- (repérée par son code marchand) et ses clientes, puis reconstruit.
-- =====================================================================

do $$
declare
  -- ⬇⬇⬇  METTRE ICI L'ADRESSE DU COMPTE VENDEUSE CRÉÉ DANS L'APP  ⬇⬇⬇
  v_vendor_email constant text := 'aicha@mesk.mr';

  v_merchant_code constant text := 'DEMO-12345';
  v_vendor    uuid;
  v_shop      uuid;
  v_cat       uuid;
  v_client    uuid;
  v_order     uuid;
  v_product   uuid;
  v_clients   uuid[] := '{}';
  v_products  uuid[] := '{}';
  v_day       date;
  v_when      timestamptz;
  v_weight    int;
  v_n         int;
  v_i         int;
  v_pick      int;
  v_provider  text;
  v_status    text;
  v_paystatus text;
  v_growth    numeric;
  v_names     text[] := array[
    'Fatimetou','Mariem','Aminetou','Khadijetou','Salka','Zeinabou',
    'Nebghouha','Lalla','Toutou','Vatimetou','Mounina','Selma',
    'Habsatou','Coumba','Oumou'];
  v_order_count int := 0;
begin
  -- ---- 0. la vendeuse doit exister ----------------------------------
  select id into v_vendor from public.profiles where email = v_vendor_email;
  if v_vendor is null then
    raise exception
      'Compte vendeuse introuvable (%). Créez-le d''abord depuis l''application, puis remettez son adresse en haut de ce fichier.',
      v_vendor_email;
  end if;
  update public.profiles set role = 'vendor', city = 'Nouakchott' where id = v_vendor;

  -- ---- 1. table rase (rejouable) ------------------------------------
  delete from public.shops where merchant_code = v_merchant_code;
  delete from auth.users where email like 'demo.cliente%@mesk.mr';

  -- ---- 2. la boutique ------------------------------------------------
  insert into public.shops
         (owner_id, name, description, city, whatsapp_phone,
          merchant_code, merchant_provider, is_visible, created_at)
       values
         (v_vendor, 'Maison Aïcha',
          'Prêt-à-porter et accessoires — Nouakchott.',
          'Nouakchott', '22200000',
          v_merchant_code, 'Bankily', true, now() - interval '95 days')
    returning id into v_shop;

  select id into v_cat from public.categories order by sort_order, name limit 1;

  -- ---- 3. les produits ----------------------------------------------
  for v_i in 1..15 loop
    insert into public.products (shop_id, category_id, name, description, price, stock, is_visible, created_at)
         values (
           v_shop, v_cat,
           (array['Melhfa brodée','Boubou classique','Voile mousseline','Sac à main cuir',
                  'Sandales cuir','Robe soirée','Ensemble coton','Étole brodée',
                  'Pochette perlée','Caftan velours','Foulard soie','Ceinture tressée',
                  'Babouches brodées','Parure argent','Tunique lin'])[v_i],
           'Pièce confectionnée à Nouakchott.',
           (array[4500,7800,2900,12500,6200,15800,9400,3600,
                  5100,18900,4200,2700,5600,8300,6900])[v_i],
           10 + floor(random() * 40)::int,
           true,
           now() - interval '90 days' + (v_i || ' days')::interval)
      returning id into v_product;
    v_products := v_products || v_product;
  end loop;

  -- ---- 4. les clientes ----------------------------------------------
  for v_i in 1..15 loop
    v_client := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                            email_confirmed_at, created_at, updated_at,
                            raw_app_meta_data, raw_user_meta_data)
         values ('00000000-0000-0000-0000-000000000000', v_client,
                 'authenticated', 'authenticated',
                 'demo.cliente' || v_i || '@mesk.mr', '',
                 now(), now() - interval '90 days', now(),
                 '{"provider":"email","providers":["email"]}'::jsonb,
                 jsonb_build_object('full_name', v_names[v_i]));
    update public.profiles set city = 'Nouakchott', phone = '222' || (10000000 + v_i * 37)::text
     where id = v_client;
    v_clients := v_clients || v_client;
  end loop;

  -- ---- 5. les commandes ----------------------------------------------
  --
  -- Le volume dépend du JOUR DE LA SEMAINE, pour que « votre jour le plus
  -- actif est vendredi » soit une observation vraie lue dans les données,
  -- et pas une phrase écrite en dur dans l'application. Le vendredi est
  -- le jour de repos hebdomadaire en Mauritanie : c'est le pic d'achat.
  --
  -- Une légère croissance dans le temps rend l'indicateur d'évolution du
  -- tableau de bord positif — comme dans la vraie vie d'une boutique qui
  -- démarre, et ça donne quelque chose à commenter pendant la démo.
  for v_i in reverse 89..0 loop
    v_day  := (now() - (v_i || ' days')::interval)::date;
    v_weight := case extract(dow from v_day)::int
                  when 0 then 1  -- dimanche
                  when 1 then 2
                  when 2 then 2
                  when 3 then 2
                  when 4 then 3  -- jeudi, veille du week-end
                  when 5 then 6  -- VENDREDI
                  when 6 then 4  -- samedi
                end;
    v_growth := 1.0 + ((90 - v_i)::numeric / 90) * 0.7;
    v_n := floor(random() * v_weight * v_growth)::int;

    for v_pick in 1..greatest(v_n, 0) loop
      v_when := v_day + (8 + floor(random() * 13) || ' hours')::interval
                      + (floor(random() * 60) || ' minutes')::interval;

      -- Bankily domine, comme sur le marché mauritanien.
      v_provider := case
        when random() < 0.60 then 'Bankily'
        when random() < 0.65 then 'Masrvi'
        else 'Sedad' end;

      -- Les commandes récentes sont encore en cours ; les anciennes sont
      -- livrées. Quelques-unes restent en attente de vérification, sinon
      -- l'écran de vérification du paiement n'a rien à montrer.
      if v_i < 3 then
        v_status := 'pending'; v_paystatus := 'submitted';
      elsif v_i < 7 then
        v_status := (array['confirmed','preparing','delivering'])[1 + floor(random()*3)::int];
        v_paystatus := 'verified';
      else
        v_status := 'delivered'; v_paystatus := 'verified';
      end if;
      if random() < 0.03 then
        v_paystatus := 'rejected'; v_status := 'cancelled';
      end if;

      v_client := v_clients[1 + floor(random() * array_length(v_clients, 1))::int];

      insert into public.orders
             (client_id, shop_id, status, total, client_full_name, client_phone,
              client_city, client_address, payment_reference, payment_provider,
              payment_status, payment_verified_at, delivery_mode, created_at, confirmed_at)
           values
             (v_client, v_shop, v_status, 0,
              (select full_name from public.profiles where id = v_client),
              (select phone from public.profiles where id = v_client),
              'Nouakchott', 'Tevragh Zeina, Nouakchott',
              upper(v_provider) || '-' || to_char(v_when, 'YYMMDD') || '-' ||
                lpad(floor(random() * 1000000)::text, 6, '0') || '-' || v_order_count,
              v_provider, v_paystatus,
              case when v_paystatus = 'verified' then v_when + interval '2 hours' end,
              case when random() < 0.6 then 'delivery' else 'pickup' end,
              v_when,
              case when v_status <> 'pending' then v_when + interval '3 hours' end)
        returning id into v_order;

      v_order_count := v_order_count + 1;

      -- 1 à 3 lignes par commande. Le prix unitaire est de toute façon
      -- relu depuis `products` par `order_item_price_guard`, et
      -- `orders.total` recalculé par `order_total_recompute` : les zéros
      -- envoyés ici sont corrigés par la base elle-même.
      -- `v_item` et `v_prod` sont propres à cette boucle : réutiliser les
      -- compteurs de la boucle extérieure rendrait le script illisible même
      -- si PL/pgSQL masque bien les variables de boucle FOR.
      declare
        v_item int;
        v_prod int;
      begin
        for v_item in 1..(1 + floor(random() * 3)::int) loop
          v_prod := 1 + floor(random() * array_length(v_products, 1))::int;
          insert into public.order_items
                 (order_id, product_id, product_name, unit_price, quantity, subtotal)
               values (v_order, v_products[v_prod],
                       (select name from public.products where id = v_products[v_prod]),
                       0, 1 + floor(random() * 2)::int, 0);
        end loop;
      end;
    end loop;
  end loop;

  raise notice 'Démo prête : boutique « Maison Aïcha », 15 produits, 15 clientes, % commandes sur 90 jours.', v_order_count;
end $$;
