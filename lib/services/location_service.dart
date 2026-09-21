import 'dart:math' as math;
import 'location/location_provider_stub.dart' if (dart.library.html) 'location/location_provider_web.dart';

/// Position de livraison — remise en service le 15 septembre 2026 (espace
/// Livreur : le calcul automatique de la distance en kilomètres exige une
/// vraie position, pas seulement une adresse tapée à la main).
///
/// **Pourquoi via `dart:html` et pas le paquet `geolocator`.** `geolocator`
/// avait été retiré du projet (voir l'historique de ce fichier) : ses
/// versions récentes exigent un Flutter/Dart plus récent que celui utilisé
/// ici (3.27.4 / Dart 3.6.2 — voir `pubspec.yaml`), et une version plus
/// ancienne compatible n'existe pas pour Dart 3.6. Comme ce projet est
/// déployé en Flutter WEB (voir `netlify.toml`), on peut obtenir la
/// position directement depuis l'API native `navigator.geolocation` du
/// navigateur (`dart:html`, livré avec le SDK Flutter — donc AUCUNE
/// dépendance ni contrainte de version supplémentaire). L'implémentation
/// vit dans `services/location/*.dart`, séparée par import conditionnel
/// (`if (dart.library.html)`) pour que le code continue de compiler sur
/// Android/iOS/desktop — ces plateformes retombent sur la saisie manuelle
/// d'adresse, déjà prévue partout où `LocationService` est utilisé.
class DeviceLocation {
  final double latitude;
  final double longitude;

  const DeviceLocation({required this.latitude, required this.longitude});

  String get short => '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

/// Un résultat de recherche d'adresse (15 septembre 2026, espace
/// "recherche façon Google Maps" — voir `LocationService.searchPlaces`).
class PlaceResult {
  final String label;
  final double lat;
  final double lng;

  const PlaceResult({required this.label, required this.lat, required this.lng});
}

class LocationService {
  Future<DeviceLocation> currentPosition() async {
    final (lat, lng) = await getBrowserPosition();
    return DeviceLocation(latitude: lat, longitude: lng);
  }

  /// Recherche une adresse/un lieu par son nom — demande explicite du 15
  /// septembre 2026 : "tu dois mettre comme un google maps pour rechercher
  /// une place précis" plutôt que de se limiter à la position GPS brute.
  ///
  /// Pas d'API Google Maps (choix constant du projet — voir
  /// `_LocationField`, cart_screen.dart) : passe par Nominatim
  /// (OpenStreetMap), un service de géocodage public, gratuit et sans clé
  /// ni compte de facturation. Moins riche qu'une vraie autocomplétion
  /// Google (pas de suggestions à chaque frappe, une recherche à la fois),
  /// mais suffisant pour trouver un quartier, une rue ou un lieu connu.
  Future<List<PlaceResult>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    final raw = await searchPlacesRaw(trimmed);
    return raw
        .map((m) {
          final lat = double.tryParse('${m['lat']}');
          final lng = double.tryParse('${m['lon']}');
          final label = m['display_name'] as String?;
          if (lat == null || lng == null || label == null || label.isEmpty) return null;
          return PlaceResult(label: label, lat: lat, lng: lng);
        })
        .whereType<PlaceResult>()
        .toList();
  }

  /// Distance à vol d'oiseau entre deux points, en kilomètres (formule de
  /// Haversine, rayon terrestre moyen 6371 km) — utilisée pour un premier
  /// affichage immédiat côté app (ex. dans le tableau de courses des
  /// livreuses). La valeur qui compte reste toujours celle recalculée côté
  /// base par le trigger de `supabase/livreur_patch.sql`, jamais celle-ci :
  /// ce calcul-ci ne sert qu'à ne pas laisser un écran vide le temps que le
  /// serveur réponde.
  static double distanceKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const r = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) * math.cos(_radians(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return double.parse((r * c).toStringAsFixed(2));
  }

  static double _radians(double deg) => deg * (math.pi / 180);
}
