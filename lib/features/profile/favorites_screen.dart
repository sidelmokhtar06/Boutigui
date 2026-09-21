import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/settings_controller.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../product/product_screen.dart';
import '../widgets.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _client = Supabase.instance.client;
  final _catalog = CatalogService();
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Product>> _load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final ids = await _catalog.fetchFavoriteProductIds();
    if (ids.isEmpty) return [];
    final products = <Product>[];
    for (final id in ids) {
      final product = await _catalog.fetchProduct(id);
      if (product != null) products.add(product);
    }
    return products;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Scaffold(
      appBar: AppBar(title: Text(t('favorites'))),
      body: FutureBuilder<List<Product>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return EmptyState(icon: CupertinoIcons.bookmark, title: t('no_results'));
          }
          return GridView.builder(
              // Voir home_screen.dart (10 septembre 2026, révisé le 13) :
              // petite marge plutôt que zéro, contre les photos noires lors
              // d'un aller-retour de défilement.
              cacheExtent: 800,
            // Agrandi le 15 septembre 2026 — voir all_products_screen.dart.
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
                isFavorite: true,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)))
                    .then((_) => setState(() => _future = _load())),
              );
            },
          );
        },
      ),
    );
  }
}
