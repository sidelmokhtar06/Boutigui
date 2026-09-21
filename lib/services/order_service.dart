import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'cart_controller.dart';
import 'storage_service.dart';

/// Création des commandes et suivi côté client.
///
/// Une commande = une boutique : un panier avec des produits de plusieurs
/// boutiques est découpé en autant de commandes séparées à la validation.
class OrderService {
  final SupabaseClient _client = Supabase.instance.client;
  final StorageService _storage = StorageService();

  /// Crée une commande par boutique présente dans le panier.
  ///
  /// **Refait le 6 septembre 2026 — paiement par code marchand.** Emina :
  /// "la capture d'écran n'est pas sécurisé [...] les applications
  /// bancaires en Mauritanie donnent un code marchand pour les vendeurs
  /// [...] le client doit mettre dans le formulaire le code reçu par
  /// Bankily [...] la commande ne vient pas pour le vendeur que si le
  /// client met le code, qui est obligatoire".
  ///
  /// Ce que ça change concrètement :
  ///
  ///  - La cliente paie depuis son application bancaire avec le CODE
  ///    MARCHAND de la boutique, puis saisit ici la RÉFÉRENCE de
  ///    transaction que sa banque lui renvoie. Une référence par boutique,
  ///    puisqu'une commande = une boutique et donc un paiement distinct.
  ///  - Sans référence, aucune commande n'est créée : la vendeuse ne voit
  ///    donc jamais de commande non payée.
  ///  - La référence est enregistrée DANS l'insertion de la commande, pas
  ///    par une modification faite après coup comme l'était la capture —
  ///    ce qui supprime au passage le problème silencieux décrit plus bas
  ///    dans ce fichier (la cliente n'a pas le droit de modifier sa
  ///    commande, donc l'ajout après coup pouvait ne rien enregistrer).
  ///  - Une contrainte d'unicité en base empêche qu'une même référence
  ///    serve pour deux commandes — c'est ça, le vrai gain par rapport à
  ///    la capture d'écran, qu'on pouvait renvoyer autant de fois qu'on
  ///    voulait. Voir `supabase/paiement_options_patch.sql`.
  ///
  /// [deliveryLat]/[deliveryLng] : position donnée par le téléphone de la
  /// cliente, avec son autorisation. La vendeuse l'ouvre ensuite dans
  /// Google Maps par un lien — pas d'API Google Maps, donc pas de clé ni
  /// de compte de facturation.
  ///
  /// [phone] est aussi enregistré sur le profil, pour ne plus avoir à le
  /// redemander la prochaine fois.
  Future<List<String>> checkout(
    CartController cart, {
    required String phone,
    required Map<String, String> paymentReferencesByShop,
    required double? deliveryLat,
    required double? deliveryLng,
    String? deliveryAddress,
    // 'delivery' = la boutique livre la commande ; 'pickup' = la cliente
    // passe la récupérer elle-même (6 septembre 2026). La livraison est
    // organisée par chaque boutique, comme depuis le début du projet.
    String deliveryMode = 'pickup',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) throw Exception('Phone number is required.');
    for (final shopId in cart.linesByShop.keys) {
      final ref = paymentReferencesByShop[shopId]?.trim() ?? '';
      if (ref.isEmpty) {
        throw Exception('Missing payment code for a shop.');
      }
    }
    final cleanAddress = (deliveryAddress ?? '').trim();
    if (deliveryLat == null && cleanAddress.isEmpty) {
      throw Exception('Delivery location is required.');
    }

    final profileRow = await _client.from('profiles').select().eq('id', user.id).single();

    // Service de paiement de chaque boutique, recopié sur la commande
    // (20 septembre 2026) — comme le nom et le téléphone de la cliente :
    // la vendeuse peut changer de banque plus tard, la commande doit
    // garder le service par lequel elle a réellement été payée. C'est
    // aussi ce qui permet la répartition par fournisseur du tableau de
    // bord sans jointure sur `shops`.
    //
    // Une seule requête pour tout le panier, pas une par boutique.
    final shopIds = cart.linesByShop.keys.toList();
    final providerByShop = <String, String?>{};
    try {
      final rows = await _client
          .from('shops')
          .select('id, merchant_provider')
          .inFilter('id', shopIds);
      for (final row in rows) {
        providerByShop[row['id'] as String] = row['merchant_provider'] as String?;
      }
    } catch (_) {
      // Le fournisseur est une information de confort pour les
      // statistiques : s'il manque, la commande doit quand même partir.
      // Le paiement lui-même ne dépend pas de cette colonne.
    }

    final createdOrderIds = <String>[];

    for (final entry in cart.linesByShop.entries) {
      final shopId = entry.key;
      final lines = entry.value;
      // Depuis `supabase/fintech_patch.sql` (20 septembre 2026), ce total
      // est INDICATIF : la base le remet à zéro à l'insertion puis le
      // recalcule à partir des lignes, dont elle retarife elle-même
      // chaque prix unitaire depuis `products`. Un client modifié ne peut
      // donc plus commander à 1 MRU. On continue de l'envoyer pour que
      // l'app reste compatible avec une base où le patch n'a pas encore
      // été joué.
      final total = lines.fold<double>(0, (sum, l) => sum + l.subtotal);

      final orderRow = await _client
          .from('orders')
          .insert({
            'client_id': user.id,
            'shop_id': shopId,
            'total': total,
            'client_full_name': profileRow['full_name'] ?? '',
            'client_phone': cleanPhone,
            'client_city': profileRow['city'],
            // L'adresse écrite de la commande prime sur celle du profil :
            // c'est celle de CETTE livraison.
            'client_address': cleanAddress.isEmpty ? profileRow['address'] : cleanAddress,
            'payment_reference': paymentReferencesByShop[shopId]!.trim(),
            'payment_provider': providerByShop[shopId],
            'delivery_lat': deliveryLat,
            'delivery_lng': deliveryLng,
            'delivery_mode': deliveryMode,
          })
          .select()
          .single();

      final orderId = orderRow['id'] as String;

      // Espace Livreur (15 septembre 2026) : une course n'est proposée aux
      // livreuses que si la cliente a choisi "Delivery" (pas "I'll pick it
      // up") ET a partagé une position — sans ça, il n'y a pas de point
      // d'arrivée à donner. Le point de départ (la boutique) peut manquer
      // si la vendeuse n'a pas encore renseigné sa position dans "Ma
      // boutique" ; la course reste alors visible aux livreuses, simplement
      // sans distance calculée tant que la boutique ne l'a pas renseignée.
      if (deliveryMode == 'delivery' && deliveryLat != null && deliveryLng != null) {
        try {
          final shopRow = await _client.from('shops').select('lat, lng').eq('id', shopId).maybeSingle();
          await _client.from('delivery_requests').insert({
            'order_id': orderId,
            'shop_id': shopId,
            'pickup_lat': shopRow?['lat'],
            'pickup_lng': shopRow?['lng'],
            'dropoff_lat': deliveryLat,
            'dropoff_lng': deliveryLng,
          });
        } catch (e) {
          // La commande elle-même est déjà créée et payée : une course non
          // créée (ex. patch SQL pas encore exécuté par Emina) ne doit pas
          // faire échouer tout le paiement. La boutique garde de toute
          // façon la position de livraison sur la commande elle-même
          // (`orders.delivery_lat/lng`) et peut organiser la livraison sur
          // WhatsApp comme avant.
          // ignore: avoid_print
          print('Delivery request not created: $e');
        }
      }

      final items = lines
          .map((l) => {
                'order_id': orderId,
                'product_id': l.product.id,
                // Option choisie (taille, couleur, ...) ajoutée au nom
                // enregistré (5 septembre 2026) : `order_items` garde un nom
                // recopié au moment de l'achat plutôt qu'une colonne dédiée,
                // pas besoin de migration pour que la vendeuse voie le choix
                // de la cliente dans le détail de la commande.
                'product_name': l.selectedOption == null ? l.product.name : '${l.product.name} — ${l.selectedOption}',
                'unit_price': l.product.price,
                'quantity': l.quantity,
                'subtotal': l.subtotal,
              })
          .toList();
      await _client.from('order_items').insert(items);

      createdOrderIds.add(orderId);
      cart.clearShop(shopId);
    }

    if (cleanPhone != ((profileRow['phone'] as String?) ?? '')) {
      await _client.from('profiles').update({'phone': cleanPhone}).eq('id', user.id);
    }

    return createdOrderIds;
  }

  /// Annulation par la cliente — possible uniquement tant que la vendeuse
  /// n'a pas confirmé le paiement (statut `pending`). Ajouté le
  /// 6 septembre 2026 : jusque-là, une commande passée par erreur restait
  /// là pour toujours, la cliente n'avait aucun moyen d'y toucher.
  ///
  /// La vérification qui compte est côté base (règle + déclencheur de
  /// `paiement_options_patch.sql`) : elle interdit de changer autre chose
  /// que le statut, et seulement de `pending` vers `cancelled`. Le
  /// `.select()` sert à détecter un refus silencieux, comme ailleurs dans
  /// ce fichier.
  Future<void> cancelOrder(String orderId) async {
    final updated = await _client
        .from('orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId)
        .eq('status', 'pending')
        .select('id');
    if (updated.isEmpty) {
      throw Exception(
        'This order can no longer be cancelled: the shop has already taken it in charge.',
      );
    }
  }

  Future<List<OrderModel>> fetchMyOrders() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final rows = await _client
        .from('orders')
        .select('*, shops(name)')
        .eq('client_id', user.id)
        .order('created_at', ascending: false);
    return rows.map((r) => OrderModel.fromMap(r)).toList();
  }

  /// Envoie la capture de paiement dans le bucket privé, puis l'attache à
  /// la commande.
  ///
  /// **Vérification ajoutée le 5 septembre 2026 (audit).** Le fichier
  /// partait bien dans le stockage, mais la ligne `update` qui l'attache à
  /// la commande peut ne toucher AUCUNE ligne sans lever la moindre
  /// erreur : le schéma d'origine n'autorise que la vendeuse et l'admin à
  /// modifier une commande (`orders_update_vendor_or_admin`), jamais la
  /// cliente — et PostgreSQL ne signale pas un `update` qui ne trouve
  /// aucune ligne autorisée, il en modifie simplement zéro. Résultat
  /// possible : la capture existe dans le stockage mais la vendeuse ne la
  /// voit jamais, sans qu'aucun message ne l'indique.
  ///
  /// Le `.select()` ci-dessous rend cet échec visible : si rien ne revient,
  /// c'est que la règle manque. Correctif côté base : partie 2 de
  /// `supabase/securite_patch.sql`.
  Future<void> attachPaymentProof({
    required String orderId,
    required Uint8List bytes,
    String extension = 'jpg',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final path = await _storage.uploadPaymentProof(
      userId: user.id,
      orderId: orderId,
      bytes: bytes,
      extension: extension,
    );
    final updated = await _client
        .from('orders')
        .update({'payment_proof_url': path})
        .eq('id', orderId)
        .select('id');
    if (updated.isEmpty) {
      throw Exception(
        'The payment proof could not be attached to the order '
        '(the database refused the update). The order itself was '
        'created. Fix: run supabase/securite_patch.sql.',
      );
    }
  }

  Future<void> submitVendorApplication({
    required String shopName,
    required String phone,
    String? description,
    String? city,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    await _client.from('vendor_applications').insert({
      'applicant_id': user.id,
      'shop_name': shopName,
      'phone': phone,
      'description': description,
      'city': city,
    });
  }
}
