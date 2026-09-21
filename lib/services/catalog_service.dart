import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_config.dart';
import '../models/models.dart';

/// Lecture du catalogue — boutiques, catégories, produits — toujours
/// paginée et ne demandant que les colonnes nécessaires.
class CatalogService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Shop>> fetchShops({int page = 0, String? search}) async {
    var query = _client.from('shops').select().eq('is_visible', true);
    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }
    final rows = await query
        .order('created_at', ascending: false)
        .range(page * AppConfig.pageSize, page * AppConfig.pageSize + AppConfig.pageSize - 1);
    return rows.map((r) => Shop.fromMap(r)).toList();
  }

  Future<Shop?> fetchShop(String shopId) async {
    final row =
        await _client.from('shops').select().eq('id', shopId).maybeSingle();
    return row == null ? null : Shop.fromMap(row);
  }

  /// Catégories visibles, à plat (plus de sous-catégories depuis le 29 août
  /// 2026 — seules les catégories racines, `parent_id is null`, sont
  /// prises en compte côté client).
  ///
  /// [gender] : 'women' ou 'men' pour l'onglet Femme/Homme de l'accueil
  /// (13 septembre 2026, captures Level d'Emina) — une catégorie marquée
  /// '*' (les deux, voir `Category.gender`) apparaît dans les deux onglets.
  /// `null` (comportement d'avant cette date) renvoie tout, sans filtre.
  /// Statistiques d'inclusion, agrégées — voir
  /// `supabase/inclusion_patch.sql`.
  ///
  /// Passe par une fonction `security definer` qui ne renvoie que des
  /// COMPTES : on ne peut pas savoir, depuis l'application, ce qu'une
  /// boutique donnée a déclaré.
  ///
  /// Renvoie `null` si le patch n'a pas encore été joué — l'accueil
  /// masque alors la section au lieu d'afficher des zéros.
  Future<Map<String, int>?> fetchInclusionStats() async {
    try {
      final rows = await _client.rpc('inclusion_stats');
      final list = rows as List;
      if (list.isEmpty) return null;
      final row = list.first as Map<String, dynamic>;
      return {
        'total': (row['total_shops'] as num?)?.toInt() ?? 0,
        'women': (row['women_led_shops'] as num?)?.toInt() ?? 0,
        'declared': (row['declared_shops'] as num?)?.toInt() ?? 0,
        'cities': (row['cities'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<Category>> fetchCategories({String? gender}) async {
    var query = _client
        .from('categories')
        .select()
        .eq('is_visible', true)
        .filter('parent_id', 'is', null);
    if (gender != null) {
      query = query.or('gender.eq.$gender,gender.eq.*');
    }
    final rows = await query.order('sort_order');
    return rows.map((r) => Category.fromMap(r)).toList();
  }

  Future<List<Category>> fetchAllCategories() async {
    final rows = await _client.from('categories').select().eq('is_visible', true).order('sort_order');
    return rows.map((r) => Category.fromMap(r)).toList();
  }

  static const String _productSelect =
      'id, shop_id, category_id, name, description, price, compare_at_price, stock, is_visible, '
      'created_at, option_name, option_values, option_type, option_colors, option_sold_out, brand, '
      'product_images(url, sort_order, focal_x, focal_y, zoom), shops(id, name, logo_url, is_visible)';

  /// [sort] : 'newest' (défaut), 'price_asc' ou 'price_desc' — utilisé par
  /// le bouton "Trier" de l'écran "Tous les produits".
  Future<List<Product>> fetchProducts({
    int page = 0,
    String? shopId,
    String? categoryId,
    String? search,
    double? minPrice,
    double? maxPrice,
    String sort = 'newest',
  }) async {
    var query = _client.from('products').select(_productSelect).eq('is_visible', true);
    if (shopId != null) query = query.eq('shop_id', shopId);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (search != null && search.isNotEmpty) query = query.ilike('name', '%$search%');
    if (minPrice != null) query = query.gte('price', minPrice);
    if (maxPrice != null) query = query.lte('price', maxPrice);
    final ordered = switch (sort) {
      'price_asc' => query.order('price', ascending: true),
      'price_desc' => query.order('price', ascending: false),
      _ => query.order('created_at', ascending: false),
    };
    final rows = await ordered.range(page * AppConfig.pageSize, page * AppConfig.pageSize + AppConfig.pageSize - 1);
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<Product?> fetchProduct(String productId) async {
    final row = await _client
        .from('products')
        .select(_productSelect)
        .eq('id', productId)
        .maybeSingle();
    return row == null ? null : Product.fromMap(row);
  }

  Future<List<Review>> fetchReviews(String productId) async {
    final rows = await _client
        .from('reviews')
        .select('id, product_id, client_id, rating, comment, created_at, review_authors(full_name)')
        .eq('product_id', productId)
        .eq('is_visible', true)
        .order('created_at', ascending: false);
    return rows.map((r) => Review.fromMap(r)).toList();
  }

  /// Une commande du compte connecté qui contient ce produit et n'a pas
  /// encore reçu d'avis — 15 septembre 2026, demande explicite : "un
  /// client qui a déjà passé commande [peut] laisser un commentaire".
  /// `null` si le compte n'a jamais acheté ce produit (ou si sa/ses
  /// commande(s) l'ayant contenu ont déjà chacune un avis) : c'est ce qui
  /// décide si "Write a review" s'affiche sur la fiche produit.
  Future<String?> fetchReviewableOrderId(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final purchased = await _client
        .from('order_items')
        .select('order_id, orders!inner(client_id)')
        .eq('product_id', productId)
        .eq('orders.client_id', userId);
    if (purchased.isEmpty) return null;
    final orderIds = purchased.map((r) => r['order_id'] as String).toSet();
    final reviewed = await _client
        .from('reviews')
        .select('order_id')
        .eq('product_id', productId)
        .eq('client_id', userId);
    final reviewedIds = reviewed.map((r) => r['order_id'] as String?).whereType<String>().toSet();
    final remaining = orderIds.difference(reviewedIds);
    return remaining.isEmpty ? null : remaining.first;
  }

  /// Dépose un avis — la base refuse l'écriture si `orderId` ne correspond
  /// pas à une commande du compte connecté contenant vraiment ce produit
  /// (voir `supabase/reviews_patch_purchase_required.sql`) : cette
  /// vérification ne dépend donc jamais uniquement de ce que l'app envoie.
  Future<void> createReview({
    required String productId,
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('reviews').insert({
      'product_id': productId,
      'client_id': userId,
      'order_id': orderId,
      'rating': rating,
      'comment': (comment == null || comment.trim().isEmpty) ? null : comment.trim(),
    });
  }

  /// Avis de TOUS les produits d'une boutique, façon onglet "Posts"
  /// d'Oskelly, mais avec du vrai contenu l'app (4 septembre 2026, nuit —
  /// Emina : "tout doit être dans mon application à 100%" ; "Posts" n'a pas
  /// d'équivalent direct, les avis clients en sont le plus proche). Prend
  /// directement la liste des identifiants produits (déjà chargée par
  /// l'appelant, voir shop_detail_screen.dart) plutôt qu'une jointure
  /// `reviews -> products` filtrée sur `shop_id` : après le bug de
  /// jointure trouvé plus tôt ce soir (voir admin_service.dart,
  /// `fetchAllShops`), deux requêtes simples restent le choix le plus sûr.
  Future<List<Review>> fetchShopReviews(List<String> productIds) async {
    if (productIds.isEmpty) return [];
    final rows = await _client
        .from('reviews')
        .select('id, product_id, client_id, rating, comment, created_at, review_authors(full_name)')
        .inFilter('product_id', productIds)
        .eq('is_visible', true)
        .order('created_at', ascending: false);
    return rows.map((r) => Review.fromMap(r)).toList();
  }

  Future<void> submitReview({
    required String productId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('reviews').insert({
      'product_id': productId,
      'client_id': userId,
      'rating': rating,
      'comment': comment,
    });
  }

  Future<void> toggleFavoriteProduct(String productId, bool isFavorite) async {
    final userId = _client.auth.currentUser!.id;
    if (isFavorite) {
      await _client.from('favorite_products').insert({'user_id': userId, 'product_id': productId});
    } else {
      await _client
          .from('favorite_products')
          .delete()
          .eq('user_id', userId)
          .eq('product_id', productId);
    }
  }

  Future<Set<String>> fetchFavoriteProductIds() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    final rows = await _client.from('favorite_products').select('product_id').eq('user_id', userId);
    return rows.map((r) => r['product_id'] as String).toSet();
  }

  // ------------------------------------------------------------------ Suivre une boutique
  //
  // Ajouté le 4 septembre 2026 — façon Oskelly ("Followers" sur le profil
  // boutique, capture envoyée par Emina). La table `favorite_shops` et sa
  // politique RLS (`favorite_shops_all_own`) existent depuis le schéma
  // d'origine ; rien dans l'application ne les utilisait jusqu'ici.

  Future<void> toggleFollowShop(String shopId, bool isFollowing) async {
    final userId = _client.auth.currentUser!.id;
    if (isFollowing) {
      await _client.from('favorite_shops').insert({'user_id': userId, 'shop_id': shopId});
    } else {
      await _client.from('favorite_shops').delete().eq('user_id', userId).eq('shop_id', shopId);
    }
  }

  Future<bool> isFollowingShop(String shopId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from('favorite_shops')
        .select('shop_id')
        .eq('user_id', userId)
        .eq('shop_id', shopId)
        .maybeSingle();
    return row != null;
  }

  /// Nombre total d'abonnés d'une boutique — lecture publique (les lignes
  /// de `favorite_shops` ne sont, elles, lisibles que par leur propriétaire,
  /// donc ce compte passe par une fonction `security definer` plutôt qu'une
  /// lecture directe de la table).
  Future<int> fetchShopFollowerCount(String shopId) async {
    final count = await _client.rpc('shop_follower_count', params: {'target_shop_id': shopId});
    return (count as num?)?.toInt() ?? 0;
  }

  /// Photos de bannière, gérées par l'admin (jusqu'à 5 par emplacement) —
  /// lecture publique (visiteur non connecté inclus). Sans [categoryId] :
  /// bannière de l'accueil (comme avant le 4 septembre). Avec [categoryId] :
  /// bannière propre à cette catégorie (nouveau le 4 septembre, nuit — ex.
  /// une bannière "Aquazzura" affichée seulement en haut de "Chaussures").
  /// Liste vide si l'admin n'a rien ajouté pour cet emplacement : l'écran
  /// Accueil retombe alors sur la photo livrée avec l'application, et une
  /// catégorie sans bannière n'affiche simplement rien à cet endroit.
  Future<List<HomeBanner>> fetchActiveBanners({String? categoryId}) async {
    var query = _client.from('home_banners').select().eq('is_visible', true);
    if (categoryId == null) {
      query = query.filter('category_id', 'is', null);
    } else {
      query = query.eq('category_id', categoryId);
    }
    final rows = await query.order('sort_order');
    return rows.map((r) => HomeBanner.fromMap(r)).toList();
  }

  /// Produits en promotion (prix barré renseigné) — utilisé par la liste
  /// "Réductions" de l'accueil. Filtré une seconde fois côté client par
  /// [Product.isOnSale] car le prix barré peut être ≤ au prix normal.
  Future<List<Product>> fetchDiscountedProducts({int limit = 12}) async {
    final rows = await _client
        .from('products')
        .select(_productSelect)
        .eq('is_visible', true)
        .not('compare_at_price', 'is', null)
        .order('created_at', ascending: false)
        .limit(limit * 2); // marge pour le filtre client (prix barré pas toujours > prix)
    return rows.map((r) => Product.fromMap(r)).where((p) => p.isOnSale).take(limit).toList();
  }

  /// Réglages généraux (numéro de contact, lien du site) — lecture publique.
  Future<AppSettings> fetchAppSettings() async {
    final row = await _client.from('app_settings').select().eq('id', 1).maybeSingle();
    return row == null ? AppSettings() : AppSettings.fromMap(row);
  }

  /// Nombre de produits visibles d'une boutique — utilisé sur la page
  /// profil boutique (façon Oskelly "preloved" : stat "N produits").
  Future<int> fetchShopProductCount(String shopId) async {
    final rows = await _client
        .from('products')
        .select('id')
        .eq('shop_id', shopId)
        .eq('is_visible', true);
    return rows.length;
  }

  Future<void> recordShopVisit(String shopId) async {
    try {
      await _client.rpc('record_shop_visit', params: {'target_shop_id': shopId});
    } catch (_) {
      // Le comptage de visite ne doit jamais bloquer l'affichage.
    }
  }

  // ----------------------------------------------------- Collections d'accueil
  //
  // Ajoutées le 5 septembre 2026 (nuit) — remplacent l'ancienne rangée de
  // produits sans titre juste sous la bannière principale (voir
  // home_screen.dart) : chaque collection est sa propre petite bannière
  // (photo + titre + description) suivie des produits qu'elle annonce.
  // Gérées entièrement par l'admin (voir CollectionsAdminScreen).

  Future<List<HomeCollection>> fetchHomeCollections() async {
    final rows = await _client
        .from('home_collections')
        .select()
        .eq('is_visible', true)
        .order('sort_order');
    return rows.map((r) => HomeCollection.fromMap(r)).toList();
  }

  /// Produits d'une collection — [categoryId] `null` = tous mélangés,
  /// renseigné = seulement cette catégorie. Requête directe avec [limit]
  /// (pas [fetchProducts], pensé pour la pagination par pages de
  /// `AppConfig.pageSize` plutôt qu'un nombre choisi au cas par cas par
  /// l'admin).
  Future<List<Product>> fetchCollectionProducts({String? categoryId, required int limit}) async {
    var query = _client.from('products').select(_productSelect).eq('is_visible', true);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map((r) => Product.fromMap(r)).toList();
  }
}
