import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/catalog_service.dart';
import '../product/product_screen.dart';
import '../widgets.dart';

/// Page profil boutique — refaite le 4 septembre 2026 (nuit) pour suivre à
/// 100% la disposition ET les fonctionnalités de la capture Oskelly
/// ("preloved") envoyée par Emina, après qu'un essai précédent (3-4
/// septembre) s'en soit trop éloigné (avatar centré au lieu d'aligné à
/// gauche à côté des stats, boutons "Wishlist"/"Favorite brands" absents,
/// pas d'onglets, pas de filtres). Chaque élément de la capture a un
/// équivalent réel ici — rien n'est un bouton qui ne mène nulle part :
///
/// - avatar + stats (produits/abonnés) : alignés à gauche, comme "22137
///   items / 183 Followers" — pas de 3e statistique "Following" : un
///   client ne "suit" rien d'autre qu'une boutique dans l'app, une fausse
///   statistique à 0 aurait été pire que son absence.
/// - "Resale Store • 3 years 3 months with OSKELLY" -> ligne "Boutique •
///   depuis X" calculée depuis la date de création réelle de la boutique.
/// - "Wishlist" -> "Mes favoris ici" : filtre la grille sur les produits
///   de CETTE boutique déjà mis en favori.
/// - "Favorite brands" : l'app n'a pas de marques, seulement des boutiques
///   — remplacé par "Localiser", qui ouvre la ville de la boutique dans
///   une carte (vrai usage : savoir où se trouve la vendeuse).
/// - bouton "Follow" noir : bouton Suivre existant (table
///   `favorite_shops`), repositionné au bon endroit.
/// - icône de partage (flèche, en haut à droite) -> copie un message de
///   partage dans le presse-papiers.
/// - onglets "Items"/"Posts" -> "Produits"/"Avis" : l'app n'a pas de fil de
///   publications, mais a de vrais avis clients (table `reviews`) — le
///   contenu le plus proche de "Posts" pour une boutique.
/// - rangée de filtres -> chips de catégories présentes chez cette
///   boutique (masquée si un seul type de produit).
class ShopDetailScreen extends StatefulWidget {
  final String shopId;

  const ShopDetailScreen({super.key, required this.shopId});

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

enum _ShopTab { products, reviews }

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  final _catalog = CatalogService();
  late Future<_ShopData> _future;
  final Set<String> _favoriteIds = {};
  bool _isFollowing = false;
  bool _followLoading = false;
  int? _followerCount;
  _ShopTab _activeTab = _ShopTab.products;
  String? _categoryFilter;
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _catalog.recordShopVisit(widget.shopId);
    _catalog.fetchFavoriteProductIds().then((ids) {
      if (mounted) setState(() => _favoriteIds.addAll(ids));
    });
    _catalog.isFollowingShop(widget.shopId).then((v) {
      if (mounted) setState(() => _isFollowing = v);
    });
    _catalog.fetchShopFollowerCount(widget.shopId).then((v) {
      if (mounted) setState(() => _followerCount = v);
    });
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    final next = !_isFollowing;
    setState(() {
      _isFollowing = next;
      _followerCount = (_followerCount ?? 0) + (next ? 1 : -1);
      _followLoading = true;
    });
    try {
      await _catalog.toggleFollowShop(widget.shopId, next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFollowing = !next;
        _followerCount = (_followerCount ?? 0) + (next ? -1 : 1);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<_ShopData> _load() async {
    final shop = await _catalog.fetchShop(widget.shopId);
    if (shop == null) {
      return _ShopData(shop: null, products: const [], productCount: 0, reviews: const [], categories: const []);
    }
    final products = await _catalog.fetchProducts(shopId: widget.shopId);
    final count = await _catalog.fetchShopProductCount(widget.shopId);
    final reviews = await _catalog.fetchShopReviews(products.map((p) => p.id).toList());

    // Catégories réellement utilisées par cette boutique (pas toutes les
    // catégories de l'app) — pour les chips de filtre sous l'onglet
    // "Produits", façon rangée de filtres Oskelly.
    final allCategories = await _catalog.fetchCategories();
    final nameById = {for (final c in allCategories) c.id: c.name};
    final seen = <String>{};
    final categories = <_CategoryOption>[];
    for (final p in products) {
      final cid = p.categoryId;
      if (cid == null || seen.contains(cid)) continue;
      seen.add(cid);
      categories.add(_CategoryOption(id: cid, name: nameById[cid] ?? '?'));
    }

    return _ShopData(shop: shop, products: products, productCount: count, reviews: reviews, categories: categories);
  }

  Future<void> _toggleFavorite(Product product) async {
    final isFav = _favoriteIds.contains(product.id);
    setState(() {
      if (isFav) {
        _favoriteIds.remove(product.id);
      } else {
        _favoriteIds.add(product.id);
      }
    });
    await _catalog.toggleFavoriteProduct(product.id, !isFav);
  }

  Future<void> _openCityMap(String city) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(city)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Même formulation que le bloc vendeur de la fiche produit — calcul
  // partagé dans widgets.dart depuis le 5 septembre 2026 (voir
  // [shopTenureLabel]), pour que les deux écrans ne puissent pas diverger.
  String _tenureLabel(DateTime createdAt) => 'Resale Store • ${shopTenureLabel(createdAt)} with us';

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FutureBuilder<_ShopData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null || data.shop == null) {
            return Scaffold(
              backgroundColor: AppTheme.bg,
              appBar: AppBar(),
              body: EmptyState(icon: Icons.storefront_outlined, title: t('no_results')),
            );
          }
          final shop = data.shop!;
          final isOwner = context.watch<AuthService>().currentUser?.id == shop.ownerId;

          var products = data.products;
          if (_categoryFilter != null) {
            products = products.where((p) => p.categoryId == _categoryFilter).toList();
          }
          if (_favoritesOnly) {
            products = products.where((p) => _favoriteIds.contains(p.id)).toList();
          }

          return CustomScrollView(
            // Voir home_screen.dart (10 septembre 2026, révisé le 13) :
            // petite marge plutôt que zéro, contre les photos noires lors
            // d'un aller-retour de défilement.
            cacheExtent: 800,
            slivers: [
              SliverAppBar(
                backgroundColor: AppTheme.bg,
                surfaceTintColor: AppTheme.bg,
                pinned: true,
                // Titre centré entre la flèche retour et l'icône de
                // partage — disposition de la capture Oskelly (6 septembre
                // 2026). Sans `centerTitle`, Material l'aligne à gauche.
                centerTitle: true,
                title: Text(shop.name, style: const TextStyle(color: AppTheme.ink, fontSize: 16, fontWeight: FontWeight.w700)),
                iconTheme: const IconThemeData(color: AppTheme.ink),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Avatar + stats côte à côte, alignés à gauche — comme
                      // sur la capture Oskelly (avatar à gauche, stats à
                      // droite), pas centrés l'un sous l'autre.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ShopAvatar(name: shop.name, logoUrl: shop.logoUrl, size: 72),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _ShopStat(value: '${data.productCount}', label: data.productCount > 1 ? 'items' : 'item'),
                                _ShopStat(
                                  value: '${_followerCount ?? ''}',
                                  label: (_followerCount ?? 0) > 1 ? t('shop_followers') : t('shop_follower'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (shop.createdAt != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _tenureLabel(shop.createdAt!),
                                style: const TextStyle(fontSize: 13, color: AppTheme.ink2, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      if (shop.city != null && shop.city!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.muted),
                            const SizedBox(width: 3),
                            Text(shop.city!, style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
                          ],
                        ),
                      ],
                      if (shop.description != null && shop.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(shop.description!, style: const TextStyle(fontSize: 13.5, color: AppTheme.ink2, height: 1.4)),
                      ],
                      const SizedBox(height: 18),
                      // "Wishlist" / "Favorite brands" — texte identique à la
                      // capture Oskelly (demande d'Emina, 14 septembre 2026 :
                      // "tous les boutons" doivent correspondre exactement).
                      // Fonction inchangée derrière ces libellés : "Wishlist"
                      // filtre sur les favoris DE cette boutique, "Favorite
                      // brands" ouvre la ville de la boutique sur la carte —
                      // l'app n'a ni marques ni notion distincte de "produits
                      // favoris vs marques favorites", donc ce sont les deux
                      // fonctions déjà existantes les plus proches.
                      Row(
                        children: [
                          Expanded(
                            child: _PillButton(
                              label: 'Wishlist',
                              active: _favoritesOnly,
                              onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PillButton(
                              label: 'Favorite brands',
                              enabled: shop.city != null && shop.city!.isNotEmpty,
                              onTap: () => _openCityMap(shop.city!),
                            ),
                          ),
                        ],
                      ),
                      if (!isOwner) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: _isFollowing
                              ? OutlinedButton(
                                  onPressed: _toggleFollow,
                                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.line)),
                                  child: Text(t('shop_following'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                                )
                              : FilledButton(
                                  onPressed: _toggleFollow,
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.ink),
                                  child: Text(t('shop_follow'), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                        ),
                      ],
                      // Bouton WhatsApp retiré d'ici le 15 septembre 2026 —
                      // absent de la capture Oskelly de référence, et déjà
                      // disponible ailleurs sur la fiche produit ("Write to
                      // the seller", voir product_screen.dart), donc rien
                      // n'est perdu pour la cliente.
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _ShopTabBar(
                  active: _activeTab,
                  reviewCount: data.reviews.length,
                  onSelect: (tab) => setState(() => _activeTab = tab),
                ),
              ),
              if (_activeTab == _ShopTab.products && data.categories.length > 1)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
                        _CategoryChip(label: 'All', selected: _categoryFilter == null, onTap: () => setState(() => _categoryFilter = null)),
                        for (final c in data.categories) ...[
                          const SizedBox(width: 8),
                          _CategoryChip(label: c.name, selected: _categoryFilter == c.id, onTap: () => setState(() => _categoryFilter = c.id)),
                        ],
                      ],
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Divider(height: 1, color: AppTheme.line),
                ),
              ),
              if (_activeTab == _ShopTab.products)
                SliverPadding(
                  // Agrandi le 15 septembre 2026 — voir all_products_screen.dart.
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                  sliver: products.isEmpty
                      ? SliverToBoxAdapter(child: EmptyState(icon: Icons.inventory_2_outlined, title: t('no_results')))
                      : SliverGrid(
                          // Format calculé, plus fixé à la main : voir
                          // [productGridAspectRatio] (6 septembre 2026 — le
                          // nom des produits était coupé sur cette page).
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                            childAspectRatio: productGridAspectRatio(
                              (MediaQuery.of(context).size.width - 2) / 2,
                              // Oublié le 14 septembre 2026 en activant
                              // `showSellerHeader` ci-dessous : la grille
                              // gardait la hauteur de carte SANS l'en-tête
                              // vendeur, donc chaque carte débordait sur la
                              // rangée suivante — c'est ça, et pas un vrai
                              // problème de mise en page, qui donnait
                              // l'impression que le prix d'une carte et l'en-
                              // tête de la suivante étaient "mélangés".
                              withSellerHeader: true,
                            ),
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final product = products[i];
                              return ProductCard(
                                key: ValueKey(product.id),
                                product: product,
                                showShopName: false,
                                // En-tête vendeur (photo + nom) au-dessus de
                                // chaque photo — demande d'Emina du 14
                                // septembre 2026 : la page boutique doit
                                // correspondre "exactement" à la capture
                                // Oskelly, qui répète le nom de la boutique
                                // sur chacun de ses propres produits.
                                showSellerHeader: true,
                                isFavorite: _favoriteIds.contains(product.id),
                                onToggleFavorite: () => _toggleFavorite(product),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)),
                                ),
                              );
                            },
                            childCount: products.length,
                          ),
                        ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: data.reviews.isEmpty
                      ? SliverToBoxAdapter(child: EmptyState(icon: Icons.rate_review_outlined, title: t('no_results')))
                      : SliverList.separated(
                          itemCount: data.reviews.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final review = data.reviews[i];
                            final productName = data.products.firstWhere(
                              (p) => p.id == review.productId,
                              orElse: () => Product(id: '', shopId: '', name: '', price: 0),
                            ).name;
                            return _ReviewCard(review: review, productName: productName);
                          },
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ShopData {
  final Shop? shop;
  final List<Product> products;
  final int productCount;
  final List<Review> reviews;
  final List<_CategoryOption> categories;

  _ShopData({
    required this.shop,
    required this.products,
    required this.productCount,
    required this.reviews,
    required this.categories,
  });
}

class _CategoryOption {
  final String id;
  final String name;

  _CategoryOption({required this.id, required this.name});
}

/// Un chiffre + son libellé, façon Oskelly ("22137 items", "183
/// Followers").
class _ShopStat extends StatelessWidget {
  final String value;
  final String label;

  const _ShopStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Valeur en gras au-dessus, libellé en dessous à la même taille et
        // en NOIR (pas en gris) — mesuré sur la capture Oskelly du
        // 6 septembre 2026 : "6 / items", les deux à ~15.
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
        Text(label, style: const TextStyle(fontSize: 13.5, color: AppTheme.ink)),
      ],
    );
  }
}

/// Bouton pilule gris clair, façon "Wishlist" / "Favorite brands" sur la
/// capture Oskelly — [active] le teinte quand le filtre qu'il représente
/// est actuellement appliqué (ex. "Mes favoris ici").
class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  const _PillButton({required this.label, required this.onTap, this.active = false, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppTheme.ink : AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : AppTheme.ink),
          ),
        ),
      ),
    );
  }
}

/// Onglets "Produits" / "Avis" — équivalent honnête de "Items"/"Posts"
/// (voir doc de la classe principale). Fait à la main (deux boutons +
/// soulignement) plutôt qu'avec un `TabBar`/`TabController` : seulement
/// deux onglets fixes, pas besoin de cette machinerie ici.
class _ShopTabBar extends StatelessWidget {
  final _ShopTab active;
  final int reviewCount;
  final ValueChanged<_ShopTab> onSelect;

  const _ShopTabBar({required this.active, required this.reviewCount, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _ShopTabItem(label: 'Items', selected: active == _ShopTab.products, onTap: () => onSelect(_ShopTab.products)),
          const SizedBox(width: 24),
          _ShopTabItem(label: 'Reviews ($reviewCount)', selected: active == _ShopTab.reviews, onTap: () => onSelect(_ShopTab.reviews)),
        ],
      ),
    );
  }
}

class _ShopTabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ShopTabItem({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.ink : AppTheme.muted,
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 2, width: 26, color: selected ? AppTheme.ink : Colors.transparent),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.ink : AppTheme.panel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppTheme.ink2),
        ),
      ),
    );
  }
}

/// Une carte d'avis dans l'onglet "Avis" — auteur, note en étoiles,
/// commentaire, et sur quel produit (utile ici car les avis viennent de
/// plusieurs produits différents, contrairement à la fiche produit où
/// c'est évident).
class _ReviewCard extends StatelessWidget {
  final Review review;
  final String productName;

  const _ReviewCard({required this.review, required this.productName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.authorName ?? 'Customer',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink),
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 15,
                    color: const Color(0xFFE0A34D),
                  ),
                ),
              ),
            ],
          ),
          if (productName.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('On "$productName"', style: const TextStyle(fontSize: 11.5, color: AppTheme.muted)),
          ],
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment!, style: const TextStyle(fontSize: 13, color: AppTheme.ink2, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
