import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/role_controller.dart';
import '../widgets.dart';

/// Indicatif unique : la Mauritanie (21 septembre 2026, demande explicite).
///
/// Le menu déroulant proposait +221, +212, +216 et +213. L'application
/// s'adresse à des commerçantes et des clientes mauritaniennes : un choix
/// à cinq entrées dont une seule sert est un choix de trop dans un
/// formulaire. L'indicatif est maintenant affiché, pas demandé.
const String _countryCode = '+222';

/// Les autres indicatifs restent connus EN LECTURE seulement : un numéro
/// enregistré avant ce changement ne doit pas réapparaître avec son
/// indicatif collé devant, ce qui le ferait doubler à la sauvegarde.
const List<String> _knownPrefixes = ['+222', '+221', '+212', '+216', '+213'];

/// Sépare un numéro enregistré en (indicatif, partie locale).
///
/// L'indicatif par défaut est celui de la Mauritanie : c'est le pays de
/// l'application, et de très loin le cas courant.
String _localPhone(String raw) {
  var v = raw.trim();
  if (v.isEmpty) return '';

  // « 00222… » est la même chose que « +222… ».
  if (v.startsWith('00')) v = '+${v.substring(2)}';

  for (final code in _knownPrefixes) {
    final digits = code.substring(1); // « 222 »
    // « +222 42000000 » ou « +22242000000 »
    if (v.startsWith(code)) return v.substring(code.length).trim();
    // « 22242000000 », sans le « + ». On ne coupe QUE s'il reste quelque
    // chose derrière : un numéro local qui commencerait par 222 et ne
    // ferait que trois chiffres ne doit pas devenir un indicatif orphelin.
    if (!v.startsWith('+') && v.startsWith(digits) && v.length > digits.length) {
      return v.substring(digits.length).trim();
    }
  }

  // Indicatif inconnu : on garde le numéro tel quel plutôt que de le
  // tronquer, et on laisse l'indicatif par défaut.
  return v;
}

/// Écran "Mon profil" — reproduit la maquette de référence au trait près
/// (3 septembre 2026, demande d'Emina) : champs séparés par une simple
/// ligne (pas les champs arrondis remplis utilisés ailleurs dans l'app),
/// prénom/nom séparés, indicatif + numéro séparés, email non modifiable,
/// genre, puis les 3 boutons "Enregistrer", "Se déconnecter" et
/// "Supprimer mon compte".
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  String? _gender;
  bool _dirty = false;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _signingOut = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthService>().profile;

    final nameParts = (profile?.fullName ?? '').trim().split(RegExp(r'\s+'));
    _firstName = TextEditingController(text: nameParts.isNotEmpty ? nameParts.first : '');
    _lastName = TextEditingController(text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '');

    // Séparation de l'indicatif — refaite le 21 septembre 2026.
    //
    // L'ancienne version n'acceptait qu'une seule écriture : « +222 » suivi
    // d'une ESPACE. Or un numéro arrive de partout dans l'application —
    // saisi au paiement, recopié sur la commande, écrit par les données de
    // démonstration — et il est le plus souvent enregistré sans espace et
    // sans « + » : « 22242000000 ».
    //
    // Ce cas tombait dans le `else` : l'indicatif restait collé au numéro,
    // le champ affichait « 22242000000 » À CÔTÉ du menu « +222 », et
    // l'enregistrement recomposait « +222 22242000000 » — l'indicatif en
    // double, un peu plus à chaque passage.
    //
    // On reconnaît maintenant les quatre écritures rencontrées :
    // « +222 42000000 », « +22242000000 », « 0022242000000 » et
    // « 22242000000 ».
    _phone = TextEditingController(text: _localPhone(profile?.phone ?? ''));

    // "Prefer not to say" retiré des choix le 15 septembre 2026 (demande
    // explicite) — un compte qui avait choisi cette valeur AVANT ce
    // retrait ne doit pas faire planter le menu déroulant (Flutter exige
    // que la valeur actuelle corresponde à l'un des choix listés) : on la
    // traite comme "pas encore choisi", exactement comme un compte qui
    // n'a jamais renseigné son genre.
    _gender = profile?.gender == 'unspecified' ? null : profile?.gender;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    final auth = context.read<AuthService>();
    final fullName = [_firstName.text.trim(), _lastName.text.trim()].where((s) => s.isNotEmpty).join(' ');
    final phone = _phone.text.trim().isEmpty ? '' : '$_countryCode ${_phone.text.trim()}';
    final error = await auth.updateProfile(fullName: fullName, phone: phone, gender: _gender);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) _dirty = false;
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour.')));
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    // Le rôle est lié au compte : il doit disparaître en même temps, sinon
    // l'écran Compte continuerait d'afficher "Espace vendeuse" pour la
    // personne suivante (6 septembre 2026).
    context.read<RoleController>().clear();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _deleteAccount() async {
    final t = context.read<SettingsController>().t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(t('delete_account_title')),
        content: Text(t('delete_account_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t('cancel'))),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('delete_account_confirm'), style: const TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    final error = await context.read<AuthService>().deleteAccount();
    if (!mounted) return;
    if (error != null) {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  /// Champs ENCADRÉS depuis le 20 septembre 2026 — ils étaient soulignés.
  ///
  /// Le reste de l'application est fait de surfaces arrondies posées sur du
  /// blanc (accueil, catégories, compte) ; un formulaire en traits
  /// soulignés y ressemblait à une pièce rapportée. Un cadre rempli montre
  /// aussi où l'on peut écrire AVANT qu'on y touche, ce qu'un simple trait
  /// ne fait pas.
  ///
  /// La couleur du texte d'invite était un gris de thème SOMBRE écrit en
  /// dur (`0xFF6F6668`), resté là depuis le passage au thème clair du
  /// 3 septembre 2026 — remplacé par le jeton `AppTheme.muted`, comme
  /// l'exige `AGENTS.md`.
  InputDecoration _boxed({String? hint}) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppTheme.panel,
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: AppTheme.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: AppTheme.line),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: AppTheme.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: const BorderSide(color: AppTheme.green, width: 1.6),
        ),
      );

  /// Choisit une photo de profil et l'envoie (21 septembre 2026).
  ///
  /// La colonne `avatar_url` existait depuis le début et l'écran Compte
  /// affichait déjà la photo — mais rien nulle part ne permettait d'en
  /// déposer une. Elle restait donc vide pour tout le monde.
  ///
  /// L'envoi part dès le choix, sans passer par « Enregistrer » : une
  /// photo n'est pas un champ de formulaire, et devoir enregistrer ensuite
  /// laisse croire qu'elle n'a pas été prise en compte.
  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() => _uploadingAvatar = true);
    final error = await context.read<AuthService>().updateAvatar(
          bytes,
          extension: picked.name.split('.').last.toLowerCase(),
        );
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Photo de profil mise à jour.')),
    );
  }

  Widget _label(String text, {bool required = true, bool muted = false}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted ? AppTheme.ink.withValues(alpha: 0.55) : AppTheme.ink),
        children: [
          TextSpan(text: text),
          // Rouge plutôt que mauve (20 septembre 2026) : un champ
          // obligatoire se signale avec la couleur d'alerte de
          // l'application, pas avec une teinte décorative.
          if (required) const TextSpan(text: ' *', style: TextStyle(color: AppTheme.red)),
        ],
      ),
    );
  }

  Widget _field({required String label, required Widget input, bool required = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: required),
          const SizedBox(height: 9),
          input,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final profile = context.watch<AuthService>().profile;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: SvgPicture.string(
                        '<svg viewBox="0 0 24 24" fill="none" stroke="#2B2B2B" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>',
                        width: 22,
                        height: 22,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        t('my_profile'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink, letterSpacing: -0.2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 26),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    _AvatarPicker(
                      url: profile?.avatarUrl,
                      busy: _uploadingAvatar,
                      onTap: _pickAvatar,
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        t('general_info').toUpperCase(),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: AppTheme.ink),
                      ),
                    ),
                    // Les champs vivent dans une carte (20 septembre 2026),
                    // comme les lignes de l'écran Compte et les sections du
                    // tableau de bord : la page cesse d'être une colonne de
                    // champs posés sur le fond et devient un bloc identifié.
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(color: AppTheme.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    _field(
                      label: t('first_name'),
                      input: TextFormField(
                        controller: _firstName,
                        style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                        decoration: _boxed(),
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                    _field(
                      label: t('last_name'),
                      input: TextFormField(
                        controller: _lastName,
                        style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                        decoration: _boxed(),
                        onChanged: (_) => _markDirty(),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Préfixe FIXE, plus un menu : il n'y a qu'un
                        // indicatif. Présenté comme un champ désactivé pour
                        // rester aligné sur le champ voisin.
                        SizedBox(
                          width: 92,
                          child: _field(
                            label: t('country_code'),
                            required: false,
                            input: Container(
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.panel,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                border: Border.all(color: AppTheme.line),
                              ),
                              child: const Text(
                                _countryCode,
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _field(
                            label: t('phone_number'),
                            input: TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                              decoration: _boxed(hint: '42 00 00 00'),
                              onChanged: (_) => _markDirty(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _field(
                      label: t('email_address'),
                      input: TextFormField(
                        initialValue: profile?.email ?? '',
                        readOnly: true,
                        style: TextStyle(color: AppTheme.ink.withValues(alpha: 0.55), fontSize: 14),
                        decoration: _boxed(),
                      ),
                    ),
                    _field(
                      label: t('gender'),
                      input: DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: _boxed(),
                        dropdownColor: AppTheme.panel,
                        icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.muted, size: 18),
                        style: const TextStyle(color: AppTheme.ink, fontSize: 14),
                        items: [
                          DropdownMenuItem(value: 'female', child: Text(t('gender_female'))),
                          DropdownMenuItem(value: 'male', child: Text(t('gender_male'))),
                        ],
                        onChanged: (v) {
                          setState(() => _gender = v);
                          _markDirty();
                        },
                      ),
                    ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // Couleurs reprises du thème le 20 septembre 2026 :
                        // les quatre valeurs ci-dessous étaient écrites en
                        // hexadécimal en dur, ce qu'interdit `AGENTS.md`
                        // (« every colour comes from AppTheme »). Elles
                        // dataient du thème SOMBRE et n'avaient jamais été
                        // reprises au passage au clair : un gris pour thème
                        // sombre sur un fond blanc donnait un bouton
                        // inactif presque illisible.
                        //
                        // Enregistrer est l'action principale de cet
                        // écran : elle passe au vert de marque.
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _dirty ? AppTheme.greenDeep : AppTheme.panel,
                          foregroundColor: _dirty ? Colors.white : AppTheme.muted,
                          disabledBackgroundColor: AppTheme.panel,
                          disabledForegroundColor: AppTheme.muted,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                        ),
                        onPressed: (_dirty && !_saving) ? _save : null,
                        child: _saving
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : Text(t('save_changes'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          // Corrigé le 4 septembre 2026 : le texte était de la
                          // même couleur que le fond (encre sur encre), donc
                          // invisible — Emina ne voyait pas le mot
                          // "Déconnecter" sur ce bouton.
                          // Hiérarchie revue le 20 septembre 2026. Il y
                          // avait deux aplats pleins l'un sous l'autre :
                          // « Enregistrer » et « Se déconnecter » se
                          // disputaient le regard alors qu'une seule est
                          // l'action de l'écran. Se déconnecter devient
                          // secondaire — contour, pas aplat.
                          backgroundColor: AppTheme.card,
                          foregroundColor: AppTheme.ink,
                          elevation: 0,
                          side: const BorderSide(color: AppTheme.line),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                          ),
                        ),
                        onPressed: _signingOut ? null : _signOut,
                        child: _signingOut
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(t('sign_out_caps'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.red,
                          side: const BorderSide(color: AppTheme.red),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                          ),
                        ),
                        onPressed: _deleting ? null : _deleteAccount,
                        child: _deleting
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.red))
                            : Text(t('delete_account_caps'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                      ),
                    ),
                    const SizedBox(height: 26),
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

/// Photo de profil, avec sa pastille d'appareil photo.
///
/// La pastille est nécessaire : un rond avec une silhouette ne dit pas
/// qu'on peut le toucher. Elle porte aussi le libellé d'accessibilité,
/// parce qu'une icône seule n'est rien pour un lecteur d'écran.
class _AvatarPicker extends StatelessWidget {
  final String? url;
  final bool busy;
  final VoidCallback onTap;

  const _AvatarPicker({required this.url, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: 'Changer la photo de profil',
        child: GestureDetector(
          onTap: busy ? null : onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.panel,
                  border: Border.all(color: AppTheme.line, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: busy
                    ? const Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (url == null || url!.isEmpty)
                        ? const Icon(Icons.person_outline, size: 40, color: AppTheme.muted)
                        : AppImage(url: url, fit: BoxFit.cover, thumbnail: true),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.greenDeep,
                    border: Border.all(color: AppTheme.bg, width: 3),
                  ),
                  child: const Icon(Icons.photo_camera_outlined, size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
