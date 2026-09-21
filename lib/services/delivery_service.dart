import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Espace "Livreur" (15 septembre 2026, demande explicite) — voir
/// `supabase/livreur_patch.sql` pour le schéma complet et le détail des
/// règles de sécurité. Résumé de ce que fait cette classe :
///
///  - [fetchMyDriverProfile] / [becomeDriver] / [setAvailability] :
///    devenir livreur (une simple ligne dans `driver_profiles`, comme
///    devenir vendeuse ajoute une ligne dans `shops`) et se déclarer
///    disponible ou non.
///  - [streamOpenBoard] : le tableau des courses EN ATTENTE, mis à jour EN
///    TEMPS RÉEL (Supabase Realtime) — une livreuse disponible voit une
///    nouvelle course apparaître sans recharger l'écran. Nécessite que
///    `alter publication supabase_realtime add table delivery_requests`
///    ait été exécuté (fait par le patch SQL).
///  - [acceptRequest] / [markDelivered] : les deux seules transitions
///    permises, via des fonctions RPC atomiques côté base — jamais un
///    `update` direct depuis l'app (voir le patch SQL pour pourquoi).
///  - [fetchContact] : le nom/téléphone/adresse de la cliente, UNIQUEMENT
///    une fois la course acceptée par CE livreur — avant ça, l'app n'a
///    tout simplement pas accès à ces informations, à aucun moment.
class DeliveryService {
  final SupabaseClient _client = Supabase.instance.client;

  static const String _boardSelect =
      'id, order_id, shop_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, distance_km, '
      'status, driver_id, created_at, shops(name, city), orders(total)';

  Future<DriverProfile?> fetchMyDriverProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client.from('driver_profiles').select().eq('id', userId).maybeSingle();
    return row == null ? null : DriverProfile.fromMap(row);
  }

  /// Inscription livreur — ne demande qu'un type de véhicule (facultatif),
  /// exactement comme créer une boutique ne demande que le minimum.
  Future<DriverProfile> becomeDriver({String? vehicleType}) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('driver_profiles')
        .insert({'id': userId, 'vehicle_type': vehicleType, 'is_available': true})
        .select()
        .single();
    return DriverProfile.fromMap(row);
  }

  Future<void> setAvailability(bool available) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('driver_profiles').update({'is_available': available}).eq('id', userId);
  }

  /// Liste des candidatures livreur en attente — admin uniquement (RLS,
  /// voir `livreur_patch_3_approval.sql`) : jointe à `profiles` pour
  /// afficher un nom plutôt qu'un identifiant technique.
  Future<List<Map<String, dynamic>>> fetchPendingDrivers() async {
    final rows = await _client
        .from('driver_profiles')
        .select('id, vehicle_type, status, created_at, profiles(full_name, email, phone)')
        .eq('status', 'pending')
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> setDriverStatus(String driverId, String status) async {
    await _client.from('driver_profiles').update({'status': status}).eq('id', driverId);
  }

  /// Tableau des courses en attente — flux temps réel plutôt qu'un simple
  /// `select()` unique, pour qu'une nouvelle demande de livraison apparaisse
  /// dès sa création, tant que l'écran de la livreuse reste ouvert (voir la
  /// limite honnête sur les notifications, en tête de `livreur_patch.sql`).
  Stream<List<DeliveryRequest>> streamOpenBoard() {
    return _client
        .from('delivery_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at')
        .map((rows) => rows.map((r) => DeliveryRequest.fromMap(r)).toList());
    // Remarque : `.stream()` ne peut pas embarquer la jointure
    // `shops(name, city)` utilisée par `_boardSelect` (limite de l'API
    // realtime de supabase_flutter, qui ne suit que la table elle-même) —
    // le nom de la boutique est donc réattaché à part, voir
    // [_attachShopNames], utilisé par l'écran plutôt que directement ici
    // pour garder ce flux simple et rapide à démarrer.
  }

  /// Les noms de boutique correspondant à une liste de courses — appelé par
  /// l'écran juste après avoir reçu une mise à jour de [streamOpenBoard],
  /// pour compléter l'affichage sans dupliquer la logique de jointure.
  Future<Map<String, Shop>> fetchShopsFor(List<DeliveryRequest> requests) async {
    final ids = requests.map((r) => r.shopId).toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await _client.from('shops').select().inFilter('id', ids);
    return {for (final row in rows) row['id'] as String: Shop.fromMap(row)};
  }

  /// Mes courses (en cours ou livrées) — celles où je suis la livreuse
  /// assignée, les plus récentes d'abord.
  Future<List<DeliveryRequest>> fetchMyDeliveries() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await _client
        .from('delivery_requests')
        .select(_boardSelect)
        .eq('driver_id', userId)
        .order('created_at', ascending: false);
    return rows.map((r) => DeliveryRequest.fromMap(r)).toList();
  }

  /// Accepte une course — atomique côté base (voir
  /// `accept_delivery_request` dans le patch SQL) : si une autre livreuse
  /// vient de l'accepter à l'instant, cet appel échoue proprement avec un
  /// message clair plutôt que de créer une double affectation.
  Future<DeliveryRequest> acceptRequest(String requestId) async {
    final row = await _client.rpc('accept_delivery_request', params: {'p_request_id': requestId});
    return DeliveryRequest.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<DeliveryRequest> markDelivered(String requestId) async {
    final row = await _client.rpc('mark_delivery_delivered', params: {'p_request_id': requestId});
    return DeliveryRequest.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Contact de la cliente — seul point d'accès à ces informations, et
  /// seulement pour la course que j'ai acceptée (voir `get_delivery_contact`
  /// dans le patch SQL, qui vérifie `driver_id = auth.uid()` côté base).
  Future<DeliveryContact?> fetchContact(String requestId) async {
    final rows = await _client.rpc('get_delivery_contact', params: {'p_request_id': requestId});
    final list = rows as List;
    if (list.isEmpty) return null;
    return DeliveryContact.fromMap(Map<String, dynamic>.from(list.first as Map));
  }
}
