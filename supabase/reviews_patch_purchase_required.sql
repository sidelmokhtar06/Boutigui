-- =====================================================================
-- AVIS — achat obligatoire, 15 septembre 2026.
--
-- À exécuter UNE FOIS dans Supabase > SQL Editor.
--
-- Demande explicite : "un client qui a déjà passé commande [peut] laisser
-- un commentaire, et ce commentaire sera visible dans le menu Reviews".
-- La table `reviews` avait déjà une colonne `order_id` prévue pour ça
-- (voir marketplace_schema.sql), mais la policy d'insertion d'origine
-- n'exigeait qu'un compte connecté (`client_id = auth.uid()`), sans
-- jamais vérifier qu'une commande existe vraiment ni qu'elle contient
-- vraiment ce produit — l'app pouvait choisir un bon `order_id`, mais rien
-- ne l'y obligeait côté base. Ce patch le rend obligatoire.
-- =====================================================================

drop policy if exists "reviews_insert_own" on public.reviews;
create policy "reviews_insert_own"
  on public.reviews for insert
  with check (
    client_id = auth.uid()
    and order_id is not null
    and exists (
      select 1
      from public.orders o
      join public.order_items oi on oi.order_id = o.id
      where o.id = order_id
        and o.client_id = auth.uid()
        and oi.product_id = reviews.product_id
    )
  );
