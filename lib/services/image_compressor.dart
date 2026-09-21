import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Compression des photos AVANT envoi — 9 septembre 2026.
///
/// **Le problème qu'elle résout.** Une fois le site publié, les photos
/// devenaient noires au bout d'une minute sur iPhone, et partiellement sur
/// ordinateur. Cause : chaque photo était stockée et affichée à sa taille
/// d'origine — 3000 à 5000 pixels de côté, plusieurs mégaoctets — alors
/// qu'elle s'affiche dans une carte de 170 points de large. Le navigateur
/// finit par manquer de mémoire graphique et rend des rectangles noirs.
///
/// Réduire la taille fait passer une photo d'environ 5 Mo à 200 Ko, sans
/// différence visible à l'écran. Trois problèmes réglés d'un coup :
///
///  - la mémoire du téléphone, donc les rectangles noirs ;
///  - le temps de chargement — un accueil de 18 Mo est inaccessible hors
///    de Nouakchott, quel que soit le serveur ;
///  - la facture Supabase, dont l'egress est facturé.
///
/// **Deux tailles par photo, comme tous les sites e-commerce.** Une seule
/// taille ne peut pas convenir partout : la fiche produit affiche la photo
/// en pleine largeur, la grille l'affiche dans une carte six fois plus
/// petite. Envoyer la grande image à la grille, c'est décoder six fois trop
/// de pixels — et c'est ça qui sature la mémoire du téléphone, plus encore
/// que le poids du fichier. On prépare donc :
///
///  - la grande version (1200 px) pour la fiche produit ;
///  - une vignette (500 px) pour les grilles, les listes et les avatars.
///
/// C'est le principe du `srcset` des sites web : la bonne taille au bon
/// endroit.
///
/// **Format de sortie : JPEG.** Pas WebP, bien qu'il soit plus efficace :
/// la bibliothèque `image` sait lire le WebP mais pas l'écrire. L'écart
/// avec un JPEG bien compressé est faible.
///
/// **Attention aux photos DÉJÀ envoyées** : elles restent lourdes. Voir
/// `supabase/recompresser_photos.py` pour les traiter en une fois.
class ImageCompressor {
  /// Grande version — celle de la fiche produit, affichée en pleine
  /// largeur. 1200 px correspond exactement à ce qu'affiche un téléphone
  /// moderne en plein écran (393 points × 3 de densité = 1179 pixels) :
  /// au-delà, aucun pixel supplémentaire n'est visible.
  static const int maxWidth = 1200;
  static const int quality = 82;

  /// Vignette — celle des grilles et des listes. Une carte produit fait
  /// environ 170 points de large, soit 510 pixels réels sur un écran de
  /// densité 3. 500 px est donc la taille juste : plus petit, ça pixelise ;
  /// plus grand, on décode pour rien.
  static const int thumbWidth = 500;
  static const int thumbQuality = 78;

  /// Suffixe du fichier vignette. `photo.jpg` → `photo_thumb.jpg`.
  static const String thumbSuffix = '_thumb';

  static const int _skipUnderBytes = 60 * 1024;

  /// Prépare les deux versions d'une photo.
  ///
  /// **Ne lève jamais** : si le format n'est pas reconnu, les octets
  /// d'origine sont renvoyés tels quels — mieux vaut une photo lourde
  /// qu'une vendeuse bloquée.
  static PreparedImage prepare(Uint8List bytes, String fileName) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return PreparedImage(bytes: bytes, fileName: fileName, changed: false);
      }

      final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;

      final large = decoded.width > maxWidth
          ? img.copyResize(decoded, width: maxWidth, interpolation: img.Interpolation.average)
          : decoded;
      var mainBytes = Uint8List.fromList(img.encodeJpg(large, quality: quality));
      var mainName = '$base.jpg';

      // Une photo déjà bien optimisée peut ressortir plus lourde après
      // réencodage : dans ce cas on garde l'originale telle quelle.
      final keepOriginal = mainBytes.length >= bytes.length && bytes.length <= _skipUnderBytes;
      if (keepOriginal) {
        mainBytes = bytes;
        mainName = fileName;
      }

      final small = decoded.width > thumbWidth
          ? img.copyResize(decoded, width: thumbWidth, interpolation: img.Interpolation.average)
          : decoded;
      final thumbBytes = Uint8List.fromList(img.encodeJpg(small, quality: thumbQuality));

      return PreparedImage(
        bytes: mainBytes,
        fileName: mainName,
        changed: !keepOriginal,
        thumbBytes: thumbBytes,
        thumbFileName: '$base$thumbSuffix.jpg',
      );
    } catch (_) {
      return PreparedImage(bytes: bytes, fileName: fileName, changed: false);
    }
  }

  /// URL de la vignette correspondant à une photo, ou `null` si le nom ne
  /// s'y prête pas.
  ///
  /// Les photos envoyées AVANT le 9 septembre 2026 n'ont pas de vignette :
  /// l'URL construite ici ne mènera à rien. C'est prévu — [AppImage]
  /// retombe alors sur la photo d'origine, sans rien casser à l'écran.
  static String? thumbUrlFor(String url) {
    final cut = url.lastIndexOf('.');
    if (cut <= 0 || url.length - cut > 6) return null;
    if (url.substring(0, cut).endsWith(thumbSuffix)) return url;
    return '${url.substring(0, cut)}$thumbSuffix.jpg';
  }
}

/// Les deux versions prêtes à envoyer.
class PreparedImage {
  final Uint8List bytes;
  final String fileName;
  final bool changed;
  final Uint8List? thumbBytes;
  final String? thumbFileName;

  const PreparedImage({
    required this.bytes,
    required this.fileName,
    required this.changed,
    this.thumbBytes,
    this.thumbFileName,
  });
}
