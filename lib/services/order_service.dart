import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'cart_controller.dart';
import 'storage_service.dart';

/// Résultat d'une validation de panier — voir [OrderService.checkout].
///
/// **Ajouté le 21 septembre 2026 (audit).** Le panier peut contenir
/// plusieurs boutiques, donc plusieurs PAIEMENTS distincts, déjà effectués
/// dans l'application bancaire avant d'arriver ici. Une seule d'entre elles
/// peut échouer (référence déjà utilisée, article épuisé entre-temps). Le
/// code d'avant renvoyait une simple liste d'identifiants et laissait
/// l'exception remonter à la première erreur : les commandes déjà créées
/// existaient bel et bien, mais l'écran affichait un échec sec et la
/// cliente pensait que rien n'était parti. Ce type dit exactement ce qui a
/// abouti et ce qui n'a pas abouti.
class CheckoutOutcome {
  /// Identifiants des commandes réellement créées.
  final List<String> createdOrderIds;

  /// Boutiques dont la commande a échoué : nom de la boutique -> raison
  /// déjà lisible par une humaine.
  final Map<String, String> failedByShop;

  const CheckoutOutcome({required this.createdOrderIds, required this.failedByShop});

  bool get hasFailures => failedByShop.isNotEmpty;
  bool get hasSuccesses => createdOrderIds.isNotEmpty;

  /// Rien n'est passé du tout — l'écran affiche une erreur simple, le
  /// panier est intact.
  bool get isTotalFailure => createdOrderIds.isEmpty;
}

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
  ///
  /// **Refait le 21 septembre 2026 (audit) — une transaction par
  /// boutique.** Cette méthode enchaînait trois appels HTTP par boutique :
  /// `insert into orders`, puis `insert into delivery_requests`, puis
  /// `insert into order_items`. Trois transactions distinctes. Si la
  /// dernière échouait — un article épuisé depuis `correctifs_patch.sql`,
  /// une coupure réseau — la commande restait en base SANS SES LIGNES,
  /// donc avec un total recalculé à zéro, et la vendeuse voyait une
  /// commande vide qu'elle ne pouvait pas honorer.
  ///
  /// Tout passe maintenant par la fonction `create_order`
  /// (`supabase/correctifs_patch.sql`, partie 7), qui fait les trois
  /// insertions dans UNE transaction : ou bien la commande complète
  /// existe, ou bien rien n'existe.
  ///
  /// Et comme chaque boutique correspond à un paiement déjà effectué et
  /// distinct, l'échec de l'une n'annule plus les autres : on continue la
  /// boucle et on renvoie le détail dans [CheckoutOutcome].
  Future<CheckoutOutcome> checkout(
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

    // Nom de chaque boutique — sert uniquement aux messages d'erreur : une
    // cliente doit lire « Chez Fatima » et non un identifiant technique.
    // Une seule requête pour tout le panier, pas une par boutique.
    final shopNames = <String, String>{};
    try {
      final rows = await _client.from('shops').select('id, name').inFilter('id', cart.linesByShop.keys.toList());
      for (final row in rows) {
        shopNames[row['id'] as String] = (row['name'] as String?) ?? '';
      }
    } catch (_) {
      // Sans les noms, les messages parleront de « cette boutique ». La
      // commande elle-même n'en dépend pas.
    }

    final createdOrderIds = <String>[];
    final failedByShop = <String, String>{};

    // `linesByShop` reconstruit une map à chaque lecture : on en prend une
    // copie avant la boucle, puisque `clearShop` modifie le panier au fur
    // et à mesure.
    final byShop = cart.linesByShop;

    for (final entry in byShop.entries) {
      final shopId = entry.key;
      final lines = entry.value;
      final shopLabel = (shopNames[shopId] ?? '').isEmpty ? 'cette boutique' : shopNames[shopId]!;

      try {
        // Ni le prix unitaire ni le total ne sont envoyés : depuis
        // `fintech_patch.sql` la base retarife chaque ligne depuis
        // `products` et recalcule le total. Les envoyer quand même ne
        // servait qu'à entretenir l'illusion qu'ils comptaient.
        final orderId = await _client.rpc('create_order', params: {
          'p_shop_id': shopId,
          'p_payment_reference': paymentReferencesByShop[shopId]!.trim(),
          'p_client_full_name': profileRow['full_name'] ?? '',
          'p_client_phone': cleanPhone,
          'p_client_city': profileRow['city'],
          // L'adresse écrite de la commande prime sur celle du profil :
          // c'est celle de CETTE livraison.
          'p_client_address': cleanAddress.isEmpty ? profileRow['address'] : cleanAddress,
          'p_delivery_lat': deliveryLat,
          'p_delivery_lng': deliveryLng,
          'p_delivery_mode': deliveryMode,
          'p_items': [
            for (final l in lines)
              {
                'product_id': l.product.id,
                // Option choisie (taille, couleur, ...) ajoutée au nom
                // enregistré (5 septembre 2026) : `order_items` garde un
                // nom recopié au moment de l'achat plutôt qu'une colonne
                // dédiée, pas besoin de migration pour que la vendeuse
                // voie le choix de la cliente dans le détail.
                'product_name':
                    l.selectedOption == null ? l.product.name : '${l.product.name} — ${l.selectedOption}',
                'quantity': l.quantity,
              },
          ],
        });

        createdOrderIds.add(orderId as String);
        // Uniquement les boutiques dont la commande est réellement partie :
        // ce qui a échoué reste dans le panier, prêt à être réessayé.
        cart.clearShop(shopId);
      } catch (e) {
        failedByShop[shopLabel] = describeCheckoutError(e);
      }
    }

    if (cleanPhone != ((profileRow['phone'] as String?) ?? '')) {
      // Le téléphone est un confort ; il ne doit pas faire échouer une
      // commande déjà payée.
      try {
        await _client.from('profiles').update({'phone': cleanPhone}).eq('id', user.id);
      } catch (_) {}
    }

    return CheckoutOutcome(createdOrderIds: createdOrderIds, failedByShop: failedByShop);
  }

  /// Traduit une erreur brute de PostgreSQL en une phrase lisible.
  ///
  /// Les deux chaînes cherchées ici sont LOAD BEARING côté base :
  /// `orders_payment_reference_unique` est le nom de l'index unique posé
  /// par `rattrapage_patch.sql`, et `STOCK_INSUFFISANT` le préfixe du
  /// message levé par `order_item_stock_guard`
  /// (`correctifs_patch.sql`, partie 3). Renommer l'un ou l'autre en base
  /// dégrade silencieusement le message affiché ici.
  static String describeCheckoutError(Object error) {
    final raw = error.toString();
    if (raw.contains('STOCK_INSUFFISANT')) {
      return "Un article n'est plus disponible en quantité suffisante. "
          'Ajustez la quantité et réessayez.';
    }
    if (raw.contains('orders_payment_reference_unique') || raw.contains('duplicate key')) {
      return 'Cette référence de paiement a déjà servi pour une autre commande.';
    }
    // Reste une erreur qu'on n'a pas prévue. `PostgrestException.toString()`
    // donne « PostgrestException(message: ..., code: 42501, details: ...) » :
    // on n'en garde que le message, le reste ne veut rien dire pour la
    // personne qui le lit.
    if (error is PostgrestException) return error.message;
    return raw.replaceFirst('Exception: ', '');
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
