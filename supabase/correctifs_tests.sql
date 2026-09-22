-- =====================================================================
-- correctifs_tests.sql — 21 septembre 2026
--
-- Preuve que `correctifs_patch.sql` fait ce qu'il prétend. À coller dans
-- l'éditeur SQL de Supabase APRÈS le patch.
--
-- Même principe que `fintech_tests.sql` : tout se déroule dans une
-- transaction annulée à la fin, la base ressort exactement dans l'état où
-- elle est entrée, il n'y a rien à nettoyer. Et comme là-bas, les
-- résultats sont accumulés dans une table temporaire plutôt qu'envoyés
-- par `raise notice`, que l'éditeur SQL de Supabase n'affiche pas.
--
-- Chaque test reproduit l'ATTAQUE ou le BUG décrit dans l'en-tête du
-- patch, et échoue bruyamment si le trou est encore ouvert. Un test qui
-- « passe » ici veut dire : la base a refusé ce qu'elle acceptait avant.
--
-- La bascule `set local role authenticated` + `request.jwt.claims` imite
-- une vraie personne connectée : sans elle `auth.uid()` est nul dans
-- l'éditeur SQL et aucun des gardes ne se déclenche.
-- =====================================================================

begin;

create temp table _resultats (n int, test text, resultat text) on commit drop;

do $$
declare
  v_client   uuid := gen_random_uuid();
  v_vendor   uuid := gen_random_uuid();
  v_pirate   uuid := gen_random_uuid();
  v_shop     uuid;
  v_product  uuid;
  v_order    uuid;
  v_order2   uuid;
  v_review   uuid;
  v_stock    int;
  v_status   text;
  v_count    int;
  v_failed   boolean;
begin
  -- ---- décor minimal ------------------------------------------------
  -- Trois comptes : la vendeuse, sa cliente, et un compte quelconque qui
  -- va essayer de devenir livreur approuvé tout seul.
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  select '00000000-0000-0000-0000-000000000000', u.id,
         'authenticated', 'authenticated', u.mail, '',
         now(), now(), now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         json_build_object('full_name', u.nom)::jsonb
    from (values (v_vendor, 'vendeuse.c@mesk.mr',  'Vendeuse Test'),
                 (v_client, 'cliente.c@mesk.mr',   'Cliente Test'),
                 (v_pirate, 'pirate.c@mesk.mr',    'Compte Quelconque'))
         as u(id, mail, nom);

  update public.profiles set role = 'vendor' where id = v_vendor;

  insert into public.shops (owner_id, name, city, merchant_code, merchant_provider, is_visible)
       values (v_vendor, 'Boutique Correctifs', 'Nouakchott', 'TEST-002', 'Bankily', true)
    returning id into v_shop;

  -- Stock 3 : assez pour une commande de 2, pas pour une de 4.
  insert into public.products (shop_id, name, price, stock, is_visible)
       values (v_shop, 'Produit Correctifs', 5000, 3, true)
    returning id into v_product;


  -- ===================================================================
  -- On devient la CLIENTE
  -- ===================================================================
  set local role authenticated;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_client, 'role', 'authenticated')::text,
                     true);

  -- ===================================================================
  -- TEST 1 — `create_order` écrit la commande ET ses lignes, d'un bloc
  -- ===================================================================
  select public.create_order(
           v_shop, 'REF-CORR-1', 'Cliente Test', '22000000', 'Nouakchott',
           'Tevragh Zeina', null, null, 'pickup',
           jsonb_build_array(jsonb_build_object(
             'product_id', v_product, 'product_name', 'Produit Correctifs', 'quantity', 2))
         ) into v_order;

  select count(*) into v_count from public.order_items where order_id = v_order;
  select total into v_stock from public.orders where id = v_order;
  if v_count <> 1 or v_stock <> 10000 then
    raise exception 'TEST 1 ÉCHEC : % ligne(s), total % (attendu 1 ligne, 10000)', v_count, v_stock;
  end if;
  insert into _resultats values (1, 'TEST 1 — commande atomique',
    format('1 ligne écrite, total recalculé à %s MRU', v_stock));

  -- ===================================================================
  -- TEST 2 — la commande a bien DÉCRÉMENTÉ le stock
  -- Avant le patch, `products.stock` ne bougeait jamais.
  -- ===================================================================
  select stock into v_stock from public.products where id = v_product;
  if v_stock <> 1 then
    raise exception 'TEST 2 ÉCHEC : stock % après une commande de 2 sur 3 (attendu 1)', v_stock;
  end if;
  insert into _resultats values (2, 'TEST 2 — stock décrémenté',
    format('3 - 2 = %s unité restante', v_stock));

  -- ===================================================================
  -- TEST 3 — on ne peut pas commander plus que le stock
  -- C'est le cas « deux clientes achètent le dernier rouge à lèvres ».
  -- ===================================================================
  v_failed := false;
  begin
    perform public.create_order(
      v_shop, 'REF-CORR-2', 'Cliente Test', '22000000', 'Nouakchott',
      'Tevragh Zeina', null, null, 'pickup',
      jsonb_build_array(jsonb_build_object(
        'product_id', v_product, 'product_name', 'Produit Correctifs', 'quantity', 4)));
  exception when others then
    v_failed := true;
    if position('STOCK_INSUFFISANT' in sqlerrm) = 0 then
      raise exception 'TEST 3 ÉCHEC : refusé, mais pas par le garde de stock (%)', sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'TEST 3 ÉCHEC : 4 unités commandées alors qu''il n''en reste 1';
  end if;
  insert into _resultats values (3, 'TEST 3 — survente refusée',
    'commande de 4 sur 1 en stock rejetée (STOCK_INSUFFISANT)');

  -- ===================================================================
  -- TEST 4 — une cliente ne peut plus gonfler sa commande après coup
  --
  -- Il faut d'abord que la commande cesse d'être un brouillon, et c'est
  -- la VENDEUSE qui la confirme — d'où l'aller-retour de rôle ci-dessous.
  -- ===================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_vendor, 'role', 'authenticated')::text,
                     true);
  update public.orders set status = 'confirmed' where id = v_order;
  select status into v_status from public.orders where id = v_order;
  if v_status <> 'confirmed' then
    raise exception 'TEST 4 ÉCHEC (préparation) : la vendeuse n''a pas pu confirmer (statut %)', v_status;
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_client, 'role', 'authenticated')::text,
                     true);
  v_failed := false;
  begin
    -- La commande est toujours la sienne, mais elle est partie : la
    -- policy doit refuser la ligne supplémentaire.
    insert into public.order_items (order_id, product_id, product_name, unit_price, quantity, subtotal)
         values (v_order, v_product, 'Produit Correctifs', 0, 1, 0);
  exception when others then
    v_failed := true;
  end;
  select count(*) into v_count from public.order_items where order_id = v_order;
  if not v_failed or v_count <> 1 then
    raise exception 'TEST 4 ÉCHEC : la commande est passée de 1 à % ligne(s) après confirmation', v_count;
  end if;
  insert into _resultats values (4, 'TEST 4 — commande non gonflable',
    'ajout de ligne refusé sur une commande qui n''est plus « pending »');

  -- ===================================================================
  -- TEST 5 — la cliente PEUT annuler tant que la boutique n'a rien fait
  -- ===================================================================
  select public.create_order(
           v_shop, 'REF-CORR-3', 'Cliente Test', '22000000', 'Nouakchott',
           'Tevragh Zeina', null, null, 'pickup',
           jsonb_build_array(jsonb_build_object(
             'product_id', v_product, 'product_name', 'Produit Correctifs', 'quantity', 1))
         ) into v_order2;

  select stock into v_stock from public.products where id = v_product;
  if v_stock <> 0 then
    raise exception 'TEST 5 ÉCHEC (préparation) : stock % au lieu de 0', v_stock;
  end if;

  update public.orders set status = 'cancelled' where id = v_order2;
  select status into v_status from public.orders where id = v_order2;
  if v_status <> 'cancelled' then
    raise exception 'TEST 5 ÉCHEC : la commande est restée « % »', v_status;
  end if;
  insert into _resultats values (5, 'TEST 5 — annulation par la cliente',
    'pending -> cancelled accepté (le bouton « Annuler » fonctionne enfin)');

  -- ===================================================================
  -- TEST 6 — l'annulation REND le stock
  -- ===================================================================
  select stock into v_stock from public.products where id = v_product;
  if v_stock <> 1 then
    raise exception 'TEST 6 ÉCHEC : stock % après annulation d''une commande de 1 (attendu 1)', v_stock;
  end if;
  insert into _resultats values (6, 'TEST 6 — stock rendu à l''annulation',
    format('l''unité annulée est revenue en rayon (stock = %s)', v_stock));

  -- ===================================================================
  -- TEST 7 — une cliente ne décide toujours pas de son paiement
  -- (garde repris de fintech/payment_amount : on vérifie qu'il tient
  --  encore après la réécriture de la partie 4)
  -- ===================================================================
  v_failed := false;
  begin
    update public.orders set payment_status = 'verified' where id = v_order;
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    select payment_status into v_status from public.orders where id = v_order;
    if v_status = 'verified' then
      raise exception 'TEST 7 ÉCHEC : la cliente a vérifié son propre paiement';
    end if;
  end if;
  insert into _resultats values (7, 'TEST 7 — paiement non auto-vérifiable',
    'la cliente ne peut toujours pas passer son paiement en « verified »');


  -- ===================================================================
  -- On devient le COMPTE QUELCONQUE qui veut livrer
  -- ===================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_pirate, 'role', 'authenticated')::text,
                     true);

  -- ===================================================================
  -- TEST 8 — un livreur naît « pending », même s'il demande mieux
  -- ===================================================================
  insert into public.driver_profiles (id, vehicle_type, is_available, status)
       values (v_pirate, 'moto', true, 'approved');
  select status into v_status from public.driver_profiles where id = v_pirate;
  if v_status <> 'pending' then
    raise exception 'TEST 8 ÉCHEC : profil livreur créé avec le statut « % »', v_status;
  end if;
  insert into _resultats values (8, 'TEST 8 — livreur créé « pending »',
    'le statut demandé à l''inscription est ignoré');

  -- ===================================================================
  -- TEST 9 — un livreur ne s'approuve pas lui-même
  -- LE TROU LE PLUS GRAVE : il ouvrait le nom, le téléphone et l'adresse
  -- des clientes à n'importe quel compte connecté.
  -- ===================================================================
  v_failed := false;
  begin
    update public.driver_profiles set status = 'approved' where id = v_pirate;
  exception when others then
    v_failed := true;
  end;
  select status into v_status from public.driver_profiles where id = v_pirate;
  if v_status = 'approved' then
    raise exception 'TEST 9 ÉCHEC : le compte s''est approuvé lui-même';
  end if;
  insert into _resultats values (9, 'TEST 9 — pas d''auto-approbation livreur',
    format('statut resté « %s » malgré la tentative', v_status));

  -- ===================================================================
  -- TEST 10 — un livreur non approuvé ne peut pas accepter de course
  -- ===================================================================
  v_failed := false;
  begin
    perform public.accept_delivery_request(gen_random_uuid());
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'TEST 10 ÉCHEC : une course a été acceptée par un compte non approuvé';
  end if;
  insert into _resultats values (10, 'TEST 10 — course refusée',
    'accept_delivery_request rejette un livreur non approuvé');


  -- ===================================================================
  -- On devient la VENDEUSE
  -- ===================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_vendor, 'role', 'authenticated')::text,
                     true);

  -- ===================================================================
  -- TEST 11 — la vendeuse masque un avis, elle ne le réécrit pas
  -- ===================================================================
  reset role;   -- l'avis est posé « par la base », le test porte sur l'UPDATE
  insert into public.reviews (product_id, client_id, order_id, rating, comment)
       values (v_product, v_client, v_order, 1, 'Décevant.')
    returning id into v_review;

  set local role authenticated;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_vendor, 'role', 'authenticated')::text,
                     true);

  v_failed := false;
  begin
    update public.reviews set rating = 5, comment = 'Excellent !' where id = v_review;
  exception when others then
    v_failed := true;
  end;
  select rating into v_count from public.reviews where id = v_review;
  if v_count <> 1 then
    raise exception 'TEST 11 ÉCHEC : la note est passée à % sous la plume de la vendeuse', v_count;
  end if;
  insert into _resultats values (11, 'TEST 11 — avis non réécrivable',
    'la note 1 étoile a résisté à la vendeuse');

  -- ===================================================================
  -- TEST 12 — mais elle peut bien le MASQUER
  -- ===================================================================
  update public.reviews set is_visible = false where id = v_review;
  if (select is_visible from public.reviews where id = v_review) then
    raise exception 'TEST 12 ÉCHEC : la modération ne fonctionne plus';
  end if;
  insert into _resultats values (12, 'TEST 12 — modération conservée',
    'la vendeuse peut toujours masquer un avis');

  reset role;
  insert into _resultats values (99, 'TOTAL', 'Les 12 tests passent');
end $$;

select n as "#", test, resultat as "résultat" from _resultats order by n;

rollback;
