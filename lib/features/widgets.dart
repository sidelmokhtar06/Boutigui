import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../services/image_compressor.dart';
import '../services/location_service.dart';
import '../models/models.dart';

/// Image en cache avec état de chargement et image cassée gérés. Fond
/// blanc par défaut : sur la maquette l'app, les photos produit restent sur
/// une carte blanche même si le reste de l'app est en thème sombre.
class AppImage extends StatefulWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? radius;
  // Point de la photo à garder visible quand `fit` recadre l'image (ex.
  // BoxFit.cover) — choisi par la vendeuse (voir `Product.focalXAt`/
  // `focalYAt`, 5 septembre 2026, nuit). Centre par défaut, comme avant.
  final Alignment alignment;
  // Zoom EN PLUS du recadrage automatique de `fit` — 1.0 = pas de zoom
  // (voir `Product.zoomAt`, 5 septembre 2026). Un simple `Transform.scale`
  // au-dessus de l'image déjà recadrée : reste cohérent quel que soit le
  // format (largeur/hauteur) de la carte qui affiche cette photo, contrairement
  // à un recadrage en pixels figés une fois pour toutes. L'appelant (ex.
  // [ProductCard]) est déjà entouré d'un `ClipRRect` qui coupe le
  // débordement visuel du zoom.
  final double zoom;

  /// Utiliser la VIGNETTE (500 px) plutôt que la grande photo.
  ///
  /// Ajouté le 9 septembre 2026 : à mettre partout où la photo s'affiche
  /// petite — grilles de produits, listes, avatars de boutique. La fiche
  /// produit, elle, garde la grande version.
  ///
  /// Si la vignette n'existe pas (photo envoyée avant cette date), on
  /// retombe automatiquement sur la grande version : rien ne casse.
  final bool thumbnail;

  const AppImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius,
    this.alignment = Alignment.center,
    this.zoom = 1.0,
    this.thumbnail = false,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> with SingleTickerProviderStateMixin {
  // **Battement de dessin — 14 septembre 2026, QUATRIÈME correctif.**
  //
  // Historique complet de cette photo qui devient noire : mémoire (corrigé
  // le 9 puis le 13), course de décodage supposée (préchargement le 14,
  // sans effet), texture "oubliée" supposée (redessin par `setState()` vide
  // le 14, sans effet), puis `memCacheWidth`/`memCacheHeight` retirés
  // (bug moteur documenté flutter/flutter#160199, toujours sans effet —
  // reproduit même avec un `Image.network` tout nu, sans AUCUN réglage).
  //
  // Une recherche plus large a trouvé la vraie explication, côté
  // NAVIGATEUR cette fois, pas Flutter : un très ancien comportement connu
  // des moteurs WebGL (Chrome ET Firefox, documenté depuis 2013) — *"si
  // rien ne change à l'écran, aucun ordre de dessin n'est envoyé à la
  // carte graphique. Après quelques secondes sans nouvel ordre de dessin,
  // le navigateur VIDE le canevas. Dès qu'un nouvel ordre de dessin
  // arrive, l'image revient."* Une photo bien affichée puis JAMAIS
  // retouchée (pas d'animation, pas de scroll) ne redemande plus aucun
  // dessin — exactement notre cas.
  //
  // C'est aussi pourquoi le premier essai de redessin périodique (13
  // septembre, `setState(() {})` vide) n'a rien changé : Flutter est
  // justement assez malin pour remarquer qu'un `setState` qui ne change
  // RIEN à l'apparence ne mérite pas un nouveau dessin, et n'envoie donc
  // toujours aucun ordre à la carte graphique — la même optimisation qui
  // cause le bug côté navigateur agit aussi côté Flutter.
  //
  // Cette fois, un changement RÉEL (une opacité qui alterne entre 1.0 et
  // 0.999 — invisible à l'œil, 0,1 % de différence) force un vrai nouveau
  // dessin à chaque battement, sans jamais laisser trois secondes s'écouler
  // sans qu'un ordre de dessin parte vers la carte graphique.
  late final AnimationController _heartbeat;

  @override
  void initState() {
    super.initState();
    _heartbeat = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _heartbeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final width = widget.width;
    final height = widget.height;
    final fit = widget.fit;
    final alignment = widget.alignment;
    final zoom = widget.zoom;
    final radius = widget.radius;
    final thumbnail = widget.thumbnail;

    final placeholder = Container(
      width: width,
      height: height,
      color: AppTheme.imageBg,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: AppTheme.muted, size: (width ?? 40) * 0.4),
    );

    Widget child;
    if (url == null || url.isEmpty) {
      child = placeholder;
    } else {
      // Les photos sont compressées à l'envoi depuis le 9 septembre 2026
      // (1200 px pour la grande version, 500 px pour la vignette — voir
      // `image_compressor.dart`) : pas besoin de redemander une taille de
      // décodage plus petite ici (voir historique ci-dessus).
      final thumbUrl = thumbnail ? ImageCompressor.thumbUrlFor(url) : null;
      Widget network(String source, {Widget Function()? onError}) => CachedNetworkImage(
            imageUrl: source,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => onError == null ? placeholder : onError(),
          );
      child = thumbUrl == null || thumbUrl == url
          ? network(url)
          : network(thumbUrl, onError: () => network(url));
    }

    if (zoom != 1.0) {
      child = Transform.scale(scale: zoom, alignment: alignment, child: child);
    }

    if (radius != null) {
      child = ClipRRect(borderRadius: radius, child: child);
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _heartbeat,
        // `builder` (pas `child:`) : c'est justement le fait que cette
        // fonction soit rappelée à chaque tick, avec une vraie valeur qui
        // change, qui force le nouveau dessin recherché.
        builder: (context, _) => Opacity(
          opacity: 1.0 - (_heartbeat.value * 0.001),
          child: child,
        ),
      ),
    );
  }
}

/// Écran plein cadre permettant de choisir le point d'une photo qui doit
/// TOUJOURS rester visible, quelle que soit la carte où elle s'affiche
/// ensuite, et son zoom — ajouté le 5 septembre 2026 (nuit) pour les photos
/// produit d'une vendeuse (Emina : "le vendeur il peut contrôler la photo,
/// ce que le vendeur il veut apparaître pour le client", puis "ça reste un
/// problème que je ne peux pas zoomer ni dezoomer, [...] la point la plus
/// importante pour moi"), et déplacé ici (partagé, plus privé à
/// my_shop_screen.dart) le même soir pour être réutilisé côté admin par les
/// photos de CATÉGORIE (categories_admin_screen.dart — Emina : "l'admin il
/// peut contrôler le photo, soit couper une partie ou faire un zoom").
///
/// l'app affiche la même photo dans plusieurs cartes de formats différents
/// (grille, liste, fiche produit, bande de catégorie) — recadrer/couper
/// l'image une fois pour toutes ne conviendrait qu'à UN SEUL de ces formats
/// et couperait le sujet dans les autres. À la place, on fait glisser la
/// photo derrière un cadre fixe pour indiquer le point à garder visible ;
/// ce choix est stocké (pas de nouveaux pixels) et appliqué automatiquement
/// partout où la photo apparaît, quel que soit le format de la carte — voir
/// `Product.focalXAt`/`focalYAt`/`Category.focalX`/`focalY` (models.dart) et
/// `AppImage.alignment`/`zoom` ci-dessus.
///
/// [frameAspectRatio] : format du cadre de prévisualisation — 0.66 pour une
/// photo produit (carte grille), ~2.78 (1920x690) pour une photo de
/// catégorie ; par défaut 0.66.
///
/// Retourne un enregistrement `(focalX, focalY, zoom)` (fractions 0 à 1
/// pour le point, 1.0 à 3.0 pour le zoom) via `Navigator.pop`, ou `null` si
/// on annule.
class PhotoPositionScreen extends StatefulWidget {
  final Uint8List? bytes;
  final String? url;
  final double initialFocalX;
  final double initialFocalY;
  final double initialZoom;
  final double frameAspectRatio;

  const PhotoPositionScreen({
    super.key,
    this.bytes,
    this.url,
    this.initialFocalX = 0.5,
    this.initialFocalY = 0.5,
    this.initialZoom = 1.0,
    this.frameAspectRatio = 0.66,
  });

  static const double minZoom = 1.0;
  static const double maxZoom = 3.0;

  @override
  State<PhotoPositionScreen> createState() => _PhotoPositionScreenState();
}

class _PhotoPositionScreenState extends State<PhotoPositionScreen> {
  late double _focalX = widget.initialFocalX;
  late double _focalY = widget.initialFocalY;
  late double _zoom = widget.initialZoom;
  double _zoomAtGestureStart = 1.0;
  final _frameKey = GlobalKey();

  // Glisser (un doigt) ET pincer pour zoomer (deux doigts) utilisent tous
  // les deux la famille de gestes "scale" de Flutter — `onPanUpdate` et
  // `onScaleUpdate` sur un même `GestureDetector` entreraient en conflit,
  // donc glisser-seul est aussi géré ici via `onScaleUpdate`.
  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtGestureStart = _zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final box = _frameKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width == 0 || box.size.height == 0) return;
    setState(() {
      _zoom = (_zoomAtGestureStart * details.scale).clamp(PhotoPositionScreen.minZoom, PhotoPositionScreen.maxZoom);
      // Glisser la photo vers la droite doit révéler ce qui est à gauche
      // sur la photo — le point de référence se déplace donc dans le sens
      // opposé au doigt, comme déplacer une fenêtre sur une image fixe.
      // `focalPointDelta` : mouvement depuis le dernier appel (pas depuis
      // le début du geste), valable aussi bien pour un seul doigt (glisser)
      // que pour deux doigts (pincer + glisser en même temps).
      //
      // `* _zoom` : sans lui, glisser à vitesse de doigt constante
      // déplacerait TOUJOURS le point de référence de la même quantité,
      // quel que soit le zoom. Or `Transform.scale` n'agit que sur
      // l'affichage (pas sur la zone tactile du `GestureDetector`) : à
      // zoom x3, la photo affichée bouge 3x plus vite à l'écran que le
      // doigt ne bouge réellement. En divisant aussi par `_zoom`, le
      // déplacement du point de référence reste proportionnel à ce qui
      // bouge VISIBLEMENT à l'écran, quel que soit le niveau de zoom.
      _focalX = (_focalX - details.focalPointDelta.dx / (box.size.width * _zoom)).clamp(0.0, 1.0);
      _focalY = (_focalY - details.focalPointDelta.dy / (box.size.height * _zoom)).clamp(0.0, 1.0);
    });
  }

  void _reset() => setState(() {
        _focalX = 0.5;
        _focalY = 0.5;
        _zoom = 1.0;
      });

  @override
  Widget build(BuildContext context) {
    final alignment = Alignment(_focalX * 2 - 1, _focalY * 2 - 1);
    final rawImage = widget.bytes != null
        ? Image.memory(widget.bytes!, fit: BoxFit.cover, alignment: alignment)
        : AppImage(url: widget.url, fit: BoxFit.cover, alignment: alignment);
    final image = _zoom == 1.0 ? rawImage : Transform.scale(scale: _zoom, alignment: alignment, child: rawImage);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.white70, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Drag the photo, and pinch with two fingers to zoom in/out, to choose what should always stay visible, whatever card it appears on in the app.",
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.frameAspectRatio,
                  child: ClipRect(
                    key: _frameKey,
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: Colors.white54, width: 1)),
                      child: GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        child: image,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 10, 24, 4),
              child: Text(
                'Ce point et ce zoom restent identiques sur les autres formats de carte.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                  IconButton(onPressed: _reset, icon: const Icon(Icons.refresh, color: Colors.white70)),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop((_focalX, _focalY, _zoom)),
                    child: const Text('OK'),
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



/// Couleurs de dégradé pour l'avatar rond d'une boutique (initiales),
/// choisies de façon déterministe à partir du nom.
List<Color> shopGradient(String seed) {
  const palettes = [
    [Color(0xFFF17C6E), Color(0xFFD33A34)],
    [Color(0xFFC9A227), Color(0xFF7C5A12)],
    [Color(0xFF79B7A0), Color(0xFF2E6B57)],
    [Color(0xFF7FA8D9), Color(0xFF2F5B94)],
    [Color(0xFFE5A0B4), Color(0xFFB0577A)],
    [Color(0xFF8E7BC4), Color(0xFF4B3A85)],
    [Color(0xFFF0B67F), Color(0xFFC4731F)],
  ];
  final idx = seed.isEmpty ? 0 : seed.codeUnits.fold<int>(0, (a, b) => a + b) % palettes.length;
  return palettes[idx];
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

/// Carte produit — grille 2 colonnes, style l'app sombre : photo sur fond
/// blanc (avec un défilement de plusieurs images s'il y en a, comme sur la
/// maquette "Tous les produits"), coeur favori, nom de boutique (utilisé
/// comme ligne "marque" — l'app n'a pas de champ marque séparé), nom,
/// prix + bouton d'ajout rond blanc.
class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onAdd;
  // false sur la page d'une boutique (ShopDetailScreen) : répéter le nom de
  // la boutique sous chacun de ses propres produits, alors qu'on est déjà
  // sur sa page, n'apporte rien et charge inutilement l'écran (4 septembre
  // 2026).
  final bool showShopName;
  // Texte aligné à gauche plutôt que centré — capture Level envoyée par
  // Emina le 4 septembre 2026 (nuit), utilisée pour la nouvelle rangée de
  // produits de l'accueil ; par défaut centré, comme sur la maquette de référence
  // (correction pixel-exacte du 2 septembre), pour ne rien changer aux
  // écrans qui utilisaient déjà cette carte.
  final bool leftAlign;
  // En-tête vendeur AU-DESSUS de la photo — photo de la boutique, son nom,
  // et la mention "Boutique" en dessous (capture Oskelly "preloved /
  // Resale Store" envoyée par Emina le 6 septembre 2026 : "tu dois mettre
  // le profile pour les produits qui se trouve après la deuxième bannière
  // SEULEMENT"). Donc `false` par défaut : les cartes de l'accueil hors
  // collections, de la recherche, des favoris et de la page boutique ne
  // changent pas. Toucher cet en-tête ouvre la page de la boutique
  // ([onOpenShop]), séparément du reste de la carte qui ouvre le produit.
  final bool showSellerHeader;
  final VoidCallback? onOpenShop;
  // Ajoutés le 15 septembre 2026 pour le rail horizontal de la page
  // d'accueil (_ProductShowcaseRow), qui a son propre format de photo
  // (5:7, coins carrés) — voir la doc de ce widget. Par défaut inchangés,
  // donc les grilles existantes ne bougent pas.
  final double imageAspectRatio;
  final BorderRadius? borderRadius;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onAdd,
    this.showShopName = true,
    this.leftAlign = false,
    this.showSellerHeader = false,
    this.onOpenShop,
    // Spec unifiée du 15 septembre 2026 ("Tous les produits doivent
    // respecter [cette spec]") : ratio 472x661 = 0,714, coins carrés,
    // partout — plus seulement sur les rails horizontaux. Toujours
    // surchargeable (aucun appel existant n'a besoin de le faire).
    this.imageAspectRatio = 0.714,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  // `_pageController` retiré le 10 septembre 2026 avec le carrousel des
  // cartes produit (voir la note dans le build).

  @override
  Widget build(BuildContext context) {
    // Photo en plein cadre (BoxFit.cover, sans marge) depuis le 5 septembre
    // 2026 (nuit) — Emina, capture d'une carte où le coeur semblait flotter
    // au-dessus de la photo plutôt que posé dessus : "la coeur doit être
    // toujours sur la photo". Avant ce correctif, la photo était en
    // BoxFit.contain avec 8px de marge (façon catalogue), ce qui laissait
    // une bande blanche autour d'elle — le coeur (positionné par rapport à
    // la carte entière) tombait alors sur cette bande plutôt que sur
    // l'image elle-même. Coeur favori en simple contour (pas de bouton
    // d'ajout rond, pas de badge "stock faible"), puces de pagination
    // cuivre (#C4682F) quand plusieurs photos, puis texte marque / nom /
    // prix centrés en dessous.
    final product = widget.product;

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.showSellerHeader && (product.shopName ?? '').isNotEmpty) ...[
            _SellerMiniHeader(
              name: product.shopName!,
              logoUrl: product.shopLogoUrl,
              onTap: widget.onOpenShop,
            ),
            const SizedBox(height: 10),
          ],
          ClipRRect(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(AppTheme.radiusSmall),
            child: AspectRatio(
              aspectRatio: widget.imageAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppTheme.imageBg),
                  // **Une seule photo par carte — 10 septembre 2026.**
                  //
                  // Les cartes affichaient un carrousel : on pouvait faire
                  // défiler les photos du produit sans ouvrir sa fiche. Joli,
                  // mais très coûteux : un `PageView` garde les pages
                  // voisines en mémoire, donc une carte à 3 photos en
                  // décodait 2 ou 3 au lieu d'une. Avec une dizaine de
                  // cartes à l'écran, ça multipliait la mémoire graphique
                  // par trois — et c'est elle qui, saturée, fait dessiner du
                  // noir à la place des photos sur iPhone.
                  //
                  // Les autres photos restent visibles sur la fiche produit,
                  // en grand. C'est d'ailleurs ce que font Oskelly et
                  // Farfetch : une seule photo dans la grille.
                  AppImage(
                    url: product.coverImage,
                    fit: BoxFit.cover,
                    thumbnail: true,
                    alignment: Alignment(product.focalXAt(0) * 2 - 1, product.focalYAt(0) * 2 - 1),
                    zoom: product.zoomAt(0),
                  ),
                  if (widget.onToggleFavorite != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _HeartButton(isFavorite: widget.isFavorite, onTap: widget.onToggleFavorite!),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: widget.leftAlign ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                // Marque en gras/majuscules (le champ dédié si la vendeuse
                // l'a renseigné, sinon le nom de la boutique — voir
                // Product.brandLine, models.dart, ajouté le 5 septembre
                // 2026 nuit), puis nom du produit en poids normal SANS
                // majuscules — capture Level envoyée par Emina ("GUCCI" /
                // "Donna pumps") : jusque-là le nom du produit était aussi
                // mis en gras et en majuscules, ce qui confondait les deux
                // lignes, et seul le nom de la boutique existait comme
                // "marque".
                // Quand l'en-tête vendeur est affiché au-dessus de la
                // photo, on ne répète la ligne "marque" que si la vendeuse
                // a vraiment renseigné une marque : sans ça, le nom de la
                // boutique (utilisé par défaut comme marque) apparaîtrait
                // deux fois sur la même carte. Sur la capture de
                // référence, l'en-tête ("preloved") et la marque ("HERMES
                // PRE-OWNED") sont bien deux choses différentes.
                if (widget.showShopName &&
                    product.brandLine.isNotEmpty &&
                    (!widget.showSellerHeader || (product.brand ?? '').isNotEmpty))
                  Text(
                    product.brandLine.toUpperCase(),
                    maxLines: 1,
                    textAlign: widget.leftAlign ? TextAlign.left : TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.productBrand,
                  ),
                const SizedBox(height: 8),
                Text(
                  product.name,
                  maxLines: 1,
                  textAlign: widget.leftAlign ? TextAlign.left : TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.productName,
                ),
                const SizedBox(height: 8),
                _PriceRow(product: product, leftAlign: widget.leftAlign),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne de prix — prix normal seul, ou (en promotion) prix barré en gris +
/// prix réduit + pourcentage en rouge, façon Farfetch.
class _PriceRow extends StatelessWidget {
  final Product product;
  final bool leftAlign;

  const _PriceRow({required this.product, this.leftAlign = false});

  @override
  Widget build(BuildContext context) {
    if (!product.isOnSale) {
      return Text(
        Money.format(product.price),
        textAlign: leftAlign ? TextAlign.left : TextAlign.center,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppTheme.ink),
      );
    }
    // Corrigé le 15 septembre 2026 (photo de référence) : deux lignes, pas
    // une seule — le prix barré seul sur la première, le nouveau prix ET
    // le pourcentage ensemble sur la seconde, tous les deux en noir (pas
    // de rouge sur le pourcentage).
    return Column(
      crossAxisAlignment: leftAlign ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Money.format(product.compareAtPrice!),
          textAlign: leftAlign ? TextAlign.left : TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppTheme.muted, decoration: TextDecoration.lineThrough),
        ),
        Text(
          '${Money.format(product.price)} -${product.discountPercent}%',
          textAlign: leftAlign ? TextAlign.left : TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink),
        ),
      ],
    );
  }
}

class _HeartButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;

  const _HeartButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            isFavorite ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
            size: 20,
            color: isFavorite ? AppTheme.red : const Color(0xFF111111),
          ),
        ),
      ),
    );
  }
}

/// Petit avatar rond d'une boutique (logo si dispo, sinon initiales en
/// dégradé) — utilisé par [ProductFeedCard] et réutilisable ailleurs.
class ShopAvatar extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final double size;

  const ShopAvatar({super.key, required this.name, this.logoUrl, this.size = 22});

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return AppImage(url: logoUrl, width: size, height: size, thumbnail: true, radius: BorderRadius.circular(size / 2));
    }
    final grad = shopGradient(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(_initials(name), style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

/// Carte "fil de produits" — façon Oskelly : le nom + logo de la boutique
/// au-dessus de chaque carte produit (au lieu d'une simple liste de
/// boutiques). Remplace l'ancien onglet "Boutiques" depuis le 3 septembre
/// 2026 (demande d'Emina : "lister les produits de cette façon avec le
/// profil de la boutique, ensuite on peut cliquer sur la boutique pour voir
/// leur produit"). Le nom de la boutique n'est plus répété dans la carte
/// (il est déjà dans l'en-tête), contrairement à [ProductCard].
class ProductFeedCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onShopTap;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final double imageAspectRatio;
  final BorderRadius? borderRadius;

  const ProductFeedCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onShopTap,
    this.isFavorite = false,
    this.onToggleFavorite,
    // Même spec unifiée que ProductCard — voir sa doc.
    this.imageAspectRatio = 0.714,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  State<ProductFeedCard> createState() => _ProductFeedCardState();
}

class _ProductFeedCardState extends State<ProductFeedCard> {
  // `_pageController` retiré le 10 septembre 2026 avec le carrousel des
  // cartes produit (voir la note dans le build).

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.onShopTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                ShopAvatar(name: product.shopName ?? '', logoUrl: product.shopLogoUrl),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    product.shopName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: widget.borderRadius ?? BorderRadius.circular(AppTheme.radiusSmall),
                child: AspectRatio(
                aspectRatio: widget.imageAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: AppTheme.imageBg),
                    // Plein cadre depuis le 5 septembre 2026 (nuit) — même
                    // correctif que ProductCard : voir sa doc plus haut
                    // ("la coeur doit être toujours sur la photo").
                    // Une seule photo ici aussi — voir la note dans
                    // ProductCard (10 septembre 2026).
                    AppImage(
                      url: product.coverImage,
                      fit: BoxFit.cover,
                      thumbnail: true,
                      alignment: Alignment(product.focalXAt(0) * 2 - 1, product.focalYAt(0) * 2 - 1),
                      zoom: product.zoomAt(0),
                    ),
                    if (widget.onToggleFavorite != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _HeartButton(isFavorite: widget.isFavorite, onTap: widget.onToggleFavorite!),
                      ),
                  ],
                ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    // Marque en gras/majuscules PUIS nom en poids normal —
                    // 15 septembre 2026, pour retrouver exactement la même
                    // hiérarchie que [ProductCard] (et la capture Net-a-
                    // Porter envoyée par Emina) : avant, cette carte-ci
                    // n'affichait que le nom du produit, en gras et en
                    // majuscules, sans jamais montrer la marque séparément.
                    if (product.brandLine.isNotEmpty) ...[
                      Text(
                        product.brandLine.toUpperCase(),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.productBrand,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      product.name,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.productName,
                    ),
                    const SizedBox(height: 8),
                    _PriceRow(product: product),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Carte boutique — liste horizontale, style l'app : logo initiales en
/// dégradé, nom, tags, ville, chevron, sur fond panneau sombre.
class ShopCard extends StatelessWidget {
  final Shop shop;
  final VoidCallback onTap;
  final String? tags;

  const ShopCard({super.key, required this.shop, required this.onTap, this.tags});

  @override
  Widget build(BuildContext context) {
    final grad = shopGradient(shop.name);
    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              shop.logoUrl != null && shop.logoUrl!.isNotEmpty
                  ? AppImage(url: shop.logoUrl, width: 58, height: 58, thumbnail: true, radius: BorderRadius.circular(17))
                  : Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(shop.name),
                        style: AppTheme.brand(size: 20, color: Colors.white),
                      ),
                    ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.25, color: AppTheme.ink),
                    ),
                    if (tags != null && tags!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(tags!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                    ],
                    if (shop.city != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.muted),
                          const SizedBox(width: 3),
                          Text(shop.city!, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// En-tête vendeur d'une carte produit — photo ronde de la boutique, son
/// nom en gras, "Boutique" en gris juste en dessous.
///
/// Reproduit la capture Oskelly du 6 septembre 2026 ("preloved / Resale
/// Store" au-dessus de chaque photo). l'app n'a pas de type de vendeur
/// (particulier / professionnel / dépôt-vente) : la deuxième ligne est
/// donc toujours "Boutique", plutôt qu'une information inventée.
///
/// Toucher cet en-tête ouvre la page de la boutique — le reste de la carte
/// continue d'ouvrir le produit.
class _SellerMiniHeader extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final VoidCallback? onTap;

  const _SellerMiniHeader({required this.name, this.logoUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // `behavior` : sans lui, seules les zones réellement peintes de la
      // ligne (la photo, les lettres) recevraient le toucher — pas les
      // espaces entre les deux.
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShopAvatar(name: name, logoUrl: logoUrl, size: 30),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink),
                ),
                const Text(
                  'Boutique',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Teintes proposées à la vendeuse quand elle décrit les variantes d'un
/// produit (6 septembre 2026, captures "Concealer Color" / "Lipliner
/// color"). Volontairement centrée sur les teintes de maquillage — fonds
/// de teint, anticernes, lèvres — plus quelques couleurs franches pour le
/// reste du catalogue.
///
/// Une liste fermée plutôt qu'un sélecteur libre : des teintes cohérentes
/// entre les boutiques donnent un rendu plus propre qu'un dégradé où
/// chacune choisit une nuance légèrement différente.
/// Teintes proposées à la vendeuse pour décrire les variantes d'un produit.
///
/// **Refaite le 10 septembre 2026.** Emina : "enlève la fonctionnalité de
/// mettre le nom de chaque teinte / augmente les teintes — dégradés de
/// rose, dégradés de fond de teint, et les autres teintes courantes du
/// maquillage et de la maroquinerie".
///
/// Chaque teinte porte donc son nom ICI, une fois pour toutes. La vendeuse
/// n'a plus rien à taper : elle touche les carrés qu'elle vend, et le nom
/// suit automatiquement. C'est lui qui apparaîtra dans la commande, pour
/// qu'elle sache quelle teinte préparer.
///
/// C'était aussi la cause d'un vrai bug : une teinte ajoutée sans nom était
/// filtrée à l'enregistrement, donc invisible côté cliente — qui ne pouvait
/// alors rien sélectionner, ni ajouter au panier.
class Swatch {
  final String name;
  final String hex;
  const Swatch(this.name, this.hex);
}

const List<Swatch> kSwatchPalette = [
  // --- Fond de teint et anticernes (du plus clair au plus foncé)
  Swatch('Porcelain', '#F7E7DA'),
  Swatch('Ivory', '#F2DCC8'),
  Swatch('Light beige', '#EBD0B7'),
  Swatch('Beige', '#E2BFA1'),
  Swatch('Sand', '#D9AE8B'),
  Swatch('Honey', '#CE9A73'),
  Swatch('Golden', '#C08A5F'),
  Swatch('Caramel', '#B0764C'),
  Swatch('Hazelnut', '#9C6440'),
  Swatch('Cinnamon', '#8A5334'),
  Swatch('Mocha', '#75432B'),
  Swatch('Chocolate', '#5E3422'),
  Swatch('Espresso', '#4A2819'),
  Swatch('Ebony', '#361C12'),

  // --- Roses
  Swatch('Pale pink', '#F6D5DA'),
  Swatch('Powder pink', '#EFBFC8'),
  Swatch('Soft pink', '#E8A6B4'),
  Swatch('Bright pink', '#DE8398'),
  Swatch('Indian pink', '#D06A83'),
  Swatch('Fuchsia', '#C44D74'),
  Swatch('Raspberry', '#B03A60'),
  Swatch('Rosy plum', '#96335A'),

  // --- Lèvres : rouges, nudes, bruns
  Swatch('Rosy nude', '#D9A79C'),
  Swatch('Beige nude', '#C99483'),
  Swatch('Brown nude', '#B57B66'),
  Swatch('Coral', '#E9705C'),
  Swatch('Light red', '#D9534F'),
  Swatch('Red', '#C62F32'),
  Swatch('Deep red', '#A81F26'),
  Swatch('Burgundy', '#8C1D2C'),
  Swatch('Brick', '#9E4034'),
  Swatch('Terracotta', '#B25A43'),
  Swatch('Rosy brown', '#A5685F'),
  Swatch('Brown', '#7E4A3E'),
  Swatch('Plum', '#6E2D45'),
  Swatch('Aubergine', '#4E2036'),

  // --- Fards à paupières et couleurs franches
  Swatch('Champagne', '#E8D3B5'),
  Swatch('Bronze', '#A9743B'),
  Swatch('Copper', '#B5622C'),
  Swatch('Gold', '#D4AF37'),
  Swatch('Silver', '#C0C0C0'),
  Swatch('Taupe', '#8B7B6B'),
  Swatch('Khaki', '#6E6B4A'),
  Swatch('Green', '#2E9C5B'),
  Swatch('Emerald', '#1E7A5A'),
  Swatch('Turquoise', '#00A9A5'),
  Swatch('Sky blue', '#7FB3E3'),
  Swatch('Blue', '#1F4FD8'),
  Swatch('Midnight blue', '#1B2A5B'),
  Swatch('Purple', '#8E44AD'),
  Swatch('Lavender', '#B9A7DA'),
  Swatch('Yellow', '#F2C94C'),
  Swatch('Orange', '#EE6C2B'),

  // --- Maroquinerie et accessoires
  Swatch('Black', '#000000'),
  Swatch('White', '#FFFFFF'),
  Swatch('Cream', '#F3EDE3'),
  Swatch('Grey', '#8E8E8E'),
  Swatch('Charcoal grey', '#4A4A4A'),
  Swatch('Camel', '#C19A6B'),
  Swatch('Cognac', '#9A5B33'),
  Swatch('Dark burgundy', '#5E1F28'),
  Swatch('Navy', '#1F2A44'),
  Swatch('Nude', '#D8C3AC'),
];

/// Nom d'une teinte à partir de son code, pour l'afficher dans une
/// commande. Renvoie le code lui-même si la teinte ne fait pas partie de la
/// palette (photo importée d'une version précédente).
String swatchName(String hex) {
  final clean = hex.toUpperCase();
  for (final s in kSwatchPalette) {
    if (s.hex.toUpperCase() == clean) return s.name;
  }
  return hex;
}

/// Convertit `#RRGGBB` en couleur affichable. Tolérante : une valeur
/// abîmée ou vide renvoie un gris neutre plutôt que de faire planter
/// l'écran d'une cliente.
Color hexToColor(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return const Color(0xFFCCCCCC);
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return const Color(0xFFCCCCCC);
  return Color(0xFF000000 | value);
}

/// Rapport largeur/hauteur à donner à une case de grille de produits.
///
/// **Corrigé le 6 septembre 2026** : les grilles utilisaient un rapport
/// FIXE (0,62), calculé une fois à l'œil. Or la hauteur réelle d'une carte
/// ne suit pas sa largeur de la même façon : la photo, elle, garde son
/// format (0,66), mais les trois lignes de texte en dessous — marque, nom,
/// prix — occupent une hauteur CONSTANTE, quelle que soit la largeur de la
/// case. Sur un téléphone étroit, la place laissée au texte devenait donc
/// presque nulle, et le nom des produits se retrouvait coupé ou recouvert
/// par la rangée suivante — exactement ce qu'Emina a photographié sur la
/// page d'une boutique.
///
/// Ici, la hauteur est calculée : photo (largeur ÷ 0,66) + la place qu'il
/// faut vraiment au texte. Le rapport s'adapte donc à la largeur réelle de
/// la case, sur n'importe quel écran.
double productGridAspectRatio(double cellWidth, {bool withSellerHeader = false, double imageRatio = 0.714}) {
  // 90 au lieu de 82 (15 septembre 2026) : le prix sur deux lignes (prix
  // barré + nouveau prix/pourcentage) prend un peu plus de hauteur que
  // l'ancienne ligne unique.
  const textHeight = 90.0; // marque + nom + prix + espacements
  const headerHeight = 50.0; // photo ronde de la boutique + 2 lignes
  final height = cellWidth / imageRatio + textHeight + (withSellerHeader ? headerHeight : 0);
  return cellWidth / height;
}

/// Ancienneté d'une boutique, en français — "depuis 3 ans et 2 mois sur
/// l'app", façon "3 years, 3 months on OSKELLY" des captures de référence.
///
/// Partagé (5 septembre 2026) entre la page boutique
/// (shop_detail_screen.dart, qui le préfixe de "Boutique • ") et le bloc
/// vendeur de la fiche produit (product_screen.dart, qui l'affiche tel
/// quel sous le nom de la boutique) — une seule formulation, calculée
/// depuis la vraie date de création de la boutique.
String shopTenureLabel(DateTime createdAt) {
  final now = DateTime.now();
  var months = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
  if (now.day < createdAt.day) months -= 1;
  if (months <= 0) return 'less than a month';
  if (months < 12) return months == 1 ? '1 month' : '$months months';
  final years = months ~/ 12;
  final rem = months % 12;
  final yearsLabel = years > 1 ? '$years years' : '1 year';
  if (rem == 0) return yearsLabel;
  return '$yearsLabel $rem ${rem > 1 ? 'months' : 'month'}';
}

/// État vide générique (liste vide, pas de résultats).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.muted),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink), textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: const TextStyle(color: AppTheme.muted), textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;
  final String? subtitle;

  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.seeAllLabel = '',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.45, color: AppTheme.ink)),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
              ],
            ),
          ),
          if (onSeeAll != null)
            InkWell(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  seeAllLabel,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.ink, letterSpacing: 0.6, decoration: TextDecoration.underline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StarRating extends StatelessWidget {
  final double rating;
  final double size;

  const StarRating({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(filled ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: AppTheme.amber);
      }),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  final String status;
  final String label;

  const OrderStatusChip({super.key, required this.status, required this.label});

  Color _color() {
    switch (status) {
      case 'delivered':
        return const Color(0xFF57BB7E);
      case 'cancelled':
        return AppTheme.red;
      case 'confirmed':
      case 'preparing':
      case 'delivering':
        return AppTheme.stockWarn;
      default:
        return AppTheme.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Champ de recherche arrondi style l'app (fond panneau sombre, icône
/// appareil photo optionnelle à droite — comme sur la maquette Accueil).
class AppSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCameraTap;
  final Widget? trailing;
  // Réglages d'apparence, ajoutés le 5 septembre 2026 pour l'en-tête de
  // l'onglet Catégories (Emina : "à la place du photo 1 tu dois essayer
  // exactement la photo 2 même couleur"). Les valeurs par défaut sont
  // EXACTEMENT celles d'avant, donc l'accueil et les autres écrans qui
  // utilisent ce champ ne bougent pas d'un pixel.
  final Color? fillColor;
  final Color? iconColor;
  final Color? hintColor;
  final double height;
  final double radius;
  final double fontSize;
  final double iconSize;

  const AppSearchField({
    super.key,
    this.controller,
    required this.hint,
    this.onSubmitted,
    this.onChanged,
    this.onCameraTap,
    this.trailing,
    this.fillColor,
    this.iconColor,
    this.hintColor,
    this.height = 46,
    this.radius = 14,
    this.fontSize = 14.5,
    this.iconSize = 19,
  });

  @override
  Widget build(BuildContext context) {
    // Reproduit exactement `.search` de la maquette de référence : fond #383838,
    // rayon 14, icône loupe + champ + séparateur vertical + icône appareil
    // photo (pas de bordure, contrairement aux autres champs de l'app).
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: fillColor ?? AppTheme.searchFill,
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          Icon(Icons.search, size: iconSize, color: iconColor ?? AppTheme.searchPlaceholder),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              style: TextStyle(fontSize: fontSize, color: AppTheme.ink),
              decoration: InputDecoration(
                filled: false,
                hintText: hint,
                hintStyle: TextStyle(fontSize: fontSize, color: hintColor ?? AppTheme.searchPlaceholder),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          if (onCameraTap != null) ...[
            const SizedBox(width: 11),
            Container(width: 1, height: 22, color: AppTheme.searchSep),
            const SizedBox(width: 11),
            InkWell(
              onTap: onCameraTap,
              child: const Icon(Icons.camera_alt_outlined, size: 21, color: AppTheme.ink),
            ),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Recherche d'adresse façon "Google Maps" (15 septembre 2026, demande
/// explicite) — utilisée à la fois par la cliente au moment de payer
/// (cart_screen.dart) et par la vendeuse pour le point de collecte de sa
/// boutique (my_shop_screen.dart). Une recherche à la fois (pas de
/// suggestions à chaque frappe) : voir `LocationService.searchPlaces` pour
/// pourquoi (pas d'API Google Maps dans ce projet).
class PlaceSearchField extends StatefulWidget {
  final ValueChanged<PlaceResult> onSelected;
  final String hintText;

  const PlaceSearchField({
    super.key,
    required this.onSelected,
    this.hintText = 'Search for an address or place',
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _controller = TextEditingController();
  final _location = LocationService();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _location.searchPlaces(query);
      if (!mounted) return;
      setState(() => _loading = false);
      if (results.isEmpty) {
        setState(() => _error = 'No results. Try a more specific address.');
        return;
      }
      final chosen = await showModalBottomSheet<PlaceResult>(
        context: context,
        backgroundColor: AppTheme.card,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          top: false,
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.hair),
            itemBuilder: (context, i) => ListTile(
              leading: const Icon(Icons.place_outlined, color: AppTheme.ink2),
              title: Text(results[i].label, style: const TextStyle(fontSize: 13.5, color: AppTheme.ink)),
              onTap: () => Navigator.of(context).pop(results[i]),
            ),
          ),
        ),
      );
      if (chosen != null) widget.onSelected(chosen);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    onPressed: _search,
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(fontSize: 12, color: AppTheme.red)),
        ],
      ],
    );
  }
}

/// Carte de catégorie — photo au-dessus, nom en dessous, dans un cadre
/// arrondi. Ajoutée le 20 septembre 2026.
///
/// Partagée entre l'accueil (petites cellules, trois ou quatre par rangée)
/// et l'onglet Catégories (grandes cartes, deux par rangée) pour qu'une
/// catégorie ait la MÊME apparence partout. Avant, l'accueil n'en montrait
/// aucune et l'onglet Catégories utilisait de larges bandes pleine largeur
/// avec le nom posé par-dessus la photo — donc deux traitements sans
/// rapport pour un même objet.
///
/// Le cadrage de la photo ([Category.focalX] / [focalY] / [zoom]) est
/// respecté : ces valeurs sont réglées à la main depuis le site admin et
/// les ignorer décadrerait des photos déjà ajustées.
///
/// [category] à `null` produit la case « Plus » qui termine une grille
/// tronquée.
class CategoryCard extends StatelessWidget {
  final Category? category;
  final VoidCallback onTap;

  /// Format de la photo. 1 pour les petites cellules de l'accueil, plus
  /// large (4/3) pour les grandes cartes de l'onglet Catégories.
  final double imageAspectRatio;

  /// Libellé de la case « Plus ».
  final String moreLabel;

  const CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
    this.imageAspectRatio = 1,
    this.moreLabel = 'Plus',
  });

  @override
  Widget build(BuildContext context) {
    final cat = category;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        decoration: BoxDecoration(
          color: cat == null ? AppTheme.greenTint : AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppTheme.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: imageAspectRatio,
              child: cat == null
                  ? const Center(child: Icon(Icons.add, size: 24, color: AppTheme.green))
                  : (cat.imageUrl == null || cat.imageUrl!.isEmpty)
                      ? const ColoredBox(
                          color: AppTheme.panel,
                          child: Center(
                            child: Icon(Icons.category_outlined,
                                size: 22, color: AppTheme.muted),
                          ),
                        )
                      : AppImage(
                          url: cat.imageUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment(cat.focalX * 2 - 1, cat.focalY * 2 - 1),
                          zoom: cat.zoom,
                        ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Text(
                cat?.name ?? moreLabel,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: cat == null ? AppTheme.green : AppTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
