-- =====================================================================
-- inclusion_patch.sql — 20 septembre 2026
--
-- À jouer APRÈS `fintech_patch.sql`. Rejouable sans risque.
--
-- Boutigui est ouvert à TOUS les entrepreneurs mauritaniens. Les femmes en
-- sont le public principal — elles tiennent une part décisive du commerce
-- en Mauritanie, et l'application leur parle par défaut — mais personne
-- n'est écarté, et aucune fonctionnalité ne dépend de ce champ.
--
-- Ce que cette colonne EST : une déclaration facultative, faite par la
-- vendeuse elle-même, qui sert uniquement à mesurer l'impact du produit.
--
-- Ce qu'elle n'est PAS, et ne doit jamais devenir :
--
--   * un critère d'accès — aucune boutique n'est refusée ni limitée ;
--   * une entrée de l'indice de préparation financière. Faire peser un
--     attribut personnel protégé sur un signal qui peut orienter un
--     financement, c'est de la discrimination à l'octroi de crédit. Voir
--     `analytics_service.dart`, `_readiness()` : le calcul ne lit que
--     l'activité commerciale, et cette colonne n'y apparaît pas.
--
-- `null` = la question n'a pas été posée ou la personne n'a pas répondu.
-- On ne déduit jamais une valeur à partir d'un prénom.
-- =====================================================================

alter table public.shops
  add column if not exists women_led boolean;

comment on column public.shops.women_led is
  'Déclaration facultative de la propriétaire. Mesure d''impact uniquement : '
  'jamais un critère d''accès, jamais une entrée du score de préparation '
  'financière. null = non renseigné.';

-- Statistiques d'inclusion, agrégées et PUBLIQUES.
--
-- Une fonction `security definer` plutôt qu'une policy ouverte sur
-- `shops` : elle ne renvoie que des COMPTES, jamais la ligne d'une
-- boutique en particulier. Personne ne peut donc savoir, depuis
-- l'application, ce qu'une boutique donnée a déclaré — on ne lit que le
-- total.
create or replace function public.inclusion_stats()
returns table (
  total_shops      bigint,
  women_led_shops  bigint,
  declared_shops   bigint,
  cities           bigint
)
language sql
security definer
stable
set search_path = public
as $$
  select
    count(*)                                          as total_shops,
    count(*) filter (where women_led is true)         as women_led_shops,
    count(*) filter (where women_led is not null)     as declared_shops,
    count(distinct city) filter (where city is not null and city <> '') as cities
  from public.shops
  where is_visible = true;
$$;

grant execute on function public.inclusion_stats() to anon, authenticated;
