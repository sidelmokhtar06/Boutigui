import 'dart:html' as html;
import 'dart:convert';

/// Position réelle via l'API `navigator.geolocation` du navigateur —
/// aucun paquet externe, donc aucune contrainte de version Flutter/Dart
/// supplémentaire (voir la note en tête de `location_service.dart` sur la
/// raison pour laquelle `geolocator` avait été retiré du projet).
///
/// **15 septembre 2026, deuxième correction.** La version précédente
/// affichait littéralement "Instance of 'minified:rU'" en production : en
/// mode `--release`, dart2js renomme les classes en noms courts
/// ("minifiés"), et `PositionError` (l'erreur que le navigateur renvoie
/// vraiment quand la position échoue) n'a pas de `toString()` personnalisé
/// — `'$e'` affichait donc le nom de classe minifié plutôt qu'un message.
/// Ici, on reconnaît explicitement `html.PositionError` et on construit
/// nous-mêmes un message lisible à partir de son `code` (1 = permission
/// refusée, 2 = position indisponible, 3 = délai dépassé) — jamais son
/// `toString()` par défaut.
Future<(double, double)> getBrowserPosition() async {
  try {
    final geo = html.window.navigator.geolocation;
    final pos = await geo.getCurrentPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 15),
    );
    final coords = pos.coords;
    if (coords == null || coords.latitude == null || coords.longitude == null) {
      throw Exception("Could not read your position. Type your address by hand instead.");
    }
    return (coords.latitude!.toDouble(), coords.longitude!.toDouble());
  } on html.PositionError catch (e) {
    final reason = switch (e.code) {
      1 => "location access was denied",
      2 => "your position isn't available right now",
      3 => "it took too long to get a location fix",
      _ => "an unknown error",
    };
    throw Exception("Couldn't get your location ($reason). Type your address by hand instead.");
  } catch (_) {
    // Toute autre erreur (site non servi en HTTPS, API absente de ce
    // navigateur...) : pas de détail fiable à extraire sans risquer le même
    // bug d'affichage qu'avant, donc un message générique mais toujours
    // clair sur ce qu'il reste à faire.
    throw Exception(
      "Location isn't available in this browser or on this connection. Type your address by hand instead.",
    );
  }
}

/// Recherche d'adresse via Nominatim (OpenStreetMap) — service public,
/// gratuit, sans clé ni compte de facturation (voir la doc de
/// `LocationService.searchPlaces`). Utilise directement `HttpRequest`
/// (dart:html), donc aucune dépendance supplémentaire.
///
/// Limite honnête : Nominatim demande normalement un en-tête `User-Agent`
/// identifiant l'application (sa politique d'usage), que le navigateur
/// interdit de fixer soi-même depuis du JavaScript pour des raisons de
/// sécurité — un usage ponctuel depuis un navigateur reste toléré en
/// pratique, mais un usage à très fort volume pourrait un jour être limité
/// par Nominatim. Si ça arrivait, la solution serait de passer par un
/// petit relais côté serveur (une fonction Supabase Edge, par exemple)
/// plutôt que d'appeler Nominatim directement depuis le navigateur.
Future<List<Map<String, dynamic>>> searchPlacesRaw(String query) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'format': 'json',
    'q': query,
    'addressdetails': '0',
    'limit': '6',
  });
  try {
    final response = await html.HttpRequest.getString(uri.toString());
    final decoded = jsonDecode(response);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  } catch (_) {
    throw Exception("Couldn't search for that place. Check your connection and try again.");
  }
}
