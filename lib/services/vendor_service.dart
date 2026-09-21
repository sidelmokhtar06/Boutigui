import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Espace vendeur en libre-service — créer sa propre boutique et gérer ses
/// propres produits DEPUIS L'APPLICATION CLIENTE, sans passer par le site
/// admin. Ajouté le 4 septembre 2026 (Emina : "n'importe qui peut créer
/// une boutique comme un profil, comme un compte Instagram... mais la
/// boutique est cachée tant que l'administrateur n'a pas accepté").
///
/// Rien à ajouter côté base de données : les policies RLS le permettent
/// déjà (`shops_insert_own` : owner_id = soi-même ; `products_insert_owner`
/// : `owns_shop(shop_id)` — voir marketplace_schema.sql) et la colonne
/// `shops.is_visible` a pour valeur par défaut `false` : une boutique
/// créée ici est donc invisible pour tout le monde sauf son propriétaire
/// et l'admin, jusqu'à ce que l'admin la rende visible (site admin >
/// Boutiques > interrupteur).
class VendorService {
  final SupabaseClient _client = Supabase.instance.client;

  static const String _productSelect =
      'id, shop_id, category_id, name, description, price, compare_at_price, stock, is_visible, '
      'created_at, option_name, option_values, option_type, option_colors, option_sold_out, brand, '
      'product_images(url, sort_order, focal_x, focal_y, zoom), shops(id, name, logo_url, is_visible)';

  /// La boutique de l'utilisateur connecté, s'il en a déjà créé une (une
  /// seule par personne, gérée côté application — pas de contrainte en
  /// base, mais l'écran ne propose plus "créer" une fois qu'on en a une).
  Future<Shop?> fetchMyShop() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client.from('shops').select().eq('owner_id', userId).maybeSingle();
    return row == null ? null : Shop.fromMap(row);
  }

  Future<Shop> createMyShop({
    required String name,
    String? description,
    String? logoUrl,
    String? city,
    String? whatsappPhone,
    // Code marchand de la banque mobile — 6 septembre 2026. Obligatoire
    // côté formulaire : sans lui, aucune cliente ne peut payer cette
    // boutique.
    String? merchantCode,
    String? merchantProvider,
    bool? womenLed,
    // Point de collecte pour l'espace Livreur (15 septembre 2026) —
    // facultatif : sans lui, les courses de cette boutique restent
    // proposées aux livreuses, simplement sans distance calculée tant
    // qu'il n'est pas renseigné (voir "Ma boutique" > position).
    double? lat,
    double? lng,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('shops')
        .insert({
          'owner_id': userId,
          'name': name,
          'description': description,
          'logo_url': logoUrl,
          'city': city,
          'whatsapp_phone': whatsappPhone,
          'merchant_code': merchantCode,
          'merchant_provider': merchantProvider,
          'women_led': womenLed,
          'lat': lat,
          'lng': lng,
        })
        .select()
        .single();
    return Shop.fromMap(row);
  }

  Future<void> updateMyShop({
    required String shopId,
    String? name,
    String? description,
    String? logoUrl,
    String? city,
    String? whatsappPhone,
    String? merchantCode,
    String? merchantProvider,
    bool? womenLed,
    double? lat,
    double? lng,
  }) async {
    await _client.from('shops').update({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (city != null) 'city': city,
      if (whatsappPhone != null) 'whatsapp_phone': whatsappPhone,
      if (merchantCode != null) 'merchant_code': merchantCode,
      if (merchantProvider != null) 'merchant_provider': merchantProvider,
      // Envoyé même à `null` : c'est une réponse qu'on peut retirer.
      'women_led': womenLed,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    }).eq('id', shopId);
  }

  /// Ajouté le 4 septembre 2026 : jusque-là, seul l'admin pouvait supprimer
  /// une boutique (`shops_delete_admin`) — la vendeuse elle-même n'avait
  /// aucun moyen de supprimer la sienne, ni côté écran ni côté base. Le
  /// correctif RLS (`shops_delete_owner_or_admin`, voir admin_patch.sql)
  /// doit être exécuté pour que cet appel fonctionne. Les produits et
  /// commandes de la boutique sont supprimés automatiquement avec elle
  /// (`on delete cascade` sur `shop_id`, déjà dans le schéma d'origine).
  /// Catégories dans lesquelles la boutique travaille — choisies à
  /// l'inscription vendeuse (6 septembre 2026, Emina : "des questions sur
  /// quelle catégorie il va travailler, il peut choisir plusieurs
  /// réponses"). Table de liaison `shop_categories`, remplacée en entier à
  /// chaque enregistrement : c'est plus simple et plus sûr que de calculer
  /// les ajouts et les retraits.
  Future<void> setMyShopCategories({required String shopId, required List<String> categoryIds}) async {
    await _client.from('shop_categories').delete().eq('shop_id', shopId);
    if (categoryIds.isEmpty) return;
    await _client.from('shop_categories').insert([
      for (final id in categoryIds) {'shop_id': shopId, 'category_id': id},
    ]);
  }

  Future<List<Category>> fetchMyShopCategories(String shopId) async {
    final rows = await _client.from('shop_categories').select('categories(*)').eq('shop_id', shopId);
    return rows
        .map((r) => r['categories'] as Map<String, dynamic>?)
        .where((c) => c != null)
        .map((c) => Category.fromMap(c!))
        .toList();
  }

  Future<void> deleteMyShop(String shopId) async {
    await _client.from('shops').delete().eq('id', shopId);
  }

  /// Tous les produits de SA boutique (visibles ET cachés — RLS : le
  /// propriétaire voit toujours tout, via `owns_shop`).
  Future<List<Product>> fetchMyProducts(String shopId) async {
    final rows = await _client
        .from('products')
        .select(_productSelect)
        .eq('shop_id', shopId)
        .order('created_at', ascending: false);
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<String> createMyProduct({
    required String shopId,
    String? categoryId,
    required String name,
    String? description,
    required double price,
    double? compareAtPrice,
    int stock = 0,
    // Options (taille, couleur, ...) — 5 septembre 2026, voir models.dart
    // (Product.optionName / optionValues).
    String? optionName,
    List<String> optionValues = const [],
    // Couleurs / choix épuisés — 6 septembre 2026, voir
    // Product.optionType / optionColors / optionSoldOut.
    String optionType = 'text',
    List<String> optionColors = const [],
    List<bool> optionSoldOut = const [],
    // Marque — 5 septembre 2026 (nuit), voir Product.brand/brandLine.
    String? brand,
  }) async {
    final row = await _client
        .from('products')
        .insert({
          'shop_id': shopId,
          'category_id': categoryId,
          'name': name,
          'description': description,
          'price': price,
          'compare_at_price': compareAtPrice,
          'stock': stock,
          'option_name': optionName,
          'option_values': optionValues,
          'option_type': optionType,
          'option_colors': optionColors,
          'option_sold_out': optionSoldOut,
          'brand': brand,
        })
        .select()
        .single();
    return row['id'] as String;
  }

  Future<void> updateMyProduct({
    required String id,
    String? name,
    String? description,
    double? price,
    double? compareAtPrice,
    bool clearCompareAtPrice = false,
    int? stock,
    // `null` = ne pas toucher ; `''`/liste vide = effacer les options.
    String? optionName,
    bool clearOptionName = false,
    List<String>? optionValues,
    String? optionType,
    List<String>? optionColors,
    List<bool>? optionSoldOut,
    // `null` = ne pas toucher ; `''` = effacer la marque.
    String? brand,
  }) async {
    await _client.from('products').update({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (price != null) 'price': price,
      if (compareAtPrice != null) 'compare_at_price': compareAtPrice,
      if (clearCompareAtPrice) 'compare_at_price': null,
      if (stock != null) 'stock': stock,
      if (optionName != null) 'option_name': optionName,
      if (clearOptionName) 'option_name': null,
      if (optionValues != null) 'option_values': optionValues,
      if (optionType != null) 'option_type': optionType,
      if (optionColors != null) 'option_colors': optionColors,
      if (optionSoldOut != null) 'option_sold_out': optionSoldOut,
      if (brand != null) 'brand': brand.isEmpty ? null : brand,
    }).eq('id', id);
  }

  // ------------------------------------------------------------- Photos produit
  //
  // Ajoutées le 5 septembre 2026 (nuit) — Emina : "le vendeur il peut
  // contrôler la photo, c'est à dire ce que le vendeur il veut apparaître
  // pour le client" : jusque-là, une vendeuse pouvait AJOUTER des photos
  // mais jamais les réorganiser, en supprimer une précise, ni choisir
  // laquelle sert de couverture (la première photo ajoutée l'était de
  // façon arbitraire côté base, voir models.dart `Product.fromMap`).

  Future<List<ProductImage>> fetchMyProductImages(String productId) async {
    final rows = await _client
        .from('product_images')
        .select('id, url, sort_order, focal_x, focal_y, zoom')
        .eq('product_id', productId)
        .order('sort_order');
    return rows.map((r) => ProductImage.fromMap(r)).toList();
  }

  Future<void> deleteMyProductImage(String imageId) async {
    await _client.from('product_images').delete().eq('id', imageId);
  }

  /// Change le point de la photo à toujours garder visible, et son zoom —
  /// voir la doc de `Product.imageFocalX`/`imageFocalY`/`imageZoom` (5
  /// septembre 2026). [focalX]/[focalY] sont des fractions de 0 à 1,
  /// [zoom] va de 1.0 (pas de zoom) à 3.0.
  Future<void> updateMyProductImageFocal({
    required String imageId,
    required double focalX,
    required double focalY,
    required double zoom,
  }) async {
    await _client.from('product_images').update({'focal_x': focalX, 'focal_y': focalY, 'zoom': zoom}).eq('id', imageId);
  }

  /// Enregistre le nouvel ordre voulu par la vendeuse — [orderedImageIds]
  /// dans l'ordre d'affichage voulu, la première devenant la photo de
  /// couverture (`Product.coverImage`).
  Future<void> reorderMyProductImages(List<String> orderedImageIds) async {
    for (var i = 0; i < orderedImageIds.length; i++) {
      await _client.from('product_images').update({'sort_order': i}).eq('id', orderedImageIds[i]);
    }
  }

  Future<void> setMyProductVisible(String id, bool visible) async {
    await _client.from('products').update({'is_visible': visible}).eq('id', id);
  }

  Future<void> deleteMyProduct(String id) async {
    await _client.from('products').delete().eq('id', id);
  }

  Future<void> addMyProductImage({
    required String productId,
    required String url,
    int sortOrder = 0,
    double focalX = 0.5,
    double focalY = 0.5,
    double zoom = 1.0,
  }) async {
    await _client.from('product_images').insert({
      'product_id': productId,
      'url': url,
      'sort_order': sortOrder,
      'focal_x': focalX,
      'focal_y': focalY,
      'zoom': zoom,
    });
  }

  // ------------------------------------------------------------------ Commandes
  //
  // Ajoutées le 4 septembre 2026, en même temps que côté admin
  // (`AdminService`) : jusqu'ici, une vendeuse en libre-service n'avait
  // AUCUN moyen de voir ses commandes ni de vérifier une capture de
  // paiement — RLS l'y autorisait déjà (`owns_shop`), mais rien dans
  // l'application ne l'exposait.

  Future<List<OrderModel>> fetchMyShopOrders(String shopId) async {
    final rows = await _client
        .from('orders')
        .select('*, shops(name)')
        .eq('shop_id', shopId)
        .order('created_at', ascending: false);
    return rows.map((r) => OrderModel.fromMap(r)).toList();
  }

  Future<List<OrderItemModel>> fetchOrderItems(String orderId) async {
    final rows = await _client.from('order_items').select().eq('order_id', orderId);
    return rows.map((r) => OrderItemModel.fromMap(r)).toList();
  }

  Future<void> updateOrderStatus(String id, String status) async {
    await _client.from('orders').update({
      'status': status,
      if (status == 'confirmed') 'confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Vérification du paiement par la vendeuse (20 septembre 2026).
  ///
  /// C'est elle qui retrouve — ou non — la référence de transaction dans
  /// l'historique de son application bancaire. L'app ne vérifie rien
  /// toute seule : aucun fournisseur mauritanien n'expose d'API de
  /// vérification aujourd'hui, et afficher « paiement vérifié » sans
  /// vérification serait un mensonge affiché à la cliente.
  ///
  /// `payment_verified_at` est posé par la base
  /// (`payment_verified_at_stamp`), pas ici : un horodatage donné par le
  /// client n'aurait aucune valeur.
  ///
  /// [status] : 'verified' ou 'rejected'. Le `.select()` rend visible un
  /// refus de RLS — sans lui, Postgres ne modifierait aucune ligne et
  /// signalerait quand même un succès (voir `supabase/AGENTS.md`).
  ///
  /// [amountReceived] : montant relevé dans l'application bancaire au
  /// moment de la vérification (21 septembre 2026). Il n'est enregistré
  /// qu'avec un statut « verified » — un paiement rejeté n'a pas de
  /// montant reçu, et la base efface d'ailleurs la valeur d'elle-même si
  /// le statut redescend.
  Future<void> setPaymentStatus(
    String orderId,
    String status, {
    double? amountReceived,
  }) async {
    assert(status == 'verified' || status == 'rejected' || status == 'submitted');
    final updated = await _client
        .from('orders')
        .update({
          'payment_status': status,
          if (status == 'verified') 'payment_amount_received': amountReceived,
        })
        .eq('id', orderId)
        .select('id');
    if (updated.isEmpty) {
      throw Exception(
        "Le statut du paiement n'a pas pu être enregistré (la base a "
        'refusé la modification). Correctif : jouer '
        'supabase/fintech_patch.sql.',
      );
    }
  }
}
