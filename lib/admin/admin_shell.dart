import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import 'banners_admin_screen.dart';
import 'categories_admin_screen.dart';
import 'collections_admin_screen.dart';
import 'dashboard_admin_screen.dart';
import 'drivers_admin_screen.dart';
import 'orders_admin_screen.dart';
import 'products_admin_screen.dart';
import 'settings_admin_screen.dart';
import 'shops_admin_screen.dart';

/// Coquille du site admin — barre latérale fixe sur grand écran (ordinateur),
/// tiroir (Drawer) ouvert par une icône ☰ sur petit écran (téléphone),
/// changé le 2 septembre 2026 : jusque-là la barre latérale de 240px restait
/// affichée même sur téléphone, ce qui écrasait le contenu et rendait le
/// site admin très difficile à manipuler sur mobile.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

/// Largeur en-dessous de laquelle on bascule en mise en page mobile
/// (tiroir) plutôt que barre latérale fixe — une tablette en portrait ou un
/// téléphone en paysage tombent aussi dans ce cas, ce qui est voulu.
const double _mobileBreakpoint = 760;

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // "Candidatures vendeurs" retiré de la navigation le 4 septembre 2026 :
  // depuis le passage des boutiques en libre-service (voir
  // vendor/my_shop_screen.dart côté app cliente), plus rien dans
  // l'application ne crée de ligne dans `vendor_applications` — cet écran
  // resterait vide en permanence, ce qui n'est ni utile ni professionnel.
  // La vraie file d'attente d'aujourd'hui, ce sont les boutiques
  // fraîchement créées et encore cachées, déjà visibles dans "Boutiques".
  // Le fichier reste dans le projet (aucun risque à le garder) au cas où
  // Emina voudrait un jour réactiver ce circuit.
  static const _items = [
    (Icons.dashboard_outlined, 'Dashboard'),
    (Icons.grid_view_outlined, 'Categories'),
    (Icons.storefront_outlined, 'Shops'),
    (Icons.receipt_long_outlined, 'Orders'),
    (Icons.inventory_2_outlined, 'Products'),
    (Icons.image_outlined, 'Home banner'),
    // "Collections" ajouté le 5 septembre 2026 (nuit) : bannière secondaire
    // + produits sélectionnés, affichée sur l'accueil sous la grande
    // bannière (remplace l'ancienne rangée de produits sans titre).
    (Icons.auto_awesome_mosaic_outlined, 'Collections'),
    // Espace Livreur (15 septembre 2026) — file d'attente des candidatures
    // livreur à approuver ou rejeter, même principe que les boutiques
    // fraîchement créées.
    (Icons.moped_outlined, 'Drivers'),
    (Icons.settings_outlined, 'Settings'),
  ];

  static const _screens = [
    DashboardAdminScreen(),
    CategoriesAdminScreen(),
    ShopsAdminScreen(),
    OrdersAdminScreen(),
    ProductsAdminScreen(),
    BannersAdminScreen(),
    CollectionsAdminScreen(),
    DriversAdminScreen(),
    SettingsAdminScreen(),
  ];

  void _select(int i) {
    setState(() => _index = i);
    // Sur mobile, choisir une page ferme aussi le tiroir — sinon il faut un
    // second geste pour voir la page choisie.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final narrow = MediaQuery.sizeOf(context).width < _mobileBreakpoint;

    if (narrow) {
      return Scaffold(
        key: _scaffoldKey,
        backgroundColor: AdminTheme.bg,
        appBar: AppBar(
          backgroundColor: AdminTheme.card,
          title: Text(_items[_index].$2, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout, size: 20), onPressed: () => auth.signOut()),
          ],
        ),
        drawer: Drawer(
          backgroundColor: AdminTheme.card,
          child: _SidebarContent(index: _index, onSelect: _select, auth: auth),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // Barre de pastilles qui défile, ajoutée le 6 septembre 2026
              // ("essaie d'améliorer le design de la partie admin pour
              // qu'elle soit organisée dans le téléphone") : changer de
              // page demandait jusque-là d'ouvrir le tiroir, donc deux
              // gestes à chaque fois. Le tiroir reste disponible pour la
              // déconnexion et le nom du compte.
              _MobileNavStrip(index: _index, onSelect: _select),
              Expanded(child: _screens[_index]),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: SafeArea(child: _SidebarContent(index: _index, onSelect: _select, auth: auth)),
          ),
          const VerticalDivider(width: 1, color: AdminTheme.hair),
          Expanded(
            child: SafeArea(child: _screens[_index]),
          ),
        ],
      ),
    );
  }
}

/// Contenu de la navigation — factorisé pour être utilisé à la fois dans la
/// barre latérale fixe (grand écran) et dans le tiroir (petit écran).
class _SidebarContent extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final AuthService auth;

  const _SidebarContent({required this.index, required this.onSelect, required this.auth});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AdminTheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                const Icon(Icons.shopping_basket_rounded, color: AdminTheme.ink, size: 22),
                const SizedBox(width: 7),
                Text('Admin', style: AdminTheme.brand(size: 18)),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          for (var i = 0; i < _AdminShellState._items.length; i++)
            _NavItem(
              icon: _AdminShellState._items[i].$1,
              label: _AdminShellState._items[i].$2,
              selected: i == index,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(radius: 16, backgroundColor: AdminTheme.redTint, child: Icon(Icons.person, size: 16, color: AdminTheme.red)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    auth.profile?.fullName ?? auth.profile?.email ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AdminTheme.ink),
                  ),
                ),
                IconButton(
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout, size: 18),
                  onPressed: () => auth.signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AdminTheme.redTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: selected ? AdminTheme.red : AdminTheme.ink2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AdminTheme.red : AdminTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Navigation horizontale du site admin sur téléphone — une pastille par
/// page, la page courante en surbrillance.
class _MobileNavStrip extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _MobileNavStrip({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: AdminTheme.card,
        border: Border(bottom: BorderSide(color: AdminTheme.hair)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        itemCount: _AdminShellState._items.length,
        itemBuilder: (context, i) {
          final selected = i == index;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: InkWell(
              onTap: () => onSelect(i),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AdminTheme.redTint : AdminTheme.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      _AdminShellState._items[i].$1,
                      size: 15,
                      color: selected ? AdminTheme.red : AdminTheme.ink2,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _AdminShellState._items[i].$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? AdminTheme.red : AdminTheme.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
