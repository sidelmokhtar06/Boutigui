-- =====================================================================
-- ESPACE "LIVREUR" — validation par l'administrateur, 15 septembre 2026.
--
-- À exécuter UNE FOIS dans Supabase > SQL Editor, APRÈS `livreur_patch.sql`
-- ET `livreur_patch_2_grants.sql`.
--
-- Demande explicite : "Ce n'est pas n'importe quel livreur : il ne peut
-- recevoir les livraisons que si l'administrateur accepte ce livreur."
-- Jusqu'ici, s'inscrire comme livreur (`driver_profiles`) suffisait à
-- apparaître immédiatement sur le tableau de courses — exactement comme
-- une boutique nouvellement créée était visible tout de suite, AVANT le
-- correctif équivalent côté boutiques (`shops.is_visible`, dans le schéma
-- d'origine). Ce patch applique le même principe aux livreurs.
-- =====================================================================

alter table public.driver_profiles
  add column if not exists status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected'));

-- Le tableau de courses ("pending" côté delivery_requests) n'est
-- maintenant visible que pour un livreur dont le compte est APPROUVÉ —
-- avant, n'importe quel compte avec une ligne dans `driver_profiles`
-- (même fraîchement créée) pouvait voir et accepter des courses.
drop policy if exists "delivery_requests_select" on public.delivery_requests;
create policy "delivery_requests_select"
  on public.delivery_requests for select
  using (
    (status = 'pending' and exists (
      select 1 from public.driver_profiles dp
      where dp.id = auth.uid() and dp.status = 'approved'
    ))
    or driver_id = auth.uid()
    or exists (select 1 from public.orders o where o.id = order_id and o.client_id = auth.uid())
    or exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Même garde-fou côté acceptation : la fonction refusait déjà un compte
-- sans AUCUN profil livreur ; elle refuse maintenant aussi un profil
-- livreur qui existe mais n'est pas encore (ou plus) approuvé.
create or replace function public.accept_delivery_request(p_request_id uuid)
returns public.delivery_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.delivery_requests;
begin
  if not exists (
    select 1 from public.driver_profiles where id = auth.uid() and status = 'approved'
  ) then
    raise exception 'Your driver account is not approved yet.';
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

-- Admin uniquement : approuver ou rejeter un livreur (site admin,
-- lib/admin/drivers_admin_screen.dart). `profiles.role = 'admin'` est déjà
-- la même vérification utilisée partout ailleurs dans ce schéma pour
-- distinguer un compte admin (voir `profiles_select_own_or_admin` etc. dans
-- marketplace_schema.sql).
drop policy if exists "driver_profiles_update_admin" on public.driver_profiles;
create policy "driver_profiles_update_admin"
  on public.driver_profiles for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- L'admin doit aussi pouvoir lister TOUS les profils livreur (pas
-- seulement le sien) pour les approuver — la policy SELECT posée par
-- `livreur_patch.sql` le permettait déjà (elle inclut un cas admin), rien
-- à changer ici ; ce commentaire sert seulement à le confirmer par écrit.
