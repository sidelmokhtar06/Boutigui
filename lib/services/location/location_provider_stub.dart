/// Version de repli pour toute plateforme sans `dart:html` (Android, iOS,
/// desktop natif). Ce projet n'embarque aucun plugin de géolocalisation
/// (voir la note en tête de `location_service.dart`) : sur ces
/// plateformes, on ne peut donc pas demander la position au système —
/// seule la saisie d'adresse à la main (déjà prévue dans les écrans qui
/// utilisent `LocationService`) reste disponible.
Future<(double, double)> getBrowserPosition() {
  throw Exception(
    "Automatic location isn't available on this build. Type your address by hand instead.",
  );
}

/// Recherche d'adresse — voir `location_provider_web.dart` pour la vraie
/// implémentation (web uniquement, via Nominatim/OpenStreetMap).
Future<List<Map<String, dynamic>>> searchPlacesRaw(String query) {
  throw Exception("Place search isn't available on this build. Type your address by hand instead.");
}
