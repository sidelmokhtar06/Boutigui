import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import 'storage_service.dart';

/// Session, profil, rôle.
///
/// IMPORTANT : le rôle n'est JAMAIS lu depuis le jeton (les métadonnées du
/// jeton viennent du client, donc falsifiables). On relit toujours la
/// colonne `role` de `profiles` en base.
class AuthService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  Profile? _profile;
  bool _loading = true;

  StreamSubscription<AuthState>? _authSub;

  AuthService() {
    _authSub = _client.auth.onAuthStateChange.listen((_) => _syncProfile());
    _syncProfile();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Profile? get profile => _profile;
  bool get isLoading => _loading;
  bool get isLoggedIn => _client.auth.currentSession != null;
  User? get currentUser => _client.auth.currentUser;

  Future<void> _syncProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _profile = null;
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      final row = await _client.from('profiles').select().eq('id', user.id).single();
      _profile = Profile.fromMap(row);
    } catch (_) {
      _profile = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> refreshProfile() => _syncProfile();

  Future<String?> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      await _syncProfile();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      // Ajouté le 4 septembre 2026 : sans ce filet, une erreur qui n'est
      // pas une `AuthException` (ex. pas de connexion internet) remontait
      // telle quelle et faisait planter l'écran de connexion au lieu
      // d'afficher un message.
      debugPrint('Erreur de connexion : $e');
      return "Could not sign in. Check your internet connection and try again.";
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'phone': phone},
      );
      await _syncProfile();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Erreur d\'inscription : $e');
      return "Could not create the account. Check your internet connection and try again.";
    }
  }

  /// Connexion / inscription via Google — remplace le formulaire manuel
  /// "créer un compte" (retiré le 2 septembre 2026, à la demande d'Emina :
  /// une adresse e-mail saisie à la main n'est jamais vérifiée, alors que
  /// Google garantit que l'adresse existe vraiment). Sur le web, Supabase
  /// redirige le navigateur vers Google puis revient sur cette page ; la
  /// ligne `profiles` est créée automatiquement au premier retour par le
  /// même déclencheur que pour l'inscription par e-mail (voir
  /// `profiles_trigger_patch.sql`).
  ///
  /// Préalable côté Emina (ne peut pas être fait depuis ce code) : créer un
  /// identifiant OAuth dans Google Cloud Console, puis l'activer dans
  /// Supabase → Authentication → Sign In / Providers → Google.
  Future<String?> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? Uri.base.toString() : null,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Erreur de connexion Google : $e');
      return "Could not sign in with Google. Try again.";
    }
  }

  /// Renvoie le message de confirmation d'adresse (20 septembre 2026).
  ///
  /// Nécessaire dès lors que « Confirm email » est activé côté Supabase :
  /// sans ça, une personne qui a perdu ou supprimé le message n'a plus
  /// aucun moyen d'activer son compte depuis l'application.
  Future<String?> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Erreur de renvoi de confirmation : $e');
      return "Le message n'a pas pu être renvoyé. Vérifiez votre connexion.";
    }
  }

  /// Envoie une photo de profil et l'enregistre (21 septembre 2026).
  ///
  /// Le bucket `avatars` est PUBLIC en lecture mais n'accepte une écriture
  /// que dans le dossier de la personne connectée
  /// (`(storage.foldername(name))[1] = auth.uid()::text`, voir
  /// `marketplace_schema.sql`) — d'où [StorageService.ownedPath], qui
  /// préfixe le nom du fichier par l'identifiant. Sans ce préfixe, la
  /// règle refuse l'envoi.
  ///
  /// Le nom du fichier porte un horodatage : un navigateur qui a déjà mis
  /// l'ancienne photo en cache afficherait sinon l'ancienne indéfiniment,
  /// l'URL n'ayant pas changé.
  Future<String?> updateAvatar(Uint8List bytes, {String extension = 'jpg'}) async {
    final user = currentUser;
    if (user == null) return 'Not signed in';
    try {
      final storage = StorageService();
      final name = 'avatar-${DateTime.now().millisecondsSinceEpoch}.$extension';
      final url = await storage.uploadPublic(
        bucket: 'avatars',
        path: storage.ownedPath(name),
        bytes: bytes,
      );
      await _client.from('profiles').update({'avatar_url': url}).eq('id', user.id);
      await _syncProfile();
      return null;
    } catch (e) {
      debugPrint('Erreur d\'envoi de la photo de profil : $e');
      return "La photo n'a pas pu être envoyée. Vérifiez votre connexion.";
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _profile = null;
    notifyListeners();
  }

  Future<String?> updateProfile({
    String? fullName,
    String? phone,
    String? city,
    String? address,
    String? gender,
    String? avatarUrl,
  }) async {
    final user = currentUser;
    if (user == null) return 'Not signed in';
    try {
      await _client.from('profiles').update({
        if (fullName != null) 'full_name': fullName,
        if (phone != null) 'phone': phone,
        if (city != null) 'city': city,
        if (address != null) 'address': address,
        if (gender != null) 'gender': gender,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }).eq('id', user.id);
      await _syncProfile();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// "SUPPRIMER MON COMPTE" (écran Mon profil, 3 sept. 2026) — appelle la
  /// fonction SQL `delete_own_account()` (voir admin_patch.sql), qui
  /// supprime la ligne `auth.users` de l'utilisateur connecté ; `profiles`,
  /// `shops`, etc. suivent automatiquement via les `on delete cascade` déjà
  /// en place dans le schéma. Un utilisateur ne peut supprimer que son
  /// propre compte (la fonction utilise `auth.uid()`, jamais un id fourni
  /// par l'appelant).
  Future<String?> deleteAccount() async {
    if (currentUser == null) return 'Not signed in';
    try {
      await _client.rpc('delete_own_account');
      await _client.auth.signOut();
      _profile = null;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
