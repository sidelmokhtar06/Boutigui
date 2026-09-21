# Supabase schema and migrations

## Overview

Every table, policy, function and storage bucket the app needs lives here as
plain SQL you paste into the Supabase SQL Editor by hand. There is no
migration tool, no `supabase` CLI directory, and no ordering metadata: the
order is the one written below, and nothing enforces it for you.

## Key files

| File | Owns |
|---|---|
| `marketplace_schema.sql` | Base schema: 14 tables, RLS policies, security functions, triggers, 4 storage buckets, sample categories |
| `reviews_patch_purchase_required.sql` | A review requires an order that actually contains the product |
| `livreur_patch.sql` | Driver space: `driver_profiles`, `delivery_requests`, distance trigger, 3 RPCs |
| `livreur_patch_2_grants.sql` | The table level grants `livreur_patch.sql` forgot |
| `livreur_patch_3_approval.sql` | `driver_profiles.status`, so an admin approves a driver |
| `rattrapage_patch.sql` | Rebuild of four patch files the code references but the repo never contained |
| `fintech_patch.sql` | Server side amount integrity and payment status. Adds `orders.payment_status` / `payment_provider` / `payment_verified_at`, retarifies every `order_items` row from `products`, recomputes `orders.total` |
| `payment_amount_patch.sql` | The amount actually received, recorded by the vendor at verification, and the gap against the order total |
| `fintech_tests.sql` | Nine assertions proving `fintech_patch.sql` and `payment_amount_patch.sql` hold. Runs in a rolled back transaction, changes nothing |
| `demo_seed.sql` | Hackathon demo dataset. Needs the vendor account to exist first, created from the app |
| `recompresser_photos.py` | One off script, recompresses photos already uploaded to storage |

## Commands

None. Paste each file into Supabase, SQL Editor, in the order listed above.
Every file is written to be safe to run twice.

`demo_seed.sql` is the exception to "order listed above": it needs the demo
vendor to have signed up through the app first, because `profiles.id`
references `auth.users(id)` and a real login needs a real hashed password.
Fake customers it creates itself.

## Conventions

- Comments are in French and explain **why**, usually with the date the
  decision was made and who asked for it. Keep that style when you add SQL.
- Every policy block is preceded by `drop policy if exists`, and every object
  is created `if not exists`, so a file can always be re run.
- Security sensitive reads go through a `security definer` function rather
  than a relaxed policy (see `shop_follower_count`, `get_delivery_contact`).
- Privilege changes a user must not make themselves are blocked by a trigger,
  not by a policy, so the SQL Editor can still make them (`auth.uid()` is null
  there). That is how the first admin gets created.

## Gotchas

- **A policy is not a grant.** A table added by a later patch does not inherit
  the base `select`/`insert` right for the `authenticated` role, so a correct
  RLS policy still fails with `permission denied for table ...`. This already
  happened once and cost a whole patch file (`livreur_patch_2_grants.sql`).
  Add explicit `grant` lines whenever you create a table.
- **Four patch files named in the code do not exist in this repo**:
  `admin_patch.sql`, `paiement_options_patch.sql`, `securite_patch.sql` and
  `profiles_trigger_patch.sql`. `rattrapage_patch.sql` rebuilds what they must
  have contained, reconstructed from what the app reads and writes plus the
  live database, column by column. Its column names are certain; its RLS
  policies and notification triggers are informed guesses, flagged as such in
  its header. Prefer the originals if they ever turn up.
- **`orders_payment_reference_unique` is load bearing by name**:
  `cart_screen.dart` looks for that exact string in the raw Postgres error to
  show a friendly message. Renaming the index silently degrades the error.
- **An update blocked by RLS is not an error.** Postgres updates zero rows and
  reports success, so a missing policy looks like a feature that quietly does
  nothing. `order_service.attachPaymentProof` guards against this with
  `.select()` and an explicit throw; do the same for any new write a
  non owner performs.
- **`orders.total` is no longer what the client sent.** Since
  `fintech_patch.sql`, a client insert forces `total = 0` and the real value
  is recomputed from `order_items`, whose `unit_price` is itself re read from
  `products`. Code that inserts an order and expects to read its own total
  back must re select the row. Data seeded from the SQL Editor is exempt from
  the zeroing (`auth.uid()` is null there) but still gets the recompute.
- **The total recompute writes to `orders` from a trigger**, which wakes
  `client_order_update_guard`. They talk to each other through the
  transaction local flag `mesk.total_recompute`. Touch one, check the other.
- `profiles.role` cannot be raised from inside the app. Become admin with
  `update public.profiles set role = 'admin' where email = '...'` in the SQL
  Editor, after signing in once.

## Related specs

None yet.

_Drafted by /audit from the repo, worth a quick human pass. Edit freely: once a line stops matching this draft, later runs treat it as curated and will flag rather than overwrite it._
