import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/vendor_service.dart';
import '../auth/login_screen.dart';
import 'my_shop_screen.dart';

/// Point d'entrée commun vers "Ma boutique" — factorisé le 4 septembre 2026
/// (soir) pour que TOUS les chemins qui mènent à devenir vendeuse (le
/// bouton "Créer" de `shell.dart`, ET "Rejoindre en tant que vendeuse" sur
/// l'écran Compte, `profile_screen.dart`) se comportent exactement pareil :
/// avant, seul le bouton "Créer" passait par [VendorGateScreen] — l'entrée
/// depuis le Compte sautait directement à la création de boutique, ce qui
/// aurait contredit la demande d'Emina ("La partie 3 c'est login ou
/// registre seulement pour le vendeur même si il a un compte client").
///
/// Si une boutique existe déjà, l'écran de connexion vendeuse n'est PAS
/// remontré (il ne sert qu'avant la toute première création) : on va
/// directement au tableau de bord de la boutique.
Future<void> openMyShop(
  BuildContext context, {
  String? initialCategoryId,
  // Catégories choisies à l'inscription (6 septembre 2026) — enregistrées
  // sur la boutique juste après sa création.
  List<String> categoryIds = const [],
}) async {
  final existingShop = await VendorService().fetchMyShop();
  if (!context.mounted) return;
  if (existingShop == null) {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const VendorGateScreen()),
    );
    if (confirmed != true || !context.mounted) return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MyShopScreen(initialCategoryId: initialCategoryId, initialCategoryIds: categoryIds),
    ),
  );
}

/// Écran "Login or Register" dédié au parcours vendeuse — demandé le
/// 4 septembre 2026, texte exact d'Emina : « La partie 3 c'est login ou
/// registre seulement pour le vendeur même si il a un compte client ».
///
/// Poussé par [Shell._startSell] avant la création de la toute première
/// boutique, TOUJOURS — même pour une personne déjà connectée en tant que
/// cliente : dans ce cas, cet écran ne redemande pas un mot de passe, mais
/// affiche une carte de confirmation explicite ("Connectée en tant que...")
/// qu'il faut valider pour continuer, plutôt que de sauter directement à la
/// création de la boutique. Ferme avec `pop(true)` seulement après cette
/// confirmation explicite ; `pop(false)` (ou retour arrière) annule le
/// parcours "Créer" entièrement.
///
/// Techniquement, c'est toujours le même compte (même table `profiles`,
/// même connexion e-mail/Google — voir `login_screen.dart` pour pourquoi il
/// n'y a pas de vérification par SMS) : il n'existe qu'un seul système de
/// comptes dans l'application, pas un second système "vendeuse" séparé. Ce
/// choix a été fait en recherchant comment Oskelly gère réellement ses
/// vendeurs (voir admin_patch.sql, section du 4 septembre 2026, soir) :
/// eux non plus n'ont pas de compte vendeur distinct du compte client — on
/// vend "en deux clics" depuis le même compte. Ce que cet écran ajoute,
/// c'est l'étape de confirmation explicite demandée par Emina.
class VendorGateScreen extends StatefulWidget {
  const VendorGateScreen({super.key});

  @override
  State<VendorGateScreen> createState() => _VendorGateScreenState();
}

class _VendorGateScreenState extends State<VendorGateScreen> {
  bool _googleLoading = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (error != null) setState(() => _error = error);
  }

  Future<void> _switchAccount() async {
    await context.read<AuthService>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Croix en haut à gauche, comme sur la capture de référence —
            // pas une flèche de retour : cet écran se ferme, il ne
            // "revient" pas.
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppTheme.ink, size: 26),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Gros titre en bas de l'écran vide, comme la capture.
                    const SizedBox(height: 90),
                    Text(
                      t('vendor_gate_title'),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: AppTheme.ink, height: 1.1),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t('vendor_gate_subtitle'),
                      style: const TextStyle(fontSize: 15, color: AppTheme.ink2, height: 1.4),
                    ),
                    const SizedBox(height: 30),
                    if (auth.isLoggedIn)
                      _ConnectedCard(auth: auth, onSwitchAccount: _switchAccount)
                    else ...[
                      // Bouton noir principal, à la place du "Send Code" de
                      // la capture : chez nous c'est Google qui crée le
                      // compte (voir la note plus bas sur le SMS).
                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: _googleLoading ? null : _continueWithGoogle,
                          icon: _googleLoading
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const _GoogleLogo(size: 18),
                          label: Text(
                            t('continue_with_google'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      // Entrée par e-mail (20 septembre 2026) — cet écran
                      // ne proposait que Google, ce qui fermait la porte à
                      // qui n'a pas de compte Google actif. On renvoie vers
                      // `LoginScreen`, qui porte les deux méthodes, plutôt
                      // que de recopier un second formulaire ici.
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: _googleLoading
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  );
                                  if (!context.mounted) return;
                                  if (context.read<AuthService>().isLoggedIn) {
                                    setState(() {});
                                  }
                                },
                          icon: const Icon(Icons.mail_outline, size: 18),
                          label: Text(
                            t('continue_with_email'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 13)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte "Connectée en tant que..." — affichée quand la personne a déjà un
/// compte connecté (typiquement une cliente qui appuie sur "Créer"). Il
/// faut appuyer sur "Continuer" pour valider explicitement qu'elle veut
/// devenir vendeuse ; "Utiliser un autre compte" déconnecte pour laisser
/// place au formulaire de connexion ci-dessus.
class _ConnectedCard extends StatelessWidget {
  final AuthService auth;
  final Future<void> Function() onSwitchAccount;

  const _ConnectedCard({required this.auth, required this.onSwitchAccount});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final label = auth.profile?.fullName ?? auth.profile?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const CircleAvatar(radius: 20, backgroundColor: AppTheme.line, child: Icon(Icons.person_outline, color: AppTheme.ink2)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('vendor_gate_connected_as'), style: const TextStyle(fontSize: 11.5, color: AppTheme.muted)),
                    const SizedBox(height: 2),
                    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t('vendor_gate_continue')),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onSwitchAccount,
          child: Text(t('vendor_gate_switch_account'), style: const TextStyle(color: AppTheme.ink2)),
        ),
      ],
    );
  }
}

/// Même repère visuel "G" que sur login_screen.dart (pas de logo dessiné à
/// la main ni de dépendance d'image supplémentaire) — dupliqué ici plutôt
/// qu'exporté, cette classe étant privée à son fichier d'origine.
class _GoogleLogo extends StatelessWidget {
  final double size;

  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(fontSize: size, height: 1, fontWeight: FontWeight.w700, color: const Color(0xFF4285F4)),
        ),
      ),
    );
  }
}
