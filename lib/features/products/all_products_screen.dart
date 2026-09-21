import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/cart_controller.dart';
import '../../services/catalog_service.dart';
import '../product/product_screen.dart';
import '../widgets.dart';

/// Écran "Tous les produits" — reprend le fichier HTML fourni par Emina le
/// 29 août 2026 (grille 2 colonnes sombre, "Filtres" + "Trier", puce de
/// catégorie active amovible). Remplace l'ancien écran de catégorie/
/// sous-catégorie : accessible depuis "Explorer" et "Tout voir" sur
/// l'accueil, avec ou sans catégorie de départ.
///
/// Bannière de catégorie ajoutée le 4 septembre 2026 (nuit) : quand une
/// catégorie est sélectionnée, une bannière propre à CETTE catégorie
/// (gérée par l'admin, voir [BannersAdminScreen]) peut s'afficher en haut
/// de la grille — captures d'Emina, façon Level : une bannière "Aquazzura"
/// visible seulement dans la section Chaussures. Rien ne s'affiche si
/// l'admin n'a pas encore ajouté de bannière pour cette catégorie.
class AllProductsScreen extends StatefulWidget {
  final String? categoryId;
  final String? categoryName;
  final String? search;

  const AllProductsScreen({super.key, this.categoryId, this.categoryName, this.search});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  final _catalog = CatalogService();
  String? _categoryId;
  String? _categoryName;
  String _sort = 'newest';
  double? _minPrice;
  double? _maxPrice;
  final Set<String> _favoriteIds = {};
  late Future<List<Product>> _future;
  Future<List<HomeBanner>>? _bannerFuture;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _categoryName = widget.categoryName;
    _future = _load();
    _bannerFuture = _loadBanner();
    _catalog.fetchFavoriteProductIds().then((ids) {
      if (mounted) setState(() => _favoriteIds.addAll(ids));
    });
  }

  Future<List<Product>> _load() {
    return _catalog.fetchProducts(
      categoryId: _categoryId,
      search: widget.search,
      sort: _sort,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
    );
  }

  // Bannière propre à la catégorie affichée, s'il y en a une (4 septembre
  // 2026, nuit) — pas de bannière hors contexte catégorie (recherche,
  // "Tous les produits" sans filtre).
  Future<List<HomeBanner>>? _loadBanner() {
    if (_categoryId == null) return null;
    return _catalog.fetchActiveBanners(categoryId: _categoryId);
  }

  void _refresh() => setState(() => _future = _load());

  void _clearCategory() {
    setState(() {
      _categoryId = null;
      _categoryName = null;
      _bannerFuture = _loadBanner();
    });
    _refresh();
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

  Future<void> _openSort() async {
    final t = context.read<SettingsController>().t;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            _SortTile(label: t('sort_newest'), value: 'newest', groupValue: _sort),
            _SortTile(label: t('sort_price_asc'), value: 'price_asc', groupValue: _sort),
            _SortTile(label: t('sort_price_desc'), value: 'price_desc', groupValue: _sort),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    // Les _SortTile renvoient leur valeur via Navigator.pop directement.
    if (chosen != null && chosen != _sort) {
      setState(() => _sort = chosen);
      _refresh();
    }
  }

  Future<void> _openFilters() async {
    final t = context.read<SettingsController>().t;
    final minCtrl = TextEditingController(text: _minPrice?.toStringAsFixed(0) ?? '');
    final maxCtrl = TextEditingController(text: _maxPrice?.toStringAsFixed(0) ?? '');
    final result = await showModalBottomSheet<Map<String, double?>>(
      context: context,
      backgroundColor: AppTheme.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('price_range'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t('min')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t('max')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop({'min': null, 'max': null}),
                    child: Text(t('reset')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop({
                      'min': double.tryParse(minCtrl.text.trim()),
                      'max': double.tryParse(maxCtrl.text.trim()),
                    }),
                    child: Text(t('apply')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _minPrice = result['min'];
        _maxPrice = result['max'];
      });
      _refresh();
    }
  }

  // Sélecteur de catégorie — ajouté le 4 septembre 2026 (nuit) : depuis que
  // la grille de catégories a été retirée de l'accueil (à la demande
  // d'Emina, remplacée par des produits), plus aucun bouton de l'app ne
  // permettait de choisir une catégorie précise. Ce bouton "Catégorie"
  // dans la barre d'outils (à côté de Filtres/Trier) reprend ce rôle, pour
  // que parcourir par catégorie reste possible.
  Future<void> _openCategoryPicker() async {
    final categories = await _catalog.fetchCategories();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Category>(
      context: context,
      backgroundColor: AppTheme.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            for (final c in categories)
              ListTile(
                title: Text(c.name, style: TextStyle(color: AppTheme.ink, fontWeight: c.id == _categoryId ? FontWeight.w700 : FontWeight.w400)),
                trailing: c.id == _categoryId ? const Icon(Icons.check, color: AppTheme.ink) : null,
                onTap: () => Navigator.of(context).pop(c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      _categoryId = chosen.id;
      _categoryName = chosen.name;
      _bannerFuture = _loadBanner();
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final activeFilters = (_minPrice != null || _maxPrice != null) ? 1 : 0;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.search ?? t('all_products'),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w400, color: AppTheme.ink),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _ToolButton(
                      label: t('filter'),
                      icon: Icons.tune,
                      badge: activeFilters,
                      onTap: _openFilters,
                    ),
                    const SizedBox(width: 8),
                    _ToolButton(label: t('sort'), icon: Icons.swap_vert, onTap: _openSort),
                    const SizedBox(width: 8),
                    if (_categoryName != null)
                      _ToolButton(label: _categoryName!, selected: true, onTap: _openCategoryPicker, onClose: _clearCategory)
                    else
                      _ToolButton(label: t('category'), icon: Icons.category_outlined, onTap: _openCategoryPicker),
                  ],
                ),
              ),
            ),
            if (_bannerFuture != null)
              FutureBuilder<List<HomeBanner>>(
                future: _bannerFuture,
                builder: (context, snapshot) {
                  final urls = (snapshot.data ?? []).map((b) => b.imageUrl).toList();
                  if (urls.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: _CategoryBanner(imageUrls: urls),
                  );
                },
              ),
            const SizedBox(height: 10),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _refresh();
                  await _future;
                },
                child: FutureBuilder<List<Product>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final products = snapshot.data ?? [];
                    if (products.isEmpty) {
                      return ListView(children: [
                        const SizedBox(height: 100),
                        EmptyState(icon: Icons.inventory_2_outlined, title: t('no_results')),
                      ]);
                    }
                    return GridView.builder(
              // Voir home_screen.dart (10 septembre 2026, révisé le 13) :
              // petite marge plutôt que zéro, contre les photos noires lors
              // d'un aller-retour de défilement.
              cacheExtent: 800,
                      // Agrandi le 15 septembre 2026 : mesuré sur la
                      // capture de référence, les cartes touchent les
                      // deux bords de l'écran, séparées seulement par un
                      // fin filet de 2 pt — plus de marge de 16 pt de
                      // chaque côté, qui rétrécissait les photos.
                      // 16 px avant le premier produit (15 septembre
                      // 2026, "tous les produits doivent commencer après
                      // 16 px d'espace").
                      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                      // Format calculé plutôt que fixé — voir
                      // [productGridAspectRatio] (6 septembre 2026).
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        childAspectRatio: productGridAspectRatio((MediaQuery.of(context).size.width - 2) / 2),
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, i) {
                        final product = products[i];

                        return ProductCard(
                          key: ValueKey(product.id),
                          product: product,
                          isFavorite: _favoriteIds.contains(product.id),
                          onToggleFavorite: () => _toggleFavorite(product),
                          onAdd: () => context.read<CartController>().add(product),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;

  const _SortTile({required this.label, required this.value, required this.groupValue});

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return ListTile(
      onTap: () => Navigator.of(context).pop(value),
      title: Text(label, style: TextStyle(color: AppTheme.ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      trailing: selected ? const Icon(Icons.check, color: AppTheme.ink) : null,
    );
  }
}

/// Bouton d'outil de la barre "Filtres / Trier / puce catégorie" — reprend
/// le style `.tool` / `.tool.on` du fichier HTML fourni (fond transparent,
/// devient blanc quand sélectionné).
class _ToolButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final int badge;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const _ToolButton({
    required this.label,
    this.icon,
    this.badge = 0,
    this.selected = false,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.ink : Colors.transparent;
    final fg = selected ? Colors.white : AppTheme.ink2;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap ?? onClose,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: AppTheme.line)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: fg)),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  height: 16,
                  decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(20)),
                  alignment: Alignment.center,
                  child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                ),
              ],
              if (onClose != null) ...[
                const SizedBox(width: 6),
                // Zone de tap indépendante du reste du bouton — sinon,
                // quand `onTap` ET `onClose` sont fournis en même temps
                // (puce de catégorie active, 4 septembre 2026 nuit : appuyer
                // sur le nom rouvre le choix, appuyer sur la croix efface),
                // tout le bouton n'aurait déclenché que `onTap`.
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 13, color: fg.withValues(alpha: 0.7)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bannière d'une catégorie précise — ajoutée le 4 septembre 2026 (nuit),
/// gérée par l'admin (voir [BannersAdminScreen]). Bande plus modeste que
/// la grande bannière de l'accueil (celle-ci s'insère dans une liste de
/// produits, pas en pleine page) mais même principe de défilement
/// automatique si l'admin en a ajouté plusieurs pour cette catégorie.
class _CategoryBanner extends StatefulWidget {
  final List<String> imageUrls;

  const _CategoryBanner({required this.imageUrls});

  @override
  State<_CategoryBanner> createState() => _CategoryBannerState();
}

class _CategoryBannerState extends State<_CategoryBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.imageUrls.length >= 2) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_page + 1) % widget.imageUrls.length;
        _controller.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: AspectRatio(
        aspectRatio: 1.9,
        child: urls.length > 1
            ? PageView.builder(
                controller: _controller,
                itemCount: urls.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => AppImage(url: urls[i], fit: BoxFit.cover),
              )
            : AppImage(url: urls.first, fit: BoxFit.cover),
      ),
    );
  }
}
