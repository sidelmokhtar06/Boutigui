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
import '../driver/driver_gate_screen.dart';
import '../vendor/my_shop_screen.dart';
import 'edit_profile_screen.dart';
import 'help_screen.dart';
import '../widgets.dart';

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
            // (3 septembre 2026, retour d'Emina) : ni la maquette de référence ni
            // la maquette de référence n'ont ce bandeau — l'écran commence
            // directement par "Mon compte" ou par le nom de la personne.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 28),
                children: [
                  if (!auth.isLoggedIn)
                    // Écran "Compte" non connecté — reproduit la maquette de référence au
                    // trait près (3 septembre 2026, demande d'Emina) : bandes
                    // pleine largeur entre les groupes, lignes fines entre les
                    // lignes d'un même groupe, bouton plein largeur à angles
                    // droits. Palette déjà celle de l'app (le fichier fourni
                    // utilise directement --black/--panel/--pink de l'app).
                    _NotLoggedInAccount(t: t)
                  else
                    // Écran "Compte (connectée)" — reproduit
                    // la maquette de référence au trait près (3 septembre
                    // 2026) : nom + email en intro, "Mon profil" ouvre
                    // désormais l'écran la maquette de référence (déconnexion et
                    // suppression de compte y ont été déplacées).
                    _LoggedInAccount(t: t, profile: auth.profile),
                  const SizedBox(height: 26),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        'Copyright © 2026 · All rights reserved',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.muted, height: 1.8),
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

/// Sélecteur de langue — anglais et français réellement sélectionnables
/// depuis le 15 septembre 2026 (deuxième correction : voir
/// `settings_controller.dart`). L'arabe reste volontairement absent de
/// cette liste (demande explicite : "supprime la possibilité de traduire
/// vers l'arabe").
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
            for (final entry in const [('en', 'English'), ('fr', 'Français')])
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
/// la maquette de référence. `Stateful` uniquement pour le petit interrupteur
/// visuel "Mode sombre" (l'app l'app n'a qu'un seul thème, sombre — comme
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
          _AccountRow(icon: _AccIcon.bell, label: t('comm_preferences'), subtitle: t('sub_comm_preferences'), tint: AppTheme.promoPink, onTap: _comingSoon),
          _AccountRow(icon: _AccIcon.globe, label: t('country_language'), subtitle: t('sub_country_language'), tint: AppTheme.searchFill, onTap: () => _showLanguageSheet(context)),
        ]),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.grid, label: t('services_more'), subtitle: t('sub_services_more'), tint: AppTheme.greenTint, onTap: _comingSoon),
          _AccountRow(
            icon: _AccIcon.help,
            label: t('help_assistance'),
            subtitle: t('sub_help_assistance'),
            tint: AppTheme.promoPink,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
        ]),
        _SupportCard(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const HelpScreen())),
        ),
        const SizedBox(height: 20),
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
  // Ramenée à un simple espace le 20 septembre 2026 : les groupes sont
  // maintenant des cartes détachées, une bande grise entre eux ferait un
  // séparateur de trop.
  Widget build(BuildContext context) => const SizedBox(height: 6);
}

/// Un groupe de lignes : une ligne fine et en retrait (`margin-left:51px`,
/// alignée après l'icône) sépare chaque ligne de la suivante, mais pas la
/// première du haut de groupe (déjà séparée par une `_Band`).
/// Refait le 20 septembre 2026 : chaque ligne devient sa PROPRE carte
/// blanche, au lieu d'un bloc unique découpé par des filets.
///
/// Un bloc continu se lit comme un mur de texte ; des cartes séparées se
/// balaient du regard et donnent à chaque entrée une cible tactile
/// évidente. C'est ce que montre la maquette fournie, et c'est aussi la
/// forme déjà utilisée partout ailleurs dans l'application depuis la
/// refonte de l'accueil.
class _RowGroup extends StatelessWidget {
  final List<_AccountRow> rows;

  const _RowGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.line),
              ),
              child: row,
            ),
        ],
      ),
    );
  }
}

enum _AccIcon { profile, orders, address, vendor, driver, bell, globe, moon, grid, help }

/// Contenu complet de l'écran "Compte" connecté — reproduit
/// la maquette de référence : nom + email en intro (pas de logo), puis
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
            subtitle: t('sub_my_profile'),
            tint: AppTheme.greenTint,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
        ]),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(
            icon: _AccIcon.orders,
            label: t('my_orders'),
            subtitle: t('sub_my_orders'),
            tint: AppTheme.searchFill,
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
          _AccountRow(icon: _AccIcon.address, label: t('my_addresses'), subtitle: t('sub_my_addresses'), tint: AppTheme.redTint, onTap: _comingSoon),
        ]),
        const _Band(),
        // Depuis le 6 septembre 2026, l'écran Compte ne propose PLUS de
        // s'inscrire comme vendeuse : cette demande vit maintenant dans le
        // bouton central de la barre du bas. Ici, on n'affiche que l'accès
        // à son espace, et seulement si on en a un.
        const _MySpaceRows(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.bell, label: t('comm_preferences'), subtitle: t('sub_comm_preferences'), tint: AppTheme.promoPink, onTap: _comingSoon),
          _AccountRow(icon: _AccIcon.globe, label: t('country_language'), subtitle: t('sub_country_language'), tint: AppTheme.searchFill, onTap: () => _showLanguageSheet(context)),
        ]),
        const _Band(),
        _RowGroup(rows: [
          _AccountRow(icon: _AccIcon.grid, label: t('services_more'), subtitle: t('sub_services_more'), tint: AppTheme.greenTint, onTap: _comingSoon),
          _AccountRow(
            icon: _AccIcon.help,
            label: t('help_assistance'),
            subtitle: t('sub_help_assistance'),
            tint: AppTheme.promoPink,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
          ),
        ]),
        _SupportCard(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const HelpScreen())),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// `.intro{padding:44px 22px 26px;text-align:center}` de
/// la maquette de référence — nom complet puis email, pas de logo ni de
/// bouton (déjà connectée).
/// En-tête de l'écran Compte — refait le 20 septembre 2026 d'après la
/// maquette fournie : bandeau vert clair, photo ronde, nom, adresse, et
/// une pastille de rôle.
///
/// **La pastille donne le RÔLE, pas un statut d'abonnement.** La maquette
/// affichait « Premium Member ». Boutigui n'a aucun abonnement : écrire cela
/// afficherait à chaque personne un statut payant qui n'existe pas. Le
/// rôle réel — cliente, vendeuse, livreuse, administrateur — est vrai,
/// et il est plus utile : sur cet écran, il explique pourquoi certaines
/// lignes du menu apparaissent.
class _ConnectedIntro extends StatelessWidget {
  final Profile? profile;

  const _ConnectedIntro({required this.profile});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final role = context.watch<RoleController>();
    final name = profile?.fullName?.trim().isNotEmpty == true
        ? profile!.fullName!.trim()
        : (profile?.email ?? '');
    final avatar = profile?.avatarUrl;

    final roleLabel = profile?.role == 'admin'
        ? t('role_admin')
        : role.isVendor
            ? t('role_vendor')
            : role.isDriver
                ? t('role_driver')
                : t('role_client');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.greenTint, AppTheme.sage],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.card,
              border: Border.all(color: AppTheme.card, width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: avatar == null || avatar.isEmpty
                ? const Icon(Icons.person_outline, size: 38, color: AppTheme.muted)
                : AppImage(url: avatar, fit: BoxFit.cover, thumbnail: true),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w700, color: AppTheme.ink, letterSpacing: -0.3),
          ),
          if (profile?.email != null && profile!.email!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile!.email!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.ink2),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_outlined, size: 15, color: AppTheme.green),
                const SizedBox(width: 6),
                Text(roleLabel,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'assistance en bas de l'écran Compte (20 septembre 2026).
class _SupportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SupportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.greenTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('satisfaction_title'),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 2),
          Text(t('satisfaction_sub'),
              style: const TextStyle(fontSize: 12, color: AppTheme.ink2)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.greenDeep),
              icon: const Icon(Icons.chat_bubble_outline, size: 17),
              label: Text(t('contact_support')),
            ),
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

  /// Phrase sous l'intitulé (20 septembre 2026). Facultative : une ligne
  /// sans sous-titre reste simplement centrée sur son intitulé.
  final String? subtitle;

  /// Teinte de la pastille derrière l'icône. La maquette donne une couleur
  /// différente par ligne : c'est ce qui rend une longue liste de menu
  /// balayable du regard, chaque entrée devenant reconnaissable à sa
  /// couleur plutôt qu'à sa seule position.
  final Color tint;

  const _AccountRow({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
    this.subtitle,
    this.tint = AppTheme.greenTint,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Center(child: _AccountRowIcon(icon: icon)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 11.5, height: 1.25, color: AppTheme.ink2)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? const _AccountChevron(),
          ],
        ),
      ),
    );
  }
}

/// Icônes SVG des lignes "Compte", recopiées de la maquette de référence (mêmes
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
      case _AccIcon.driver:
        // Icône scooter/livraison simplifiée — deux roues + un guidon,
        // cohérente avec le trait des autres icônes de ce menu (15
        // septembre 2026, espace Livreur).
        return '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
            '<circle cx="6" cy="18" r="2.4"/><circle cx="18" cy="18" r="2.4"/>'
            '<path d="M6 18h4.2l3-7.4h3.4M13.2 10.6H10M15.6 5.4h2.6l1.6 4"/></svg>';
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



/// Accès à son espace vendeuse et/ou livreur, sur l'écran Compte —
/// 6 septembre 2026, espace Livreur ajouté le 15 septembre 2026.
///
/// La ligne "Seller space" n'apparaît que si la personne a déjà une
/// boutique (pour s'inscrire comme vendeuse, elle passe par le bouton
/// central de la barre du bas). L'espace Livreur, lui, est TOUJOURS
/// proposé ici (une simple cliente peut devenir livreuse directement
/// depuis ce menu, sans repasser par le bouton central) : la ligne mène à
/// l'inscription livreur si la personne n'en a pas encore, ou directement
/// au tableau de courses si elle en a déjà un.
class _MySpaceRows extends StatelessWidget {
  const _MySpaceRows();

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final role = context.watch<RoleController>();
    final rows = <_AccountRow>[
      if (role.isVendor)
        _AccountRow(
          icon: _AccIcon.vendor,
          label: t('vendor_space'),
          subtitle: t('sub_vendor_space'),
          tint: AppTheme.sage,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyShopScreen()),
          ),
        ),
      _AccountRow(
        icon: _AccIcon.driver,
        label: role.isDriver ? t('driver_space') : t('become_driver'),
        subtitle: t('sub_driver_space'),
        tint: AppTheme.greenTint,
        onTap: () => openDriverSpace(context),
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
