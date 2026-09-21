# Services (data layer)

## Overview

Everything that talks to Supabase lives here. Screens never call Supabase
directly: they call a service, or watch one of the `ChangeNotifier`
controllers wired up in `main.dart`. Models in `lib/models/models.dart` mirror
the SQL schema column for column.

## Key files

| File | Owns |
|---|---|
| `catalog_service.dart` | Public reads: shops, categories, products, banners, collections |
| `auth_service.dart` | Sign in (Google only), profile sync, account deletion |
| `order_service.dart` | Checkout, payment proof upload, vendor applications |
| `vendor_service.dart` | The shop owner's own shop, products, photos |
| `admin_service.dart` | Everything the admin console writes |
| `delivery_service.dart` | Driver space, all through RPCs |
| `analytics_service.dart` | Vendor dashboard metrics, financial readiness score, Boutigui Insights sentences. Derives everything from `orders` / `order_items`, stores nothing |
| `storage_service.dart` | Uploads to the 4 buckets, R2 switch, signed URLs |
| `cart_controller.dart`, `role_controller.dart`, `settings_controller.dart`, `notification_service.dart` | `ChangeNotifier` state, provided in `main.dart` |

## Conventions

- A service holds `final SupabaseClient _client = Supabase.instance.client;`
  and nothing else as state. Controllers that need to notify extend
  `ChangeNotifier` and are registered in `main.dart`.
- Parse rows through the model factories (`Product.fromMap`, ...), never read
  raw maps in a screen.
- Reads use bare `select()` without a column list, so a column that has not
  been added yet comes back absent rather than raising. Writes name their
  columns and will fail loudly if the column is missing.
- Reads that can grow are paginated with `AppConfig.pageSize`.
- Comments are in French and explain why, with the date of the decision.
  Match that when you add to a file that already has it.

## Gotchas

- **`analytics_service` splits fetch from compute on purpose.** `fetchForShop`
  does the query, `_build` does the arithmetic on plain maps, so the maths can
  be exercised without a database. Keep new metrics in `_build`.
- **Boutigui Insights never calls a model.** The sentences are generated in Dart.
  The app ships to the web, so an API key in the client would be readable by
  anyone. If a model is wired in later it goes behind a Supabase Edge
  Function, never in the bundle.
- **A write blocked by RLS reports success.** Postgres updates zero rows
  without an error, so a missing policy looks like a silent no op. When a
  non owner writes, add `.select()` and throw if nothing comes back, as
  `order_service.attachPaymentProof` does.
- Secrets arrive only through `--dart-define` and are read in
  `lib/app_config.dart`. Never hardcode a URL or key, and never commit one.
  With none supplied the whole app renders `NotConfiguredScreen` instead of
  crashing, which is the intended behaviour.
- `location/` has a web implementation and a stub chosen by conditional
  import, so the geolocation call compiles on every platform.
- Photos are compressed in Dart before upload (`image_compressor.dart`), in
  two sizes. The package is pure Dart on purpose, so web and Android behave
  the same with no native plugin.
- `notifications` rows are written by database triggers, never by this layer.
  There is no insert path from the app, by design.

## Related specs

None yet.

_Drafted by /audit from the repo, worth a quick human pass. Edit freely: once a line stops matching this draft, later runs treat it as curated and will flag rather than overwrite it._
