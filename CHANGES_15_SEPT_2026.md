# Changes — 15 September 2026

Same Flutter/Dart version as before (3.27.4 / Dart ^3.5.0). No new
packages were added to `pubspec.yaml`.

## 1. App is now English-only
`Strings.t()` always resolves the English text, even if someone opens the
language sheet (Account → Country and language) and taps "Français" —
the picker still shows and remembers a choice, but the app itself stays in
English everywhere. Also swept and translated leftover hardcoded French
text across the app (error messages, color-swatch names, vendor-form
validators, etc.), including the "Espace vendeuse" label mentioned in your
request, which is now properly translated ("Seller space") through the
same translation system instead of being hardcoded.

## 2. Confirm-order form cleaned up, pink removed
- The pink accent is gone from the whole client app (it came from
  `AppTheme.pink`/`colorScheme.secondary`, used by default on selected
  chips/segments — now neutral black/grey everywhere).
- The "Delivery / I'll pick it up" segmented control was rebuilt as a
  plain black-and-white toggle.
- Copy cleaned up and translated, clearer section labels added.
- The admin site keeps its own separate dark theme, untouched, as before.

## 3. Delivery driver ("Livreur") space — new
- **Backend**: run `supabase/livreur_patch.sql` once in your Supabase SQL
  editor (after your existing schema). It adds:
  - `shops.lat` / `shops.lng` — a pickup point vendors can set from "My
    shop" (new "Use my location" button, optional).
  - `driver_profiles` — becoming a driver just adds a row here, the same
    way creating a shop makes someone a vendor.
  - `delivery_requests` — the board of deliveries. **It never stores the
    customer's name, phone, or address** — only the shop, a map point, and
    the distance. Distance is recalculated server-side (a trigger), never
    trusted from the app.
  - Three database functions are the only way to accept a delivery, mark
    it delivered, or read the customer's contact info — and that contact
    function only returns anything for the driver who accepted that exact
    delivery. Two drivers can't accidentally accept the same job (it's
    atomic on the database side).
  - Realtime is turned on for the board so available drivers see new jobs
    live.
- **App**: Account → "Delivery space" (always visible) → Google
  sign-in/registration (same account system as everything else) → pick a
  vehicle → live board with an online/offline switch, an "Available" tab
  (accept jobs) and a "My deliveries" tab (contact reveal + mark
  delivered, with call/WhatsApp buttons).
- **Honest limitation**: notifications are real-time only while the app is
  open (Supabase Realtime) — not a phone-native push notification when the
  app is fully closed. That would need Firebase Cloud Messaging or Web
  Push set up with your own project credentials, which isn't part of this
  change.
- Geolocation itself was actually broken before this change (the
  `geolocator` package had been removed for Flutter-version reasons, and
  nothing replaced it) — it now works again for this web build via the
  browser's own location API, with no new dependency.

## 4. Sign-up is Google-only
The leftover email/password form (used only for a couple of legacy
sign-ins, never for creating new accounts) was removed from the
customer-facing login screen and the seller sign-up screen. Both now show
only "Continue with Google". The separate admin login is untouched.

## 5. "Add to Bag"
The button is now labeled "Add to Bag"; tapping it opens a confirmation
sheet (photo, brand, name, selected option, price) with "Go to bag" (jumps
straight to the Bag tab) and "Keep shopping".

## 6. Bag icon
The bottom tab bar's cart icon was replaced with a tote-bag icon, and the
tab is now labeled "Bag".

## Not included
Anything to do with the internal admin site (`lib/admin/**`) was left as
you had it — none of the six requests mentioned it, and it's explicitly a
separate, internal tool in this codebase.
