import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_config.dart';
import 'image_compressor.dart';

/// URLs d'images (Supabase Storage ou Cloudflare R2) et upload de fichiers.
///
/// Travaille en octets (`Uint8List`), pas en `dart:io File` : ça marche à
/// l'identique sur mobile ET sur le web (le navigateur n'a pas de système
/// de fichiers, `flutter run -d chrome` a besoin de cette version).
///
/// Bascule entre Supabase et R2 pilotée par `AppConfig.useR2` — passée au
/// build (`--dart-define=USE_R2=true`), aucun code à modifier.
class StorageService {
  final SupabaseClient _client = Supabase.instance.client;

  /// URL publique d'un fichier d'un bucket public (product-images, shop-images, avatars).
  String publicUrl(String bucket, String path) {
    if (AppConfig.useR2 && AppConfig.r2PublicBaseUrl.isNotEmpty) {
      return '${AppConfig.r2PublicBaseUrl}/$path';
    }
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Chemin d'un fichier dans un bucket PUBLIC, préfixé par l'identifiant
  /// de la personne connectée : `<uid>/<nom du fichier>`.
  ///
  /// Ajouté le 5 septembre 2026 (audit demandé par Emina). Les photos de
  /// produit et de boutique étaient déposées à la racine du bucket
  /// (`<timestamp>.jpg`), et la règle de sécurité correspondante autorise
  /// n'importe quel compte connecté à écrire n'importe où dans ces deux
  /// buckets — autrement dit, un inconnu peut s'en servir comme
  /// hébergement de fichiers gratuit, sur le quota du projet.
  ///
  /// Ce préfixe est la moitié applicative du correctif : il ne change rien
  /// tant que la règle reste permissive, mais il permet de la resserrer
  /// (`(storage.foldername(name))[1] = auth.uid()::text`, comme le bucket
  /// `avatars` le fait déjà) sans casser l'envoi de photos — voir
  /// `supabase/securite_patch.sql`, partie 5. Les photos déjà envoyées ne
  /// bougent pas : leur URL complète est enregistrée en base.
  String ownedPath(String fileName) {
    final uid = _client.auth.currentUser?.id;
    return uid == null ? fileName : '$uid/$fileName';
  }

  /// Dépose un fichier dans un bucket public et renvoie son URL publique.
  ///
  /// **Deux versions sont envoyées depuis le 9 septembre 2026** (voir
  /// [ImageCompressor]) : la grande (1200 px, pour la fiche produit) et une
  /// vignette (500 px, pour les grilles et les avatars), nommée
  /// `<nom>_thumb.jpg` à côté de la première. C'est le principe du
  /// `srcset` des sites web : la bonne taille au bon endroit.
  ///
  /// C'est fait ICI, dans le service de stockage, plutôt que dans chaque
  /// formulaire : tous les envois en profitent — photo de boutique, photos
  /// de produit, catégories, bannières, collections — sans qu'on puisse en
  /// oublier un.
  ///
  /// L'URL renvoyée est TOUJOURS celle de la grande version : c'est elle
  /// qui est enregistrée en base. La vignette est retrouvée à l'affichage
  /// en dérivant son nom ([ImageCompressor.thumbUrlFor]).
  ///
  /// Si l'envoi de la vignette échoue, on n'échoue pas pour autant : la
  /// grande version suffit à faire fonctionner l'application.
  Future<String> uploadPublic({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final prepared = ImageCompressor.prepare(bytes, path);

    await _client.storage.from(bucket).uploadBinary(
          prepared.fileName,
          prepared.bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: prepared.changed ? 'image/jpeg' : contentType,
          ),
        );

    if (prepared.thumbBytes != null && prepared.thumbFileName != null) {
      try {
        await _client.storage.from(bucket).uploadBinary(
              prepared.thumbFileName!,
              prepared.thumbBytes!,
              fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
            );
      } catch (_) {
        // Sans vignette, l'affichage retombe sur la grande version.
      }
    }

    return publicUrl(bucket, prepared.fileName);
  }

  /// Dépose une capture de paiement dans le bucket privé `payment-proofs`,
  /// sous le dossier de l'utilisateur connecté (autorisation RLS).
  Future<String> uploadPaymentProof({
    required String userId,
    required String orderId,
    required Uint8List bytes,
    String extension = 'jpg',
  }) async {
    final path = '$userId/$orderId.$extension';
    await _client.storage.from('payment-proofs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// URL signée temporaire pour afficher une capture de paiement privée
  /// (le lecteur doit être autorisé par les policies RLS du bucket).
  Future<String> signedPaymentProofUrl(String path, {int expiresInSeconds = 3600}) {
    return _client.storage.from('payment-proofs').createSignedUrl(path, expiresInSeconds);
  }
}
