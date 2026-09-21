import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'delivery_service.dart';
import 'vendor_service.dart';

/// Rôle du compte connecté : simple cliente, vendeuse, et/ou livreuse — un
/// même compte peut cumuler plusieurs rôles (voir `openMyShop` et l'espace
/// Livreur, tous deux accessibles depuis le même compte client).
///
/// Ajouté le 6 septembre 2026. L'inscription vit dans le bouton central de
/// la barre du bas ; l'écran Compte n'affiche que l'accès à son espace,
/// quand il existe.
///
/// **15 septembre 2026 : l'espace Livreur, retiré le 6 septembre 2026, est
/// réintroduit** — sur le même principe que la boutique : l'existence
/// d'une ligne dans `driver_profiles` suffit à dire "ce compte livre
/// aussi" (voir `DeliveryService`), pas de nouvelle colonne de rôle sur
/// `profiles`.
///
/// Relu à la demande (au lancement, après une inscription, après une
/// connexion) plutôt qu'en continu : le rôle ne change qu'à ces
/// moments-là.
class RoleController extends ChangeNotifier {
  final VendorService _vendor = VendorService();
  final DeliveryService _delivery = DeliveryService();

  Shop? _shop;
  DriverProfile? _driverProfile;
  bool _loaded = false;

  Shop? get shop => _shop;
  DriverProfile? get driverProfile => _driverProfile;
  bool get loaded => _loaded;

  /// A une boutique — même pas encore validée : elle doit pouvoir y
  /// ajouter ses produits en attendant.
  bool get isVendor => _shop != null;

  /// A un profil livreur (indépendamment de sa disponibilité actuelle).
  bool get isDriver => _driverProfile != null;

  Future<void> refresh() async {
    try {
      _shop = await _vendor.fetchMyShop();
    } catch (_) {
      // Pas de session, pas de réseau : on reste sur "simple cliente",
      // c'est le comportement le plus sûr — au pire, la personne repasse
      // par le parcours d'inscription, qui la reconnaîtra.
      _shop = null;
    }
    try {
      _driverProfile = await _delivery.fetchMyDriverProfile();
    } catch (_) {
      _driverProfile = null;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Vide le rôle (déconnexion).
  void clear() {
    _shop = null;
    _driverProfile = null;
    _loaded = false;
    notifyListeners();
  }
}
