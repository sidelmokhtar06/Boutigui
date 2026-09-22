import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Toutes les opérations réservées à l'administrateur : catégories,
/// boutiques, produits, candidatures vendeur. Chaque appel s'appuie sur les
/// politiques RLS `is_admin()` déjà en place (voir marketplace_schema.sql +
/// supabase/admin_patch.sql) — si le compte connecté n'est pas admin,
/// Supabase refuse l'opération côté serveur, quoi que fasse ce code.
/// Boutique + nom/email du propriétaire (jointure `profiles`) — utilisé
/// uniquement côté admin, le client mobile n'a pas besoin de cette info.
class AdminShopRow {
  final Shop shop;
  final String? ownerName;
  final String? ownerEmail;

  AdminShopRow({required this.shop, this.ownerName, this.ownerEmail});

  factory AdminShopRow.fromMap(Map<String, dynamic> map) {
    final owner = map['profiles'] as Map<String, dynamic>?;
    return AdminShopRow(
      shop: Shop.fromMap(map),
      ownerName: owner != null ? owner['full_name'] as String? : null,
      ownerEmail: owner != null ? owner['email'] as String? : null,
    );
  }
}

class AdminService {
  final SupabaseClient _client = Supabase.instance.client;

  // ---------------------------------------------------------------- Catégories
  //
  // Depuis le 29 août 2026, plus de sous-catégories (décision d'Emina) :
  // toutes les catégories sont au même niveau (`parent_id` toujours null
  // pour les nouvelles). En contrepartie, chaque catégorie peut avoir une
  // photo (`image_url`), ce qui manquait avant.

  Future<List<Category>> fetchCategories() async {
    final rows = await _client.from('categories').select().order('sort_order');
    return rows.map((r) => Category.fromMap(r)).toList();
  }

  /// Ajoutée le 4 septembre 2026, en même temps que le classement (voir
  /// [swapCategoryOrder]) : jusqu'ici, `sort_order` valait toujours 0 pour
  /// toutes les catégories, donc leur ordre à l'affichage était en réalité
  /// arbitraire (l'ordre renvoyé par la base, non contrôlable) — chaque
  /// nouvelle catégorie se met maintenant à la fin de la liste.
  Future<void> createCategory({
    required String name,
    String? imageUrl,
    double focalX = 0.5,
    double focalY = 0.5,
    double zoom = 1.0,
    // 'women', 'men' ou '*' (les deux, défaut) — voir Category.gender,
    // 13 septembre 2026.
    String gender = '*',
  }) async {
    final current = await fetchCategories();
    final nextOrder = current.isEmpty ? 0 : current.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _client.from('categories').insert({
      'name': name,
      'parent_id': null,
      'image_url': imageUrl,
      'sort_order': nextOrder,
      'focal_x': focalX,
      'focal_y': focalY,
      'zoom': zoom,
      'gender': gender,
    });
  }

  /// Change à quel onglet (Femme / Homme / les deux) une catégorie
  /// appartient — 13 septembre 2026.
  Future<void> setCategoryGender(String id, String gender) async {
    await _client.from('categories').update({'gender': gender}).eq('id', id);
  }

  /// Échange l'ordre d'affichage de deux catégories (boutons Monter/Descendre
  /// sur l'écran admin) — même principe que [swapBannerOrder].
  Future<void> swapCategoryOrder(Category a, Category b) async {
    await _client.from('categories').update({'sort_order': b.sortOrder}).eq('id', a.id);
    await _client.from('categories').update({'sort_order': a.sortOrder}).eq('id', b.id);
  }

  Future<void> renameCategory(String id, String name) async {
    await _client.from('categories').update({'name': name}).eq('id', id);
  }

  /// [focalX]/[focalY]/[zoom] : point à garder visible + zoom, choisis sur
  /// [PhotoPositionScreen] (widgets.dart) juste avant l'envoi de CETTE
  /// nouvelle photo — remis à 0.5/0.5/1.0 (centre, pas de zoom) puisqu'une
  /// nouvelle photo n'a plus de raison de garder le cadrage de l'ancienne.
  Future<void> setCategoryImage(String id, String imageUrl, {double focalX = 0.5, double focalY = 0.5, double zoom = 1.0}) async {
    await _client.from('categories').update({
      'image_url': imageUrl,
      'focal_x': focalX,
      'focal_y': focalY,
      'zoom': zoom,
    }).eq('id', id);
  }

  /// Recadre/zoome la photo DÉJÀ en ligne, sans en changer l'URL — ajoutée
  /// le 5 septembre 2026 (Emina : "l'admin il peut contrôler le photo, soit
  /// couper une partie ou faire un zoom") : permet de rouvrir
  /// [PhotoPositionScreen] sur la photo actuelle d'une catégorie à tout
  /// moment, pas seulement au moment où on la met en ligne.
  Future<void> updateCategoryImagePosition({
    required String id,
    required double focalX,
    required double focalY,
    required double zoom,
  }) async {
    await _client.from('categories').update({'focal_x': focalX, 'focal_y': focalY, 'zoom': zoom}).eq('id', id);
  }

  Future<void> setCategoryVisible(String id, bool visible) async {
    await _client.from('categories').update({'is_visible': visible}).eq('id', id);
  }

  /// Conservé pour l'écran produit (menu déroulant "Catégorie") — équivaut
  /// maintenant simplement à [fetchCategories] puisqu'il n'y a plus qu'un
  /// niveau, mais on garde le nom pour ne pas devoir toucher les écrans qui
  /// l'appellent déjà.
  Future<List<Category>> fetchAllCategoriesFlat() => fetchCategories();

  Future<void> deleteCategory(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }

  // ------------------------------------------------------------------ Boutiques

  /// Boutiques cachées (en attente de validation) d'abord — depuis le
  /// passage des boutiques en libre-service (4 septembre 2026), c'est la
  /// vraie file d'attente de l'admin : une boutique fraîchement créée par
  /// une vendeuse est toujours cachée par défaut tant que ce n'est pas
  /// traité ici.
  ///
  /// Corrigé le 4 septembre 2026 (nuit) : la version précédente faisait UNE
  /// requête avec une jointure `profiles(full_name, email)` directement
  /// dans le `select`. Chez Emina, cette requête échouait (probablement la
  /// jointure elle-même, ou son interaction avec le double `.order()`), et
  /// comme l'écran n'affichait pas les erreurs (voir shops_admin_screen.dart),
  /// l'échec silencieux ressemblait à "aucune boutique" alors que le
  /// tableau de bord — qui fait une requête toute simple sans jointure —
  /// comptait bien 2 boutiques. Pour ne plus dépendre de cette jointure,
  /// on fait maintenant deux requêtes simples (boutiques, puis profils des
  /// propriétaires) et on les assemble ici en Dart.
  Future<List<AdminShopRow>> fetchAllShops() async {
    final shopRows = await _client
        .from('shops')
        .select()
        .order('is_visible', ascending: true)
        .order('created_at', ascending: false);
    final shops = shopRows.map((r) => Shop.fromMap(r)).toList();
    if (shops.isEmpty) return [];

    final ownerIds = shops.map((s) => s.ownerId).toSet().toList();
    final profileRows = await _client.from('profiles').select('id, full_name, email').inFilter('id', ownerIds);
    final profileById = {for (final p in profileRows) p['id'] as String: p};

    return shops.map((s) {
      final owner = profileById[s.ownerId];
      return AdminShopRow(
        shop: s,
        ownerName: owner != null ? owner['full_name'] as String? : null,
        ownerEmail: owner != null ? owner['email'] as String? : null,
      );
    }).toList();
  }

  Future<void> setShopVisible(String id, bool visible) async {
    await _client.from('shops').update({'is_visible': visible}).eq('id', id);
  }

  Future<void> deleteShop(String id) async {
    await _client.from('shops').delete().eq('id', id);
  }

  Future<void> createShop({
    required String ownerId,
    required String name,
    String? city,
    String? whatsappPhone,
    String? description,
    bool isVisible = true,
  }) async {
    await _client.from('shops').insert({
      'owner_id': ownerId,
      'name': name,
      'city': city,
      'whatsapp_phone': whatsappPhone,
      'description': description,
      'is_visible': isVisible,
    });
  }

  /// Profils utilisables comme propriétaire d'une nouvelle boutique.
  Future<List<Profile>> fetchProfiles({String? search}) async {
    var query = _client.from('profiles').select();
    // `or()` prend une CHAÎNE de filtres PostgREST, pas une valeur
    // paramétrée : tout ce qu'on y interpole est lu comme de la syntaxe.
    // Une recherche contenant une virgule ou une parenthèse — « Brahim,
    // Jr » — cassait donc le filtre et faisait échouer la requête, et la
    // forme générale laissait écrire n'importe quel filtre PostgREST.
    // Nettoyé le 21 septembre 2026 (audit). Les autres recherches du
    // projet passent par `ilike()`, qui paramètre correctement sa valeur.
    final cleaned = _sanitizeOrFilterValue(search);
    if (cleaned.isNotEmpty) {
      query = query.or('full_name.ilike.%$cleaned%,email.ilike.%$cleaned%');
    }
    final rows = await query.order('created_at', ascending: false).limit(50);
    return rows.map((r) => Profile.fromMap(r)).toList();
  }

  // ------------------------------------------------------------------- Produits

  static const String _productSelect =
      'id, shop_id, category_id, name, description, price, compare_at_price, stock, is_visible, '
      'brand, product_images(url, sort_order, focal_x, focal_y, zoom), shops(id, name, logo_url, is_visible)';

  Future<List<Product>> fetchAllProducts({String? shopId, String? search}) async {
    var query = _client.from('products').select(_productSelect);
    if (shopId != null) query = query.eq('shop_id', shopId);
    if (search != null && search.isNotEmpty) query = query.ilike('name', '%$search%');
    final rows = await query.order('created_at', ascending: false).limit(200);
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<String> createProduct({
    required String shopId,
    String? categoryId,
    required String name,
    String? description,
    required double price,
    double? compareAtPrice,
    int stock = 0,
    bool isVisible = true,
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
          'is_visible': isVisible,
          'brand': brand,
        })
        .select()
        .single();
    return row['id'] as String;
  }

  /// [clearCompareAtPrice] : true pour effacer explicitement le prix barré
  /// (repasser un produit en promotion à un prix normal) — sinon, comme les
  /// autres champs, `compareAtPrice == null` laisse la valeur inchangée.
  Future<void> updateProduct({
    required String id,
    String? name,
    String? description,
    double? price,
    double? compareAtPrice,
    bool clearCompareAtPrice = false,
    int? stock,
    String? categoryId,
    String? brand,
  }) async {
    await _client.from('products').update({
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (price != null) 'price': price,
      if (compareAtPrice != null) 'compare_at_price': compareAtPrice,
      if (clearCompareAtPrice) 'compare_at_price': null,
      if (stock != null) 'stock': stock,
      if (categoryId != null) 'category_id': categoryId,
      if (brand != null) 'brand': brand.isEmpty ? null : brand,
    }).eq('id', id);
  }

  Future<void> setProductVisible(String id, bool visible) async {
    await _client.from('products').update({'is_visible': visible}).eq('id', id);
  }

  Future<void> deleteProduct(String id) async {
    await _client.from('products').delete().eq('id', id);
  }

  Future<void> addProductImage({required String productId, required String url, int sortOrder = 0}) async {
    await _client.from('product_images').insert({'product_id': productId, 'url': url, 'sort_order': sortOrder});
  }

  // --------------------------------------------------------------- Réglages

  Future<AppSettings> fetchAppSettings() async {
    final row = await _client.from('app_settings').select().eq('id', 1).maybeSingle();
    return row == null ? AppSettings() : AppSettings.fromMap(row);
  }

  Future<void> updateAppSettings({String? contactPhone, String? websiteUrl}) async {
    await _client.from('app_settings').update({
      'contact_phone': contactPhone,
      'website_url': websiteUrl,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', 1);
  }

  // ------------------------------------------------------------ Candidatures vendeur

  Future<List<VendorApplication>> fetchVendorApplications({String? status}) async {
    var query = _client.from('vendor_applications').select('*, profiles(full_name, email)');
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('created_at', ascending: false);
    return rows.map((r) => VendorApplication.fromMap(r)).toList();
  }

  /// Approuve une candidature : crée la boutique (visible immédiatement) pour
  /// le candidat, puis marque la candidature "approved". Deux appels
  /// distincts (pas de fonction serveur dédiée) — c'est expliqué dans le
  /// récapitulatif du projet comme limite connue de cette première version.
  Future<void> approveVendorApplication(VendorApplication application) async {
    await createShop(
      ownerId: application.applicantId,
      name: application.shopName,
      city: application.city,
      whatsappPhone: application.phone,
      description: application.description,
      isVisible: true,
    );
    // Passe le compte du candidat en rôle "vendor" — nécessaire pour que le
    // futur site vendeur (accès conditionné au rôle) le laisse entrer.
    // Autorisé : le déclencheur anti-élévation ne bloque que le changement
    // de SON PROPRE rôle par un utilisateur, pas un admin qui change celui
    // d'un autre compte.
    await _client.from('profiles').update({'role': 'vendor'}).eq('id', application.applicantId);
    await _client.from('vendor_applications').update({
      'status': 'approved',
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', application.id);
  }

  Future<void> rejectVendorApplication(String id) async {
    await _client.from('vendor_applications').update({
      'status': 'rejected',
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  // ------------------------------------------------------------- Bannières
  //
  // Ajoutées le 2 septembre 2026 : jusqu'à 5 photos, affichées en carrousel
  // automatique sur l'écran Accueil. Le plafond de 5 est appliqué ici, côté
  // Dart (pas de contrainte en base) — cohérent avec le reste du projet, qui
  // s'appuie sur les policies RLS pour la sécurité et sur le code pour les
  // règles de présentation.
  //
  // Étendues le 4 septembre 2026 (nuit) : une bannière peut maintenant être
  // rattachée à UNE catégorie (`categoryId`) plutôt qu'à l'accueil — captures
  // d'Emina (Level/Aquazzura) montrant une bannière propre à "Chaussures".
  // Chaque emplacement (accueil, ou une catégorie donnée) a son propre
  // plafond de 5 — [fetchBanners] avec `categoryId: null` (accueil, valeur
  // par défaut) ou une catégorie précise ne renvoie que les bannières de CET
  // emplacement, comme avant pour l'accueil.

  static const int maxBanners = 5;

  /// [categoryId] omis ou `null` → bannières de l'accueil (comportement
  /// historique). Renseigné → bannières propres à cette catégorie.
  Future<List<HomeBanner>> fetchBanners({String? categoryId}) async {
    var query = _client.from('home_banners').select('*, categories(name)');
    if (categoryId == null) {
      query = query.filter('category_id', 'is', null);
    } else {
      query = query.eq('category_id', categoryId);
    }
    final rows = await query.order('sort_order');
    return rows.map((r) => HomeBanner.fromMap(r)).toList();
  }

  Future<void> addBanner(String imageUrl, {String? categoryId}) async {
    final current = await fetchBanners(categoryId: categoryId);
    if (current.length >= maxBanners) {
      throw Exception('Maximum $maxBanners photos pour cet emplacement — supprime-en une avant d\'en ajouter une nouvelle.');
    }
    final nextOrder = current.isEmpty ? 0 : current.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _client.from('home_banners').insert({'image_url': imageUrl, 'sort_order': nextOrder, 'category_id': categoryId});
  }

  Future<void> setBannerVisible(String id, bool visible) async {
    await _client.from('home_banners').update({'is_visible': visible}).eq('id', id);
  }

  Future<void> deleteBanner(String id) async {
    await _client.from('home_banners').delete().eq('id', id);
  }

  /// Échange l'ordre de deux bannières voisines (boutons "monter" / "descendre").
  Future<void> swapBannerOrder(HomeBanner a, HomeBanner b) async {
    await _client.from('home_banners').update({'sort_order': b.sortOrder}).eq('id', a.id);
    await _client.from('home_banners').update({'sort_order': a.sortOrder}).eq('id', b.id);
  }

  // ------------------------------------------------------------------ Commandes
  //
  // Ajoutées le 4 septembre 2026 : jusqu'ici, une commande passée par un
  // client n'était visible NULLE PART côté vendeur ni côté admin — ni écran,
  // ni même la capture de paiement (le bucket privé `payment-proofs`
  // n'autorisait que le déposant à la relire, voir `admin_patch.sql` du même
  // jour). Le circuit "le vendeur vérifie le paiement" décrit dans le
  // récapitulatif du projet n'avait donc aucun moyen d'exister en pratique.

  // -------------------------------------------------- Collections d'accueil
  //
  // Ajoutées le 5 septembre 2026 (nuit), retour d'Emina, capture "Hermès
  // for Less" : remplacent l'ancienne rangée de produits sans titre juste
  // sous la bannière principale — chaque collection est sa propre petite
  // bannière (photo + titre + description) suivie des produits qu'elle
  // annonce (une catégorie précise, ou tous mélangés ; l'admin choisit
  // aussi combien en montrer). Même principe CRUD que les bannières
  // ([fetchBanners]/[addBanner]/...), pas de plafond de nombre ici (rien
  // dans la demande n'en impose un, contrairement aux 5 photos de bannière).

  Future<List<HomeCollection>> fetchCollections() async {
    final rows = await _client.from('home_collections').select('*, categories(name)').order('sort_order');
    return rows.map((r) => HomeCollection.fromMap(r)).toList();
  }

  Future<void> createCollection({
    required String imageUrl,
    required String title,
    String? subtitle,
    String? categoryId,
    int productLimit = 8,
  }) async {
    final current = await fetchCollections();
    final nextOrder = current.isEmpty ? 0 : current.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await _client.from('home_collections').insert({
      'image_url': imageUrl,
      'title': title,
      'subtitle': subtitle,
      'category_id': categoryId,
      'product_limit': productLimit,
      'sort_order': nextOrder,
    });
  }

  Future<void> updateCollection({
    required String id,
    String? imageUrl,
    String? title,
    String? subtitle,
    bool clearSubtitle = false,
    String? categoryId,
    bool clearCategoryId = false,
    int? productLimit,
  }) async {
    await _client.from('home_collections').update({
      if (imageUrl != null) 'image_url': imageUrl,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (clearSubtitle) 'subtitle': null,
      if (categoryId != null) 'category_id': categoryId,
      if (clearCategoryId) 'category_id': null,
      if (productLimit != null) 'product_limit': productLimit,
    }).eq('id', id);
  }

  Future<void> setCollectionVisible(String id, bool visible) async {
    await _client.from('home_collections').update({'is_visible': visible}).eq('id', id);
  }

  Future<void> deleteCollection(String id) async {
    await _client.from('home_collections').delete().eq('id', id);
  }

  Future<void> swapCollectionOrder(HomeCollection a, HomeCollection b) async {
    await _client.from('home_collections').update({'sort_order': b.sortOrder}).eq('id', a.id);
    await _client.from('home_collections').update({'sort_order': a.sortOrder}).eq('id', b.id);
  }

  Future<List<OrderModel>> fetchOrders({String? status}) async {
    var query = _client.from('orders').select('*, shops(name)');
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('created_at', ascending: false).limit(300);
    return rows.map((r) => OrderModel.fromMap(r)).toList();
  }

  Future<List<OrderItemModel>> fetchOrderItems(String orderId) async {
    final rows = await _client.from('order_items').select().eq('order_id', orderId);
    return rows.map((r) => OrderItemModel.fromMap(r)).toList();
  }

  /// Voir la note de `VendorService.updateOrderStatus` : un `update`
  /// refusé par RLS ne lève pas d'erreur, d'où le `.select()`.
  Future<void> updateOrderStatus(String id, String status) async {
    if (!kOrderStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Statut de commande inconnu');
    }
    final updated = await _client.from('orders').update({
      'status': status,
      if (status == 'confirmed') 'confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', id).select('id');
    if (updated.isEmpty) {
      throw Exception(
        "Le statut de la commande n'a pas pu être enregistré (la base a "
        'refusé la modification).',
      );
    }
  }

  /// Retire d'une recherche les caractères qui sont de la SYNTAXE pour
  /// PostgREST dans un `or()` : virgule (séparateur de filtres),
  /// parenthèses (groupement), point (séparateur colonne/opérateur) et les
  /// guillemets. Ce qui reste ne peut plus que servir de texte cherché.
  static String _sanitizeOrFilterValue(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'[,()."\\:]'), ' ').trim();
}
