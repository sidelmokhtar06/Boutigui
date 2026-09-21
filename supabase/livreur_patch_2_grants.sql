-- =====================================================================
-- ESPACE "LIVREUR" — correctif de permissions, 15 septembre 2026.
--
-- À exécuter UNE FOIS dans Supabase > SQL Editor, APRÈS
-- `livreur_patch.sql`. Ne refait rien de ce que ce dernier a déjà fait —
-- ajoute seulement ce qu'il manquait.
--
-- Pourquoi c'était cassé : une policy RLS ("qui a le droit de voir QUELLES
-- lignes") ne remplace jamais le droit d'accès de base sur la TABLE
-- elle-même ("qui a le droit de faire un SELECT/INSERT sur cette table,
-- point"). `livreur_patch.sql` créait bien les policies, mais jamais ce
-- droit de base pour le rôle `authenticated` (celui de tout compte
-- connecté) — d'où l'erreur remontée : "permission denied for table
-- driver_profiles". Les tables du schéma d'origine (`shops`, `orders`...)
-- n'en ont pas besoin ici parce qu'elles l'ont déjà, réglé une fois pour
-- toutes à la création du projet Supabase ; une table ajoutée après coup
-- par une requête SQL indépendante n'en hérite pas automatiquement.
-- =====================================================================

grant select, insert, update on public.driver_profiles to authenticated;
grant select, insert on public.delivery_requests to authenticated;

-- Les fonctions RPC (`accept_delivery_request`, `mark_delivery_delivered`,
-- `get_delivery_contact`) n'ont normalement pas besoin de cette ligne —
-- PostgreSQL accorde `EXECUTE` à tout le monde par défaut à la création
-- d'une fonction — mais l'écrire explicitement ne coûte rien et évite une
-- mauvaise surprise si ce comportement par défaut a été changé sur ce
-- projet.
grant execute on function public.accept_delivery_request(uuid) to authenticated;
grant execute on function public.mark_delivery_delivered(uuid) to authenticated;
grant execute on function public.get_delivery_contact(uuid) to authenticated;
