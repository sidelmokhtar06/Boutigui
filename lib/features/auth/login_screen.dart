import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/role_controller.dart';

/// Écran de connexion — **e-mail + mot de passe ET Google**, depuis le
/// 20 septembre 2026.
///
/// Historique, parce qu'il compte : le formulaire manuel avait été retiré
/// le 2 septembre 2026 puis l'écran passé en Google seul le 15 septembre,
/// à la demande d'Emina (« l'inscription se fait uniquement via Gmail »).
/// La raison donnée alors était bonne : « une adresse e-mail saisie à la
/// main n'est jamais vérifiée, alors que Google garantit que l'adresse
/// existe vraiment ».
///
/// Ce que ça coûtait : toute personne sans compte Google — ou qui n'a pas
/// envie de lier son compte Google à une boutique — ne pouvait pas entrer
/// du tout. Sur un marché où beaucoup de gens utilisent leur téléphone
/// sans compte Google actif, c'est une porte fermée.
///
/// **L'objection d'origine reste valable et se traite côté Supabase, pas
/// ici** : activer « Confirm email » (Authentication → Providers → Email)
/// oblige à cliquer un lien reçu par courriel avant de pouvoir se
/// connecter. L'adresse est alors vérifiée, exactement comme avec Google.
/// Sans ce réglage, n'importe quelle adresse inventée passerait.
///
/// Les deux méthodes mènent au même endroit : le déclencheur
/// `on_auth_user_created` crée la ligne `profiles` dans les deux cas.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();

  bool _googleLoading = false;
  bool _emailLoading = false;
  bool _obscure = true;
  /// `false` = se connecter, `true` = créer un compte.
  bool _signUpMode = false;
  String? _error;
  String? _notice;
  /// Vrai quand la connexion a échoué parce que l'adresse n'est pas
  /// confirmée : on propose alors de renvoyer le message.
  bool _needsConfirmation = false;
  bool _resending = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
      _notice = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    // Sur le web, signInWithGoogle redirige la page entière vers Google
    // (elle ne revient donc jamais ici) ; sur mobile, on repasse par ce
    // point une fois la fenêtre refermée.
    if (error != null) {
      setState(() => _error = error);
    } else if (auth.isLoggedIn) {
      await context.read<RoleController>().refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  /// Traduit les messages d'erreur de Supabase, qui arrivent en anglais et
  /// dans la langue du serveur, pas dans celle de l'application.
  ///
  /// « Email not confirmed » affiché tel quel ne dit pas non plus QUOI
  /// FAIRE : on renvoie un texte qui donne l'étape suivante.
  String _humanError(String raw, String Function(String) t) {
    final low = raw.toLowerCase();
    if (low.contains('not confirmed')) return t('err_not_confirmed');
    if (low.contains('invalid login') || low.contains('invalid credentials')) {
      return t('err_bad_credentials');
    }
    if (low.contains('already registered') || low.contains('already exists')) {
      return t('err_already_registered');
    }
    return raw;
  }

  Future<void> _resendConfirmation() async {
    final t = context.read<SettingsController>().t;
    setState(() => _resending = true);
    final error = await context.read<AuthService>().resendConfirmation(_email.text.trim());
    if (!mounted) return;
    setState(() {
      _resending = false;
      if (error == null) {
        _error = null;
        _needsConfirmation = false;
        _notice = t('resend_done');
      } else {
        _error = error;
      }
    });
  }

  /// Validation faite ICI plutôt que déléguée à Supabase : un message en
  /// français tout de suite vaut mieux qu'un aller-retour réseau qui
  /// revient avec un texte anglais du serveur.
  String? _validate(String Function(String) t) {
    final email = _email.text.trim();
    if (email.isEmpty) return t('err_email_required');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return t('err_email_invalid');
    }
    if (_password.text.length < 6) return t('err_password_short');
    if (_signUpMode && _fullName.text.trim().isEmpty) {
      return t('err_name_required');
    }
    return null;
  }

  Future<void> _submitEmail() async {
    final t = context.read<SettingsController>().t;
    final problem = _validate(t);
    if (problem != null) {
      setState(() {
        _error = problem;
        _notice = null;
      });
      return;
    }

    setState(() {
      _emailLoading = true;
      _error = null;
      _notice = null;
    });

    final auth = context.read<AuthService>();
    final error = _signUpMode
        ? await auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            fullName: _fullName.text.trim(),
            phone: _phone.text.trim(),
          )
        : await auth.signIn(
            email: _email.text.trim(),
            password: _password.text,
          );

    if (!mounted) return;
    setState(() => _emailLoading = false);

    if (error != null) {
      setState(() {
        _error = _humanError(error, t);
        _needsConfirmation = error.toLowerCase().contains('not confirmed');
      });
      return;
    }

    if (auth.isLoggedIn) {
      await context.read<RoleController>().refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      // Inscription réussie mais pas encore connectée : c'est le cas quand
      // « Confirm email » est activé côté Supabase. Il faut le DIRE, sinon
      // l'écran ne fait visiblement rien et la personne réessaie.
      setState(() {
        _signUpMode = false;
        _notice = t('signup_check_email');
      });
    }
  }

  /// Décoration des champs — 22 septembre 2026, alignée sur le reste de
  /// l'application.
  ///
  /// Cette méthode REDÉFINISSAIT tout : remplissage, bordures, rayon 12 et
  /// surtout une bordure de focus VERTE. Or `inputDecorationTheme`
  /// (theme.dart) pose déjà exactement les mêmes champs pour toute
  /// l'application — rayon 15, bordure `line`, et focus `ink`. Les deux
  /// séries de valeurs divergeaient : un champ de cet écran ne ressemblait
  /// donc à aucun autre champ de l'appli, et le vert au focus n'existe
  /// nulle part ailleurs (le vert sert d'accent, jamais de couleur
  /// d'interface).
  ///
  /// On ne garde donc ici que ce qui est PROPRE à ce formulaire — libellé,
  /// texte d'aide, icône de fin. Le reste vient du thème, et suivra
  /// automatiquement s'il change.
  InputDecoration _boxed(String label, {String? helper, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final busy = _emailLoading || _googleLoading;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: AppTheme.bg,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        title: Text(t('login'), style: const TextStyle(color: AppTheme.ink)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeToggle(
                signUpMode: _signUpMode,
                signInLabel: t('tab_sign_in'),
                signUpLabel: t('tab_sign_up'),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          _signUpMode = v;
                          _error = null;
                          _notice = null;
                        }),
              ),
              const SizedBox(height: 20),
              Text(
                // Le sous-titre suivait le mode depuis le 20 septembre
                // 2026 : `vendor_gate_subtitle` parle de CRÉER un compte,
                // ce qui n'a aucun sens au-dessus d'un formulaire de
                // connexion.
                _signUpMode ? t('vendor_gate_subtitle') : t('sign_in_sub_short'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppTheme.ink2, height: 1.4),
              ),
              const SizedBox(height: 20),

              // Nom et téléphone ne servent qu'à la création de compte :
              // les redemander à la connexion n'aurait aucun sens.
              if (_signUpMode) ...[
                TextField(
                  controller: _fullName,
                  textCapitalization: TextCapitalization.words,
                  decoration: _boxed(t('full_name')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: _boxed(t('phone_optional')),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: _boxed(t('email')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                // Envoyer le formulaire depuis le clavier : sur un
                // téléphone, viser un bouton après avoir tapé son mot de
                // passe est un geste de trop.
                onSubmitted: (_) => busy ? null : _submitEmail(),
                decoration: _boxed(
                  t('password'),
                  helper: _signUpMode ? t('password_min') : null,
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppTheme.muted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                _Message(text: _error!, isError: true),
                if (_needsConfirmation) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _resending ? null : _resendConfirmation,
                    child: _resending
                        ? const SizedBox(
                            height: 15, width: 15,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(t('resend_confirmation'),
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
              if (_notice != null) ...[
                const SizedBox(height: 14),
                _Message(text: _notice!, isError: false),
              ],

              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                // Aucun `styleFrom` : le `filledButtonTheme` donne déjà le
                // fond `ink`, le texte blanc et le rayon 16 de tous les
                // boutons pleins de l'application. Il portait ici un vert
                // (`greenDeep`) et un rayon « pilule » qu'on ne trouve sur
                // aucun autre bouton — le vert est un accent, pas la
                // couleur des actions principales.
                //
                // Majuscules + `letterSpacing: 0.6` : c'est la forme des
                // appels à l'action de l'appli (voir « ADD TO BAG » et
                // « GO TO BAG », product_screen.dart).
                child: FilledButton(
                  onPressed: busy ? null : _submitEmail,
                  child: _emailLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          (_signUpMode ? t('tab_sign_up') : t('tab_sign_in')).toUpperCase(),
                          style: const TextStyle(letterSpacing: 0.6),
                        ),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider(color: AppTheme.line)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(t('or_divider'),
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  ),
                  const Expanded(child: Divider(color: AppTheme.line)),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                height: 52,
                // Idem : `outlinedButtonTheme` fournit le contour et le
                // rayon 16 communs. Seule la pilule était propre à cet
                // écran.
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _continueWithGoogle,
                  icon: _googleLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const _GoogleLogo(size: 18),
                  label: Text(t('continue_with_google'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bascule « Se connecter » / « Créer un compte ».
///
/// Deux segments plutôt qu'un lien discret en bas de page : à la première
/// ouverture, on doit voir tout de suite que créer un compte est possible.
class _ModeToggle extends StatelessWidget {
  final bool signUpMode;
  final String signInLabel;
  final String signUpLabel;
  final ValueChanged<bool>? onChanged;

  const _ModeToggle({
    required this.signUpMode,
    required this.signInLabel,
    required this.signUpLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        // Rayon 16, comme les boutons — et non la « pilule » de 20, qui
        // n'apparaît nulle part ailleurs dans l'application.
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _segment(signInLabel, active: !signUpMode, value: false),
          _segment(signUpLabel, active: signUpMode, value: true),
        ],
      ),
    );
  }

  Widget _segment(String label, {required bool active, required bool value}) {
    return Expanded(
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            // Segment actif en `ink` sur texte blanc : c'est ce que pose
            // `segmentedButtonTheme` (theme.dart) pour toute
            // l'application. Le segment actif était auparavant une simple
            // carte blanche sur fond gris clair — lisible, mais sans
            // rapport avec les autres sélecteurs de l'appli.
            color: active ? AppTheme.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              // Le segment actif se distingue par le fond ET par la
              // graisse — jamais par la seule couleur.
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : AppTheme.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Message d'erreur ou d'information sous le formulaire.
class _Message extends StatelessWidget {
  final String text;
  final bool isError;
  const _Message({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? AppTheme.redTint : AppTheme.greenTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 17,
            color: isError ? AppTheme.red : AppTheme.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: isError ? AppTheme.red : AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Petit repère visuel "G" pour le bouton Google — texte simple plutôt
/// qu'un logo SVG (pas d'image à embarquer, pas de dépendance
/// supplémentaire à ajouter au projet), le libellé "Continuer avec Google"
/// portant déjà l'information.
class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Text(
      'G',
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: AppTheme.ink,
      ),
    );
  }
}
