import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import 'admin_widgets.dart';

class DashboardAdminScreen extends StatefulWidget {
  const DashboardAdminScreen({super.key});

  @override
  State<DashboardAdminScreen> createState() => _DashboardAdminScreenState();
}

class _DashboardAdminScreenState extends State<DashboardAdminScreen> {
  final _client = Supabase.instance.client;
  late Future<_Counts> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Counts> _load() async {
    final shops = await _client.from('shops').select('id, is_visible');
    final products = await _client.from('products').select('id');
    final categories = await _client.from('categories').select('id');
    final pendingOrders = await _client.from('orders').select('id').eq('status', 'pending');
    final visibleShops = shops.where((s) => s['is_visible'] == true).length;
    return _Counts(
      shops: shops.length,
      visibleShops: visibleShops,
      products: products.length,
      categories: categories.length,
      pendingOrders: pendingOrders.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminPageHeader(title: 'Dashboard', subtitle: 'Overview'),
        Expanded(
          child: FutureBuilder<_Counts>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final c = snapshot.data!;
              // Sur téléphone, les cartes faisaient 220 de large quoi qu'il
              // arrive : une seule tenait par ligne, avec un grand vide à
              // droite. Elles se partagent maintenant la largeur en deux
              // (6 septembre 2026, "que le site admin soit organisé dans le
              // téléphone").
              final narrow = isNarrowAdmin(context);
              final pad = narrow ? 16.0 : 28.0;
              final cardWidth = narrow
                  ? (MediaQuery.sizeOf(context).width - pad * 2 - 12) / 2
                  : 220.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                child: Wrap(
                  spacing: narrow ? 12 : 16,
                  runSpacing: narrow ? 12 : 16,
                  children: [
                    _StatCard(
                      width: cardWidth,
                      label: 'Shops',
                      value: '${c.shops}',
                      sub: '${c.shops - c.visibleShops} pending approval',
                      icon: Icons.storefront_outlined,
                      highlight: (c.shops - c.visibleShops) > 0,
                    ),
                    _StatCard(width: cardWidth, label: 'Products', value: '${c.products}', icon: Icons.inventory_2_outlined),
                    _StatCard(width: cardWidth, label: 'Categories', value: '${c.categories}', icon: Icons.grid_view_outlined),
                    _StatCard(
                      width: cardWidth,
                      label: 'Pending orders',
                      value: '${c.pendingOrders}',
                      icon: Icons.receipt_long_outlined,
                      highlight: c.pendingOrders > 0,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Counts {
  final int shops;
  final int visibleShops;
  final int products;
  final int categories;
  final int pendingOrders;

  _Counts({
    required this.shops,
    required this.visibleShops,
    required this.products,
    required this.categories,
    required this.pendingOrders,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final bool highlight;
  final double width;

  const _StatCard({
    required this.label,
    required this.value,
    this.sub,
    required this.icon,
    this.highlight = false,
    this.width = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AdminCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: highlight ? AdminTheme.red : AdminTheme.ink2, size: 22),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AdminTheme.ink)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 13, color: AdminTheme.muted)),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub!, style: const TextStyle(fontSize: 11.5, color: AdminTheme.muted)),
            ],
          ],
        ),
      ),
    );
  }
}
