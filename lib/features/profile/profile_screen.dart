import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import '../auth/login_screen.dart';
import '../orders/orders_screen.dart';
import '../../services/role_controller.dart';
import '../vendor/my_shop_screen.dart';
import 'edit_profile_screen.dart';
import 'help_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Pas de logo ni de titre "Compte" au-dessus, connecté ou pas
            // (3 septembre 2026, retour d'Emina) : ni meskappcompte.html ni
            // meskappcompteconnecte.html n'ont ce bandeau — l'écran commence
            // directement par "Mon compte" ou par le nom de la personne.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 28),
                children: [
                  if (!auth.isLoggedIn)
                    // Écran "Compte" non connecté — reproduit meskappcompte.html au
                    // trait près (3 septembre 2026, demande d'Emina) : bandes
                    // pleine largeur entre les groupes, lignes fines entre les
                    // lignes d'un même groupe, bouton plein largeur à angles
                    // droits. Palette déjà celle de MESK (le fichier fourni
                    // utilise directement --black/--panel/--pink de l'app).
                    _NotLoggedInAccount(t: t)
                  else
                    // Écran "Compte (connectée)" — reproduit
                    // meskappcompteconnecte.html au trait près (3 septembre
                    // 2026) : nom + email en intro, "Mon profil" ouvre
                    // désormais l'écran meskappprofil.html (déconnexion et
                    // suppression de compte y ont été déplacées).
                    _LoggedInAccount(t: t, profile: auth.profile),
                  const SizedBox(height: 26),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        'Copyright © 2026 · All rights reserved',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: AppTheme.muted, height: 1.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showLanguageSheet(BuildContext context) {
  final settings = context.read<SettingsController>();
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const [('fr', 'Français'), ('ar', 'العربية'), ('en', 'English')])
              ListTile(
                title: Text(entry.$2),
                trailing: settings.locale == entry.$1 ? const Icon(Icons.check, color: AppTheme.red) : null,
                onTap: () {
                  settings.setLocale(entry.$1);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Contenu complet de l'écran "Compte" non connecté — intro + CTA, puis
/// groupes de lignes séparés par des bandes pleine largeur, exactement comme
/// `meskappcompte.html`. `Stateful` uniquement pour le petit interrupteur
/// visuel "Mode sombre" (l'app MESK n'a qu'un seul thème, sombre — comme
/// dans le fichier source lui-même, ce interrupteur ne fait rien d'autre
/// que s'animer : c'est déjà tout ce que fait son JS de démonstration).
class _NotLoggedInAccount extends StatefulWidget {
  final String Function(String) t;

  const _NotLoggedInAccount({required this.t});

  @override
  State<_NotLoggedInAccount> createState() => _NotLoggedInAccountState();
}

class _NotLoggedInAccountState extends State<_NotLoggedInAccount> {
  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.t('coming_soon'))));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Column(
      children: [
        _AccountIntro(t: t),
        const _Band(),
        // Depuis le 6 septembre 2026, l'écran Compte ne propose PLUS de
        // s'inscrire comme vendeuse : cette demande vit maintenant dans le
        // bouton central de la barre du bas. Ici, on n'affiche que l'accès
        // à son espace, et seulement si on en a un.
        const _MySpaceRows(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.bell, label: t('comm_preferences'), onTap: _comingSoon),
          _AccountRow(icon: _AccIcon.globe, label: t('country_language'), onTap: () => _showLanguageSheet(context)),
        ]),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.grid, label: t('services_more'), onTap: _comingSoon),
          _AccountRow(
            icon: _AccIcon.help,
            label: t('help_assistance'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
        ]),
      ],
    );
  }
}

/// `.intro{padding:40px 26px 20px;text-align:center}` — titre, texte, puis
/// bouton plein largeur à angles droits (pas de `StadiumBorder` ici,
/// contrairement à l'ancien bandeau "Bienvenue").
class _AccountIntro extends StatelessWidget {
  final String Function(String) t;

  const _AccountIntro({required this.t});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 40, 26, 20),
      child: Column(
        children: [
          Text(
            t('sign_in_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.ink, letterSpacing: -0.5),
          ),
          const SizedBox(height: 9),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              t('sign_in_sub'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.55, color: AppTheme.ink.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(t('sign_in_cta'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.band{height:9px;background:var(--panel)}` — sépare les groupes de
/// lignes, pleine largeur (pas de marge, contrairement aux cartes utilisées
/// une fois connecté).
class _Band extends StatelessWidget {
  const _Band();

  @override
  Widget build(BuildContext context) => Container(height: 9, color: AppTheme.panel);
}

/// Un groupe de lignes : une ligne fine et en retrait (`margin-left:51px`,
/// alignée après l'icône) sépare chaque ligne de la suivante, mais pas la
/// première du haut de groupe (déjà séparée par une `_Band`).
class _RowGroup extends StatelessWidget {
  final List<_AccountRow> rows;

  const _RowGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const Padding(padding: EdgeInsets.only(left: 51), child: Divider(height: 1, thickness: 1, color: AppTheme.line)),
          rows[i],
        ],
      ],
    );
  }
}

enum _AccIcon { profile, orders, address, vendor, bell, globe, moon, grid, help }

/// Contenu complet de l'écran "Compte" connecté — reproduit
/// meskappcompteconnecte.html : nom + email en intro (pas de logo), puis
/// "Mon profil" seul dans son groupe, "Mes commandes" (avec la pastille du
/// nombre de commandes) + "Mes adresses de livraison", puis les mêmes
/// groupes que la version non connectée (vendeuse / préférences / aide).
class _LoggedInAccount extends StatefulWidget {
  final String Function(String) t;
  final Profile? profile;

  const _LoggedInAccount({required this.t, required this.profile});

  @override
  State<_LoggedInAccount> createState() => _LoggedInAccountState();
}

class _LoggedInAccountState extends State<_LoggedInAccount> {
  late final Future<int> _orderCount;

  @override
  void initState() {
    super.initState();
    _orderCount = OrderService().fetchMyOrders().then((orders) => orders.length).catchError((_) => 0);
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.t('coming_soon'))));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Column(
      children: [
        _ConnectedIntro(profile: widget.profile),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(
            icon: _AccIcon.profile,
            label: t('my_profile'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
        ]),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(
            icon: _AccIcon.orders,
            label: t('my_orders'),
            trailing: FutureBuilder<int>(
              future: _orderCount,
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.ink, borderRadius: BorderRadius.circular(9)),
                        child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 14),
                    ],
                    const _AccountChevron(),
                  ],
                );
              },
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen())),
          ),
          _AccountRow(icon: _AccIcon.address, label: t('my_addresses'), onTap: _comingSoon),
        ]),
        const _Band(),
        // Depuis le 6 septembre 2026, l'écran Compte ne propose PLUS de
        // s'inscrire comme vendeuse : cette demande vit maintenant dans le
        // bouton central de la barre du bas. Ici, on n'affiche que l'accès
        // à son espace, et seulement si on en a un.
        const _MySpaceRows(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.bell, label: t('comm_preferences'), onTap: _comingSoon),
          _AccountRow(icon: _AccIcon.globe, label: t('country_language'), onTap: () => _showLanguageSheet(context)),
        ]),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.grid, label: t('services_more'), onTap: _comingSoon),
          _AccountRow(
            icon: _AccIcon.help,
            label: t('help_assistance'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
        ]),
      ],
    );
  }
}

/// `.intro{padding:44px 22px 26px;text-align:center}` de
/// meskappcompteconnecte.html — nom complet puis email, pas de logo ni de
/// bouton (déjà connectée).
class _ConnectedIntro extends StatelessWidget {
  final Profile? profile;

  const _ConnectedIntro({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 26),
      child: Column(
        children: [
          Text(
            profile?.fullName?.trim().isNotEmpty == true ? profile!.fullName!.trim() : (profile?.email ?? ''),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.ink, letterSpacing: -0.3),
          ),
          const SizedBox(height: 7),
          Text(
            profile?.email ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.ink.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// `.row{gap:14px;padding:14px 18px;font-size:13px;font-weight:600}` —
/// icône SVG 19×19 recopiée du fichier source, libellé, puis un chevron
/// (ou l'interrupteur "Mode sombre").
class _AccountRow extends StatelessWidget {
  final _AccIcon icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _AccountRow({required this.icon, required this.label, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            _AccountRowIcon(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink)),
            ),
            trailing ?? const _AccountChevron(),
          ],
        ),
      ),
    );
  }
}

/// Icônes SVG des lignes "Compte", recopiées de `meskappcompte.html` (mêmes
/// `<path>`, `viewBox="0 0 24 24"`) — trait `#2B2B2B` (AppTheme.ink) depuis
/// le passage au thème clair du 3 septembre 2026 (c'était `#fff` du temps du
/// thème sombre) — toujours cette même couleur ici, contrairement aux
/// icônes du menu du bas qui changent selon l'onglet actif.
class _AccountRowIcon extends StatelessWidget {
  final _AccIcon icon;

  const _AccountRowIcon({required this.icon});

  String get _svg {
    switch (icon) {
      case _AccIcon.profile:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M16.5 4.6 19.4 7.5 8.9 18H6v-2.9z"/>'
            '<path d="M14.4 6.7l2.9 2.9"/></svg>';
      case _AccIcon.orders:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linejoin="round">'
            '<path d="M12 3.2l8 4.3v9l-8 4.3-8-4.3v-9z"/>'
            '<path d="M4 7.5l8 4.3 8-4.3M12 11.8v8.9"/></svg>';
      case _AccIcon.address:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linejoin="round">'
            '<path d="M12 21s6.6-6 6.6-11A6.6 6.6 0 0 0 5.4 10c0 5 6.6 11 6.6 11z"/>'
            '<circle cx="12" cy="10" r="2.4"/></svg>';
      case _AccIcon.vendor:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M4.6 7.8h14.8v9.4a2.2 2.2 0 0 1-2.2 2.2H6.8a2.2 2.2 0 0 1-2.2-2.2z"/>'
            '<path d="M8.9 7.8V6.2a3.1 3.1 0 0 1 6.2 0v1.6"/>'
            '<circle cx="15.1" cy="16.4" r="2.9" fill="#fff"/>'
            '<path d="M17.3 18.6l2 2"/></svg>';
      case _AccIcon.bell:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<path d="M18 8.8a6 6 0 1 0-12 0c0 5.8-2.1 7.2-2.1 7.2h16.2S18 14.6 18 8.8z"/>'
            '<path d="M13.7 19.8a2 2 0 0 1-3.4 0"/></svg>';
      case _AccIcon.globe:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7">'
            '<circle cx="12" cy="12" r="8.6"/><path d="M3.4 12h17.2M12 3.4a13 13 0 0 1 0 17.2 13 13 0 0 1 0-17.2z"/></svg>';
      case _AccIcon.moon:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linejoin="round">'
            '<path d="M20 14.2A8.4 8.4 0 0 1 9.8 4a8.4 8.4 0 1 0 10.2 10.2z"/></svg>';
      case _AccIcon.grid:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linejoin="round">'
            '<path d="M8.2 8.2h11.6v11.6H8.2z"/><path d="M4.2 4.2h11.6v3M4.2 4.2v11.6h3"/></svg>';
      case _AccIcon.help:
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linejoin="round">'
            '<path d="M20 4.6H4v10.8h4v4l4.4-4H20z"/></svg>';
    }
  }

  @override
  Widget build(BuildContext context) => SvgPicture.string(_svg, width: 19, height: 19);
}

class _AccountChevron extends StatelessWidget {
  const _AccountChevron();

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>',
        width: 15,
        height: 15,
      );
}



/// Accès à son espace vendeuse, sur l'écran Compte — 6 septembre 2026.
///
/// N'apparaît que si la personne a déjà une boutique. Une simple cliente ne
/// voit rien ici : pour s'inscrire, elle passe par le bouton central de la
/// barre du bas.
class _MySpaceRows extends StatelessWidget {
  const _MySpaceRows();

  @override
  Widget build(BuildContext context) {
    final role = context.watch<RoleController>();
    final rows = <_AccountRow>[
      if (role.isVendor)
        _AccountRow(
          icon: _AccIcon.vendor,
          label: 'Espace vendeuse',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyShopScreen()),
          ),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        _RowGroup(rows: rows),
        const _Band(),
      ],
    );
  }
}
