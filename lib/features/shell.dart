import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../core/settings_controller.dart';
import '../core/theme.dart';
import '../services/cart_controller.dart';
import 'cart/cart_screen.dart';
import 'categories/categories_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import '../services/role_controller.dart';
import 'vendor/vendor_categories_screen.dart';

/// Coquille de navigation. Depuis le 4 septembre 2026, un 5e bouton
/// "Créer" (rond + cerclé, façon Instagram/Vinted) a rejoint la barre, au
/// centre : il n'a pas d'écran à lui — il lance le parcours de vente en
/// libre-service (choix de catégorie -> connexion si besoin -> "Ma
/// boutique", voir [_startSell]) plutôt que de changer d'onglet.
///
/// Réorganisé le 5 septembre 2026 (demande explicite d'Emina) : un nouvel
/// onglet "Catégories" prend la place qu'occupait Panier, Panier prend la
/// place qu'occupait Favoris, et Favoris disparaît du menu du bas — l'ordre
/// est donc maintenant Accueil / Catégories / Créer / Panier / Compte.
/// L'écran Favoris lui-même n'a pas été supprimé (le coeur en haut de
/// l'accueil y mène toujours, voir home_screen.dart, `_openFavorites`) :
/// seul le bouton dédié du menu du bas a été retiré, comme demandé
/// ("supprime le menu favoris"). Les 4 vrais onglets restent gérés par un
/// IndexedStack, qui préserve leur état.
class Shell extends StatefulWidget {
  Shell({Key? key}) : super(key: key ?? navKey);

  /// Clé globale (15 septembre 2026) — permet à un écran poussé au-dessus
  /// du [Shell] (ex. la fiche produit, après "Add to Bag") de revenir dessus
  /// ET de changer d'onglet en un seul geste, via [ShellState.goToBag] :
  /// `Navigator.of(context).popUntil((r) => r.isFirst)` ramène au [Shell]
  /// déjà existant (son état, dont l'onglet actif, est conservé), puis
  /// `Shell.navKey.currentState?.goToBag()` bascule sur l'onglet Bag.
  static final GlobalKey<ShellState> navKey = GlobalKey<ShellState>();

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int _index = 0;

  /// Bascule vers l'onglet Bag (index 2) — voir [Shell.navKey].
  void goToBag() => setState(() => _index = 2);

  static const _screens = [
    HomeScreen(),
    CategoriesScreen(),
    CartScreen(),
    ProfileScreen(),
  ];

  /// Parcours "Créer" (demande d'Emina, 4 septembre 2026 ; écran de
  /// connexion vendeuse dédié précisé le même jour, en soirée) : on choisit
  /// d'abord la catégorie de l'article à vendre, puis — seulement si la
  /// personne n'a pas ENCORE de boutique — un écran de connexion/inscription
  /// dédié à la vendeuse ([VendorGateScreen]), même si elle est déjà
  /// connectée en tant que cliente (dans ce cas, une confirmation explicite
  /// est demandée plutôt qu'un saut direct). Une fois qu'une boutique existe
  /// déjà, "Créer" ne repasse plus par cet écran : on va directement ajouter
  /// un produit à sa boutique.
  ///
  /// Limite honnête à connaître : côté web, "Continuer avec Google"
  /// recharge toute la page (redirection complète vers Google puis retour)
  /// — dans ce cas précis, la catégorie choisie ici est perdue au retour et
  /// la personne atterrit simplement connectée sur l'accueil ; il lui
  /// suffit de rappuyer sur "Créer" une fois connectée. Avec la connexion
  /// par e-mail (pas de rechargement de page), l'enchaînement complet
  /// fonctionne sans interruption.
  /// **6 septembre 2026** : ce bouton ne mène plus directement au parcours
  /// vendeuse, mais à un choix entre "vendre" et "livrer"
  /// ([JoinChoiceScreen]) — demande d'Emina. Chaque parcours enchaîne
  /// ensuite sur ses propres questions puis sur l'écran de connexion
  /// dédié.
  /// **Corrigé le 6 septembre 2026, après retour d'Emina** : « ce bouton
  /// c'est seulement pour quelqu'un qui va s'inscrire, il ne gère pas les
  /// commandes ». Le tour précédent en avait fait un raccourci vers "Ma
  /// boutique" quand on avait déjà une boutique — c'était une erreur, et
  /// ça avait un effet de bord : une vendeuse ne pouvait plus atteindre
  /// l'inscription, puisque le bouton l'envoyait droit à sa boutique.
  ///
  /// Ce bouton est donc, et reste, **l'entrée d'inscription vendeuse**. La
  /// GESTION (boutique, produits, commandes) vit dans l'écran Compte, sous
  /// "Espace vendeuse".
  ///
  /// L'étape intermédiaire "vendeuse ou livreur" a disparu le 6 septembre
  /// 2026, en même temps que la partie livreur : il n'y a plus qu'un seul
  /// parcours, on va donc directement au choix des catégories.
  Future<void> _startSell(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VendorCategoriesScreen()),
    );
    // Le rôle a pu changer pendant la visite (création de boutique) : on
    // le relit pour que l'écran Compte suive.
    if (mounted) await context.read<RoleController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final cartCount = context.watch<CartController>().itemCount;

    final tabs = [
      _TabSpec(_TabKind.home, t('tab_home'), active: _index == 0),
      _TabSpec(_TabKind.categories, t('tab_categories'), active: _index == 1),
      _TabSpec(_TabKind.create, t('tab_create'), active: false),
      _TabSpec(_TabKind.cart, t('tab_cart'), badge: cartCount, active: _index == 2),
      _TabSpec(_TabKind.account, t('tab_profile'), active: _index == 3),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _AppTabBar(
        tabs: tabs,
        onTap: (kind) {
          switch (kind) {
            case _TabKind.home:
              setState(() => _index = 0);
              break;
            case _TabKind.categories:
              setState(() => _index = 1);
              break;
            case _TabKind.create:
              _startSell(context);
              break;
            case _TabKind.cart:
              setState(() => _index = 2);
              break;
            case _TabKind.account:
              setState(() => _index = 3);
              break;
          }
        },
      ),
    );
  }
}

enum _TabKind { home, categories, create, cart, account }

class _TabSpec {
  final _TabKind kind;
  final String label;
  final int badge;
  final bool active;

  _TabSpec(this.kind, this.label, {this.badge = 0, this.active = false});
}

/// Barre d'onglets claire — reproduit `<nav class="tabbar">` de
/// la maquette de référence au trait près (icônes, badge rose sur Panier).
/// `.tabbar{padding:9px 2px 0}` et `.tab{gap:5px}` → paddings ci-dessous.
/// Le bouton central "Créer" (4 septembre 2026) n'est jamais actif — c'est
/// une action, pas une destination — donc toujours affiché en encre pleine.
class _AppTabBar extends StatelessWidget {
  final List<_TabSpec> tabs;
  final ValueChanged<_TabKind> onTap;

  const _AppTabBar({required this.tabs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.panel, // .tabbar{background:var(--panel)} dans la maquette de référence
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                for (final tab in tabs)
                  Expanded(
                    child: InkWell(
                      onTap: () => onTap(tab.kind),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _AppTabIcon(
                                kind: tab.kind,
                                color: tab.kind == _TabKind.create
                                    ? AppTheme.ink
                                    : (tab.active ? AppTheme.ink : AppTheme.mutedDark),
                              ),
                              if (tab.badge > 0)
                                Positioned(
                                  top: -4,
                                  right: -9,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    height: 17,
                                    constraints: const BoxConstraints(minWidth: 17),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.ink,
                                      borderRadius: BorderRadius.all(Radius.circular(9)),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${tab.badge}',
                                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: tab.active ? FontWeight.w600 : FontWeight.w500,
                              color: tab.kind == _TabKind.create ? AppTheme.ink : (tab.active ? AppTheme.ink : AppTheme.mutedDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icônes SVG du menu du bas. L'icône Panier garde une petite découpe qui
/// doit toujours avoir la couleur du FOND de la barre (`AppTheme.panel`,
/// passée dynamiquement — jamais codée en dur). L'icône "Créer" (rond +
/// signe plus, 4 septembre 2026) reproduit la capture envoyée par Emina :
/// un simple cercle fin avec une croix au centre, sans remplissage.
class _AppTabIcon extends StatelessWidget {
  final _TabKind kind;
  final Color color;

  const _AppTabIcon({required this.kind, required this.color});

  static String _hex(Color c) => '#${c.value.toRadixString(16).substring(2)}';

  String _svg(String hex, String barBgHex) {
    switch (kind) {
      case _TabKind.home:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="$hex" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M4 11.5 12 4l8 7.5"/>'
            '<path d="M6 10.3V19a1 1 0 0 0 1 1h3v-5.4h4V20h3a1 1 0 0 0 1-1v-8.7"/></svg>';
      case _TabKind.cart:
        // Icône "sac" (15 septembre 2026, demande explicite : remplacer
        // l'icône panier par ce sac, voir capture de référence) — panier
        // avec anse arrondie, à la place de l'ancien chariot de course.
        return '<svg viewBox="0 0 24 24" fill="none" stroke="$hex" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M7 8.5V6.8a5 5 0 0 1 10 0V8.5"/>'
            '<rect x="4" y="8.5" width="16" height="11.5" rx="2.2"/></svg>';
      case _TabKind.create:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="$hex" stroke-width="1.6" stroke-linecap="round">'
            '<circle cx="12" cy="12" r="9.2"/>'
            '<path d="M12 7.7v8.6M7.7 12h8.6"/></svg>';
      case _TabKind.categories:
        // Icône "liste + loupe" (15 septembre 2026, photo de référence :
        // trois petits traits empilés à gauche, loupe superposée à
        // droite) — remplace la grille 2x2 du 5 septembre 2026.
        return '<svg viewBox="0 0 24 24" fill="none" stroke="$hex" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<line x1="2.6" y1="6.3" x2="7.4" y2="6.3"/>'
            '<line x1="2.6" y1="11.6" x2="7.4" y2="11.6"/>'
            '<line x1="2.6" y1="16.9" x2="7.4" y2="16.9"/>'
            '<circle cx="14.6" cy="11.4" r="5.1"/>'
            '<line x1="18.3" y1="15.1" x2="21.6" y2="18.4"/></svg>';
      case _TabKind.account:
        // Remplacé le 15 septembre 2026 (photo de référence : trois points
        // pleins alignés, libellé "MORE") — l'onglet est renommé "Plus" /
        // "More" en même temps (voir strings.dart), donc l'ancienne icône
        // "buste" (compte personnel) n'avait plus de sens.
        return '<svg viewBox="0 0 24 24">'
            '<circle cx="5" cy="12" r="2.1" fill="$hex"/>'
            '<circle cx="12" cy="12" r="2.1" fill="$hex"/>'
            '<circle cx="19" cy="12" r="2.1" fill="$hex"/></svg>';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_svg(_hex(color), _hex(AppTheme.panel)), width: 24, height: 24);
  }
}
