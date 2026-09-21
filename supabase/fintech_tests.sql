-- =====================================================================
-- fintech_tests.sql — 20 septembre 2026
--
-- Preuve que `fintech_patch.sql` et `payment_amount_patch.sql` font ce
-- qu'ils prétendent. À coller dans
-- l'éditeur SQL de Supabase APRÈS le patch.
--
-- Tout se déroule dans une transaction annulée à la fin : la base
-- ressort exactement dans l'état où elle est entrée. Rien à nettoyer.
--
-- Utile deux fois : pour vérifier le patch, et pour le montrer à un jury
-- qui demande « qu'est-ce qui empêche un client de payer 1 MRU ? ».
--
-- La bascule `set local role authenticated` + `request.jwt.claims` est la
-- façon d'imiter une vraie cliente connectée : sans elle `auth.uid()` est
-- nul dans l'éditeur SQL et aucun des gardes côté cliente ne se déclenche.
-- =====================================================================

begin;

-- Les résultats sont ACCUMULÉS dans une table plutôt qu'envoyés par
-- `raise notice` : l'éditeur SQL de Supabase n'affiche pas les notices,
-- on ne verrait donc rien du tout. Une table s'affiche, et se montre à un
-- jury. La table disparaît avec la transaction.
create temp table _resultats (n int, test text, resultat text) on commit drop;

do $$
declare
  v_client   uuid := gen_random_uuid();
  v_vendor   uuid := gen_random_uuid();
  v_shop     uuid;
  v_product  uuid;
  v_order    uuid;
  v_total    numeric;
  v_price    numeric;
  v_failed   boolean;
begin
  -- ---- décor minimal ------------------------------------------------
  -- `profiles.id` référence `auth.users(id)` : on ne peut donc pas
  -- fabriquer un profil directement. On insère dans `auth.users`, et le
  -- déclencheur `on_auth_user_created` (marketplace_schema.sql, 4.1) crée
  -- le profil tout seul. `encrypted_password` vide = compte qui ne peut
  -- pas se connecter, ce qui convient à un compte de test.
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
       values ('00000000-0000-0000-0000-000000000000', v_vendor,
               'authenticated', 'authenticated', 'vendeuse.test@mesk.mr', '',
               now(), now(), now(),
               '{"provider":"email","providers":["email"]}'::jsonb,
               '{"full_name":"Vendeuse Test"}'::jsonb),
              ('00000000-0000-0000-0000-000000000000', v_client,
               'authenticated', 'authenticated', 'cliente.test@mesk.mr', '',
               now(), now(), now(),
               '{"provider":"email","providers":["email"]}'::jsonb,
               '{"full_name":"Cliente Test"}'::jsonb);

  update public.profiles set role = 'vendor' where id = v_vendor;

  insert into public.shops (owner_id, name, city, merchant_code, merchant_provider, is_visible)
       values (v_vendor, 'Boutique Test', 'Nouakchott', 'TEST-001', 'Bankily', true)
    returning id into v_shop;

  insert into public.products (shop_id, name, price, stock, is_visible)
       values (v_shop, 'Produit Test', 5000, 10, true)
    returning id into v_product;

  -- ---- on devient la cliente ---------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_client, 'role', 'authenticated')::text,
                     true);

  -- ===================================================================
  -- TEST 1 — le total envoyé à la création est ignoré
  -- ===================================================================
  insert into public.orders
         (client_id, shop_id, total, client_full_name, client_phone, payment_reference)
       values
         (v_client, v_shop, 999999, 'Cliente Test', '22000000', 'REF-TEST-1')
    returning id into v_order;

  select total into v_total from public.orders where id = v_order;
  if v_total <> 0 then
    raise exception 'TEST 1 ÉCHEC : le total client a été accepté (%)', v_total;
  end if;
  insert into _resultats values (1, 'TEST 1', format('total annoncé 999999, total enregistré %s', v_total));

  -- ===================================================================
  -- TEST 2 — le prix unitaire est relu depuis `products`
  -- Le client annonce 1 MRU pour un produit à 5000 MRU.
  -- ===================================================================
  insert into public.order_items
         (order_id, product_id, product_name, unit_price, quantity, subtotal)
       values
         (v_order, v_product, 'Produit Test', 1, 2, 2);

  select unit_price, subtotal into v_price, v_total
    from public.order_items where order_id = v_order;
  if v_price <> 5000 or v_total <> 10000 then
    raise exception 'TEST 2 ÉCHEC : prix % / sous-total % (attendu 5000 / 10000)', v_price, v_total;
  end if;
  insert into _resultats values (2, 'TEST 2', format('prix annoncé 1 MRU, prix facturé %s MRU', v_price));

  -- ===================================================================
  -- TEST 3 — `orders.total` suit les lignes, automatiquement
  -- ===================================================================
  select total into v_total from public.orders where id = v_order;
  if v_total <> 10000 then
    raise exception 'TEST 3 ÉCHEC : total recalculé % (attendu 10000)', v_total;
  end if;
  insert into _resultats values (3, 'TEST 3', format('total recalculé par la base : %s MRU', v_total));

  -- ===================================================================
  -- TEST 4 — une cliente ne peut pas déclarer son paiement vérifié
  -- ===================================================================
  v_failed := false;
  begin
    update public.orders set payment_status = 'verified' where id = v_order;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 4 ÉCHEC : la cliente a pu vérifier son propre paiement';
  end if;
  insert into _resultats values (4, 'TEST 4', 'vérification du paiement refusée à la cliente');

  -- ===================================================================
  -- TEST 5 — une cliente ne peut pas changer le total après coup
  -- ===================================================================
  v_failed := false;
  begin
    update public.orders set total = 1 where id = v_order;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 5 ÉCHEC : la cliente a pu réécrire le total';
  end if;
  insert into _resultats values (5, 'TEST 5', 'réécriture du total refusée à la cliente');

  -- ===================================================================
  -- TEST 6 — une référence de paiement ne sert qu'une fois
  -- ===================================================================
  v_failed := false;
  begin
    insert into public.orders
           (client_id, shop_id, total, client_full_name, client_phone, payment_reference)
         values
           (v_client, v_shop, 0, 'Cliente Test', '22000000', 'REF-TEST-1');
  exception when unique_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 6 ÉCHEC : la même référence a servi deux fois';
  end if;
  insert into _resultats values (6, 'TEST 6', 'référence de paiement rejouée : refusée');

  -- ===================================================================
  -- TEST 7 — le montant reçu n'est pas déclaré par la cliente
  -- Ajouté le 21 septembre 2026 avec `payment_amount_patch.sql`.
  -- ===================================================================
  v_failed := false;
  begin
    update public.orders set payment_amount_received = 10000 where id = v_order;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 7 ÉCHEC : la cliente a pu déclarer le montant reçu';
  end if;
  insert into _resultats values (7, 'TEST 7', 'déclaration du montant refusée à la cliente');

  -- ---- on devient la VENDEUSE ---------------------------------------
  --
  -- `reset role` ne suffit pas : il rend son rôle à la session, mais
  -- laisse `request.jwt.claims` en place — donc `auth.uid()` continue de
  -- renvoyer la cliente, et le garde des paiements refuse la suite (c'est
  -- d'ailleurs la preuve qu'il fonctionne). Il faut changer l'identité,
  -- pas seulement le rôle.
  --
  -- Passer à la vendeuse rend les deux tests suivants plus justes : ils
  -- vérifient qu'elle PEUT enregistrer un montant, là où les tests 4 et 7
  -- ont vérifié que la cliente ne le peut pas.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_vendor, 'role', 'authenticated')::text,
                     true);

  -- ===================================================================
  -- TEST 8 — un écart de montant est visible
  -- La vendeuse relève 100 MRU pour une commande de 10 000 : le cas
  -- exact qu'aucun autre contrôle n'attrapait.
  -- ===================================================================
  update public.orders
     set payment_status = 'verified', payment_amount_received = 100
   where id = v_order;

  select public.payment_gap(o) into v_total from public.orders o where o.id = v_order;
  if v_total is null or v_total <> -9900 then
    raise exception 'TEST 8 ÉCHEC : écart calculé % (attendu -9900)', v_total;
  end if;
  insert into _resultats values (8, 'TEST 8', format('écart détecté : %s MRU', v_total));

  -- ===================================================================
  -- TEST 9 — un paiement rejeté oublie le montant relevé
  -- ===================================================================
  update public.orders set payment_status = 'rejected' where id = v_order;
  select payment_amount_received into v_total from public.orders where id = v_order;
  if v_total is not null then
    raise exception 'TEST 9 ÉCHEC : le montant est resté après rejet (%)', v_total;
  end if;
  insert into _resultats values (9, 'TEST 9', 'montant effacé au rejet du paiement');

  reset role;
  insert into _resultats values (99, 'TOTAL', 'Les 9 tests passent');
end $$;

select n as "#", test, resultat as "résultat" from _resultats order by n;

rollback;
