import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/money.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/cart_controller.dart';
import '../../services/catalog_service.dart';
import '../auth/login_screen.dart';
import '../shell.dart';
import '../shops/shop_detail_screen.dart';
import '../widgets.dart';

/// Fiche produit — refaite le 5 septembre 2026, capture Aquazzura (Level)
/// envoyée par Emina : "quand je clique sur un produit exactement la photo
/// 5". Correspondance avec la capture, élément par élément (pour que
/// chaque écart soit clair et vite corrigeable si mal deviné) :
///
///  - Flèche retour superposée sur la photo -> gardée (icône partager
///    retirée le 15 septembre 2026, demande explicite : "l'option
///    partager tu dois le supprimer de toute l'application").
///  - Badge "★ NEW" -> remplacé par un badge "PROMO" (déjà utilisé sur les
///    cartes produit, [Product.isOnSale]) — le badge "NOUVEAU" a lui aussi
///    été retiré le 15 septembre 2026 (demande explicite), pas de note "★"
///    séparée, l'app affiche déjà une vraie note (étoiles + nombre d'avis)
///    plus bas, pas la peine de la dupliquer en badge.
///  - "AQUAZZURA" (marque) -> nom de la boutique, en gras/majuscules,
///    touchable (ouvre sa page) : l'app n'a pas de champ "marque" séparé,
///    la boutique en tient lieu partout ailleurs (cartes produit, etc).
///  - "Crystal Lover 75 mules" (nom, poids normal) -> nom du produit, MÊME
///    traitement que sur les cartes produit (voir widgets.dart, corrigé le
///    même soir : poids normal, pas de majuscules).
///  - Prix + "VAT INCLUDED" -> prix seul : l'app ne facture pas de TVA,
///    afficher cette mention serait faux.
///  - Badge "MUSE" + points de fidélité + "Learn more" -> RETIRÉ : l'app n'a
///    pas de programme de fidélité/points. Personne ne triche là-dessus.
///  - "Size EU" + grille de tailles + "Size Guide" -> LA vraie demande de ce
///    retour (numéro 4) : un choix d'option dépendant du produit (taille
///    pour une chaussure, couleur pour du maquillage, ...), voir
///    [Product.optionName]/[optionValues] (models.dart) et le nouveau champ
///    du formulaire vendeuse (my_shop_screen.dart). Pas de "Size Guide" :
///    aucun contenu de ce genre n'existe dans l'app, afficherait un lien
///    mort.
///  - "Fits true to size, take your normal size" -> retiré (même raison :
///    rien en base pour étayer cette phrase pour un vrai produit l'app).
///  - "Same-day delivery to Dubai" -> remplacé par la même mention que
///    partout ailleurs dans l'app ([Strings.delivery_agreed]) : chaque
///    boutique convient de sa propre livraison sur WhatsApp, pas de
///    livraison le jour même garantie par l'app.
///  - Bouton "ADD TO BAG" plein largeur, noir -> gardé, avec le sélecteur de
///    quantité déjà existant à côté (fonctionnalité qui existait déjà avant
///    ce retour, pas retirée).
///
/// Bloc vendeur — refait le 5 septembre 2026 d'après la capture Oskelly
/// "About the Product" envoyée par Emina ("quand je clique sur un produit
/// je peux savoir le vendeur exactement de cette façon photo 2"). Le tour
/// précédent utilisait une [ShopCard] générique (logo, nom, ville,
/// chevron) : ça ne ressemblait pas à la capture. Correspondance, élément
/// par élément, avec les tailles mesurées sur l'image (largeur de
/// référence 1179 px, soit 393 pt) :
///
///  - titre "About the Product" (corps ~20, gras) -> "À propos du produit"
///  - photo ronde de la boutique, ~62 pt -> [ShopAvatar] taille 62
///  - "preloved" en gras ~17 -> nom de la boutique, touchable (ouvre sa
///    page, comme le demandait le tour précédent)
///  - "3 years, 3 months on OSKELLY" en gris -> ancienneté réelle,
///    calculée depuis la date de création de la boutique ([shopTenureLabel])
///  - bouton "Follow" gris à droite -> vrai bouton Suivre/Suivi(e) (table
///    `favorite_shops`, déjà utilisée sur la page boutique) — masqué si
///    c'est la vendeuse qui regarde son propre produit
///  - le texte de description juste en dessous -> description du produit,
///    déplacée ici (elle était plus bas, sous un titre "Description")
///  - "Show Translation" -> RETIRÉ : l'app n'a pas de traduction
///    automatique, ce lien ne mènerait nulle part
///  - bande grise "Delivery from Estonia" -> RETIRÉE. Elle existait sous
///    forme d'un widget `_DeliveryBand`, supprimé le 21 septembre 2026
///    (audit) : plus aucun écran ne l'affichait depuis un remaniement non
///    daté, `flutter analyze` la signalait comme code mort.
///  - bouton "Write to the seller" -> bouton pleine largeur qui ouvre
///    WhatsApp avec la boutique (remplace l'ancien bouton "Contacter sur
///    WhatsApp" plus discret)
class _SellerSection extends StatelessWidget {
  final Shop shop;
  final String? description;
  final bool isOwner;
  final bool isFollowing;
  final VoidCallback onToggleFollow;

  const _SellerSection({
    required this.shop,
    required this.description,
    required this.isOwner,
    required this.isFollowing,
    required this.onToggleFollow,
  });

  void _openShop(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About this product',
          // 15 septembre 2026, deuxième passage : remis en gras (w700) —
          // seule la taille (17px) et l'absence d'espacement de lettres
          // restent de la première demande.
          style: AppTheme.system(size: 17, weight: FontWeight.w700, letterSpacing: 0),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => _openShop(context),
              customBorder: const CircleBorder(),
              child: ShopAvatar(name: shop.name, logoUrl: shop.logoUrl, size: 62),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: InkWell(
                onTap: () => _openShop(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.ink),
                    ),
                    if (shop.createdAt != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        shopTenureLabel(shop.createdAt!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppTheme.muted),
                      ),
                    ] else if (shop.city != null && shop.city!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        shop.city!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppTheme.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!isOwner) ...[
              const SizedBox(width: 10),
              _FollowButton(isFollowing: isFollowing, onTap: onToggleFollow),
            ],
          ],
        ),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 18),
          // Zone grise sans bordure, coins carrés (15 septembre 2026,
          // deuxième passage : "border radius = 0") + règles de police
          // exactes : Helvetica Neue, 18px, Regular, #222222.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.zero),
            child: Text(
              description!,
              style: AppTheme.system(size: 18, weight: FontWeight.w400, color: const Color(0xFF222222), height: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bouton "Follow" de la capture : rectangle gris clair, coins légèrement
/// arrondis, texte sombre en gras. Passe en bordure simple une fois la
/// boutique suivie, pour que les deux états se distinguent.
class _FollowButton extends StatelessWidget {
  final bool isFollowing;
  final VoidCallback onTap;

  const _FollowButton({required this.isFollowing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.transparent : AppTheme.panel,
          border: Border.all(color: isFollowing ? AppTheme.line : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isFollowing ? t('shop_following') : t('shop_follow'),
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.ink),
        ),
      ),
    );
  }
}

/// Bouton "Write to the seller" de la capture : pleine largeur, fond gris
/// clair, texte sombre en gras et centré.
class _WriteToSellerButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _WriteToSellerButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(12)),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink),
          ),
        ),
      ),
    );
  }
}
class ProductScreen extends StatefulWidget {
  final String productId;

  const ProductScreen({super.key, required this.productId});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final _catalog = CatalogService();
  final _imageController = PageController();
  late Future<_ProductData> _future;
  int _quantity = 1;
  int _imagePage = 0;
  bool _isFavorite = false;
  String? _selectedOption;
  String? _optionError;
  // Bouton "Follow" du bloc vendeur (5 septembre 2026) — même
  // fonctionnalité que celui de la page boutique (table `favorite_shops`).
  String? _shopId;
  bool _isFollowingShop = false;
  bool _followBusy = false;
  // Avis après achat (15 septembre 2026, demande explicite) — non-null
  // seulement si le compte connecté a une commande contenant ce produit
  // sans avis déjà déposé pour elle (voir
  // `CatalogService.fetchReviewableOrderId`) : c'est ce qui décide si
  // "Write a review" s'affiche.
  String? _reviewableOrderId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  /// **Corrigé le 9 septembre 2026.** La fiche produit affichait "Rien à
  /// afficher pour le moment" pour un visiteur NON CONNECTÉ, alors que le
  /// produit existait bien : une seule des requêtes secondaires échouait
  /// (les avis vont chercher le nom de leur auteur dans la table des
  /// profils, que seul un compte connecté a le droit de lire), et tout
  /// l'écran tombait avec elle.
  ///
  /// Le produit et sa boutique sont le strict nécessaire. Tout le reste —
  /// avis, favoris, abonnement — est accessoire : si l'un échoue, la page
  /// s'affiche quand même, simplement sans cette partie. C'est le principe
  /// à appliquer partout où une donnée dépend d'être connecté.
  Future<_ProductData> _load() async {
    final product = await _catalog.fetchProduct(widget.productId);
    final shop = product == null ? null : await _catalog.fetchShop(product.shopId);
    _shopId = shop?.id;

    List<Review> reviews = const [];
    try {
      reviews = await _catalog.fetchReviews(widget.productId);
    } catch (e) {
      debugPrint('avis non chargés: $e');
    }

    try {
      final favorites = await _catalog.fetchFavoriteProductIds();
      _isFavorite = favorites.contains(widget.productId);
    } catch (e) {
      debugPrint('favoris non chargés: $e');
    }

    if (shop != null) {
      try {
        _isFollowingShop = await _catalog.isFollowingShop(shop.id);
      } catch (e) {
        debugPrint('abonnement non chargé: $e');
      }
    }

    try {
      _reviewableOrderId = await _catalog.fetchReviewableOrderId(widget.productId);
    } catch (e) {
      debugPrint('commande éligible à un avis non vérifiée: $e');
    }

    return _ProductData(product: product, shop: shop, reviews: reviews);
  }

  /// Rouvre juste les avis + l'éligibilité "Write a review" après un dépôt
  /// d'avis — pas la peine de tout recharger (produit, boutique...).
  Future<void> _refreshReviews() async {
    try {
      final reviews = await _catalog.fetchReviews(widget.productId);
      final reviewableOrderId = await _catalog.fetchReviewableOrderId(widget.productId);
      if (!mounted) return;
      final current = await _future;
      setState(() {
        _reviewableOrderId = reviewableOrderId;
        _future = Future.value(_ProductData(product: current.product, shop: current.shop, reviews: reviews));
      });
    } catch (_) {
      // Rien de grave : l'avis est bien déposé, il apparaîtra à la
      // prochaine ouverture de la fiche si l'actualisation échoue ici.
    }
  }

  Future<void> _openWriteReview(String orderId, String productId) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WriteReviewSheet(catalog: _catalog, productId: productId, orderId: orderId),
    );
    if (submitted == true) await _refreshReviews();
  }

  /// Suivre / ne plus suivre la boutique depuis la fiche produit. L'état
  /// est basculé tout de suite à l'écran puis remis en arrière si la base
  /// refuse — même comportement que sur la page boutique.
  Future<void> _toggleFollowShop() async {
    final shopId = _shopId;
    if (shopId == null || _followBusy) return;
    _requireLogin(() async {
      final next = !_isFollowingShop;
      setState(() {
        _isFollowingShop = next;
        _followBusy = true;
      });
      try {
        await _catalog.toggleFollowShop(shopId, next);
      } catch (e) {
        if (!mounted) return;
        setState(() => _isFollowingShop = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<SettingsController>().t('error_generic'))),
        );
      } finally {
        if (mounted) setState(() => _followBusy = false);
      }
    });
  }

  void _requireLogin(VoidCallback action) {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    action();
  }

  Future<void> _toggleFavorite() async {
    _requireLogin(() async {
      setState(() => _isFavorite = !_isFavorite);
      await _catalog.toggleFavoriteProduct(widget.productId, _isFavorite);
    });
  }

  void _addToCart(Product product) {
    if (product.hasOptions && _selectedOption == null) {
      setState(() => _optionError = '${product.optionName} — choose an option before adding to bag.');
      return;
    }
    // Plafonné au stock (15 septembre 2026, demande explicite) — voir
    // `CartController.add`, qui renvoie `true` si la quantité a dû être
    // réduite (le vendeur a moins d'unités que ce qui est déjà dans le
    // sac + ce qu'on essaie d'ajouter).
    final capped = context.read<CartController>().add(product, quantity: _quantity, selectedOption: _selectedOption);
    if (capped) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only ${product.stock} in stock — your bag was adjusted to what\'s available.')),
      );
      return;
    }
    // Fenêtre "Added to your bag" (15 septembre 2026, demande explicite,
    // même mise en page que la capture de référence : photo, nom, option
    // choisie, prix, puis un bouton "Go to bag") — remplace l'ancien
    // SnackBar, qui ne laissait pas la possibilité d'aller directement au
    // sac.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddedToBagSheet(product: product, option: _selectedOption),
    );
  }

  Future<void> _openWhatsapp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Même geste "partager" que la page boutique (5 septembre 2026) — pas de
  // lien web réel vers une fiche produit à partager, donc un message copié
  // dans le presse-papiers plutôt qu'un faux lien.
  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FutureBuilder<_ProductData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          final product = data?.product;
          if (product == null) {
            // On distingue maintenant les deux cas, qui affichaient le même
            // message jusqu'ici : un produit qui n'existe plus, et une
            // requête qui a échoué. Sans ça, impossible de comprendre ce
            // qui se passe depuis un téléphone.
            return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                icon: Icons.error_outline,
                title: snapshot.hasError ? t('error_generic') : t('no_results'),
                subtitle: snapshot.hasError ? snapshot.error.toString() : null,
              ),
            );
          }
          final shop = data!.shop;
          final avgRating = data.reviews.isEmpty
              ? 0.0
              : data.reviews.fold<int>(0, (sum, r) => sum + r.rating) / data.reviews.length;
          final images = product.imageUrls.isEmpty ? const <String?>[null] : product.imageUrls;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _ProductImageHeader(
                  images: images,
                  controller: _imageController,
                  page: _imagePage,
                  onPageChanged: (i) => setState(() => _imagePage = i),
                  onBack: () => Navigator.of(context).maybePop(),
                  isFavorite: _isFavorite,
                  onToggleFavorite: _toggleFavorite,
                  isOnSale: product.isOnSale,
                  isNew: product.isNew,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Marque (champ dédié si la vendeuse l'a renseigné,
                      // sinon le nom de la boutique — voir Product.brandLine,
                      // ajouté le 5 septembre 2026 nuit), touchable : ouvre
                      // toujours la page de la boutique, marque ou non.
                      if (shop != null && product.brandLine.isNotEmpty)
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id)),
                          ),
                          child: Text(
                            product.brandLine,
                            style: AppTheme.system(size: 19, weight: FontWeight.w400, color: const Color(0xFF1A1A1A)),
                          ),
                        ),
                      // Espacements au pixel près, demande explicite du 15
                      // septembre 2026 (photo de référence) : 5 px entre la
                      // marque et la description, 3 px entre la description
                      // et le prix — beaucoup plus serré que le reste de
                      // l'app, exprès pour cette fiche produit.
                      //
                      // **Tailles réduites le même jour, deuxième passage**
                      // (30/20/26 → 19/14/17) : la première mesure, prise
                      // sur une photo de référence à une échelle différente
                      // de l'écran réel, donnait un texte bien plus grand
                      // qu'attendu une fois affiché — remonté avec une
                      // comparaison photo à photo ("l'écriture est très
                      // grand... il doit être très petit").
                      const SizedBox(height: 5),
                      Text(
                        product.name,
                        style: AppTheme.system(size: 14, weight: FontWeight.w400, color: const Color(0xFF1A1A1A)),
                      ),
                      const SizedBox(height: 3),
                      if (product.isOnSale)
                        // Même mise en page que _PriceRow (widgets.dart, 15
                        // septembre 2026, photo de référence) : deux
                        // lignes, prix barré seul puis nouveau prix +
                        // pourcentage ensemble, tous les deux en noir.
                        //
                        // **Police changée le 15 septembre 2026, deuxième
                        // passage** ("essaie de changer le font du prix
                        // avec un font adaptant") : le prix repasse sur la
                        // police par défaut de l'app (Figtree — voir
                        // `ThemeData.fontFamily` dans core/theme.dart), qui
                        // s'adapte à toutes les tailles déjà utilisées
                        // ailleurs dans l'app, plutôt que la police système
                        // Apple utilisée pour la marque/description
                        // juste au-dessus.
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              Money.format(product.compareAtPrice!),
                              style: const TextStyle(fontSize: 12, color: AppTheme.muted, decoration: TextDecoration.lineThrough),
                            ),
                            Text(
                              '${Money.format(product.price)} -${product.discountPercent}%',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                            ),
                          ],
                        )
                      else
                        Text(
                          Money.format(product.price),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                        ),
                      if (data.reviews.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          StarRating(rating: avgRating),
                          const SizedBox(width: 6),
                          Text('(${data.reviews.length})', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                        ]),
                      ],
                      if (product.hasOptions) ...[
                        const SizedBox(height: 22),
                        _OptionPicker(
                          label: product.optionName!,
                          // En mode couleur, les teintes font foi : c'est
                          // `optionColors` qui compte, `optionValues` n'en
                          // est que le nom (10 septembre 2026).
                          values: product.optionType == 'color' && product.optionValues.length != product.optionColors.length
                              ? [for (final hex in product.optionColors) swatchName(hex)]
                              : product.optionValues,
                          colors: product.optionColors,
                          soldOut: product.optionSoldOut,
                          isColor: product.optionType == 'color',
                          selected: _selectedOption,
                          onSelect: (v) {
                            setState(() {
                              _selectedOption = v;
                              _optionError = null;
                            });
                            // Couleur choisie → photo assortie (15
                            // septembre 2026, demande explicite : "quand
                            // un client clique sur une couleur, il voie
                            // directement la photo correspondante").
                            // Hypothèse par défaut, sans réglage
                            // supplémentaire côté vendeuse : les photos
                            // sont dans le même ordre que les couleurs —
                            // ne bouge rien si les deux listes n'ont pas
                            // la même taille (pas de correspondance fiable
                            // possible).
                            if (product.optionType == 'color') {
                              final displayValues = product.optionValues.length == product.optionColors.length
                                  ? product.optionValues
                                  : [for (final hex in product.optionColors) swatchName(hex)];
                              final idx = displayValues.indexOf(v);
                              if (idx >= 0 && idx < product.imageUrls.length) {
                                _imageController.animateToPage(
                                  idx,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOut,
                                );
                              }
                            }
                          },
                        ),
                        if (_optionError != null) ...[
                          const SizedBox(height: 8),
                          Text(_optionError!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red)),
                        ],
                      ],
                      const SizedBox(height: 26),
                    ],
                  ),
                ),
              ),
              // ---------------------------------------------- Bloc vendeur
              // Disposition de la capture Oskelly envoyée par Emina le 5
              // septembre 2026 : titre "À propos du produit", photo ronde
              // de la boutique + nom + ancienneté + bouton Suivre, puis la
              // description juste en dessous (voir [_SellerSection]).
              if (shop != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                    child: _SellerSection(
                      shop: shop,
                      description: product.description,
                      isOwner: context.watch<AuthService>().currentUser?.id == shop.ownerId,
                      isFollowing: _isFollowingShop,
                      onToggleFollow: _toggleFollowShop,
                    ),
                  ),
                ),
              // Bande "Agreed with each store" retirée le 15 septembre
              // 2026 (demande explicite, photo de référence). `_DeliveryBand`
              // reste défini plus haut au cas où une autre bande de ce
              // type serait utile ailleurs, simplement plus appelée ici.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "Write to the seller" de la capture — ouvre WhatsApp
                      // avec la boutique (remplace l'ancien petit bouton
                      // "Contacter sur WhatsApp").
                      if (shop != null && shop.whatsappPhone != null && shop.whatsappPhone!.isNotEmpty) ...[
                        _WriteToSellerButton(
                          label: t('write_to_seller'),
                          onTap: () => _openWhatsapp(shop.whatsappPhone!),
                        ),
                        const SizedBox(height: 26),
                      ],
                      // Filet de sécurité : si la boutique n'a pas pu être
                      // chargée, la description n'a pas été affichée dans le
                      // bloc vendeur — on la montre ici pour qu'elle ne
                      // disparaisse jamais complètement.
                      if (shop == null && product.description != null && product.description!.isNotEmpty) ...[
                        Text(t('description'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                        const SizedBox(height: 6),
                        Text(product.description!, style: const TextStyle(fontSize: 14, color: AppTheme.ink, height: 1.45)),
                        const SizedBox(height: 26),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Text(t('reviews'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                          ),
                          // "Write a review" (15 septembre 2026, demande
                          // explicite) — visible UNIQUEMENT si le compte a
                          // une commande éligible pour ce produit ; la base
                          // refuserait de toute façon l'écriture sinon (voir
                          // supabase/reviews_patch_purchase_required.sql),
                          // mais autant ne pas montrer un bouton qui
                          // échouerait à coup sûr.
                          if (_reviewableOrderId != null)
                            TextButton(
                              onPressed: () => _openWriteReview(_reviewableOrderId!, product.id),
                              child: const Text('Write a review'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (data.reviews.isEmpty)
                        Text(t('no_results'), style: const TextStyle(color: AppTheme.muted, fontSize: 13))
                      else
                        ...data.reviews.map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(r.authorName ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.ink)),
                                    const SizedBox(width: 8),
                                    StarRating(rating: r.rating.toDouble(), size: 14),
                                  ]),
                                  if (r.comment != null && r.comment!.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(r.comment!, style: const TextStyle(fontSize: 13, color: AppTheme.ink2)),
                                  ],
                                ],
                              ),
                            )),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<_ProductData>(
        future: _future,
        builder: (context, snapshot) {
          final product = snapshot.data?.product;
          if (product == null) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: AppTheme.line), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        SizedBox(width: 20, child: Text('$_quantity', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink))),
                        IconButton(
                          onPressed: _quantity < product.stock ? () => setState(() => _quantity++) : null,
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: product.stock <= 0 ? null : () => _addToCart(product),
                      child: Text(t('add_to_cart').toUpperCase(), style: const TextStyle(letterSpacing: 0.6)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bloc image en haut de la fiche — carrousel + flèche retour et coeur
/// favori superposés directement sur la photo. Bouton "partager" retiré le
/// 15 septembre 2026 (demande explicite : "l'option partager tu dois le
/// supprimer de toute l'application").
class _ProductImageHeader extends StatelessWidget {
  final List<String?> images;
  final PageController controller;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBack;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool isOnSale;
  final bool isNew;

  const _ProductImageHeader({
    required this.images,
    required this.controller,
    required this.page,
    required this.onPageChanged,
    required this.onBack,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.isOnSale,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // Rapport ≈0,94 (15 septembre 2026, mesure précise sur photo de
      // référence : zone image ≈432×460) — remplace 0,82, qui rendait la
      // photo trop haute/étroite par rapport à la référence.
      aspectRatio: 0.94,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppTheme.imageBg),
          PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemCount: images.length,
            itemBuilder: (context, i) => AppImage(url: images[i], fit: BoxFit.contain),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            child: _RoundIconButton(icon: Icons.arrow_back, onTap: onBack),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: _RoundIconButton(
              icon: isFavorite ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
              onTap: onToggleFavorite,
              color: isFavorite ? AppTheme.red : AppTheme.ink,
            ),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 14,
              left: 16,
              right: 16,
              // Traits égaux plutôt que des points (15 septembre 2026,
              // demande explicite avec photo de référence : "il doit être
              // sous forme des lignes... au lieu de des points") — chaque
              // segment prend une largeur égale grâce à `Expanded`, comme
              // sur la photo de référence, au lieu de puces rondes de
              // tailles différentes.
              child: Row(
                children: List.generate(images.length, (i) {
                  final on = i == page;
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.only(right: i == images.length - 1 ? 0 : 5),
                      decoration: BoxDecoration(
                        color: on ? AppTheme.ink : AppTheme.pagerOff,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _RoundIconButton({required this.icon, required this.onTap, this.color = AppTheme.ink});

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, size: 19, color: color);
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: child,
        ),
      ),
    );
  }
}

/// Sélecteur d'option — puces à choix unique, façon "Size EU" de la
/// capture Aquazzura mais avec un libellé libre (voir doc de la classe
/// [ProductScreen]) : "Taille" avec des tailles, "Couleur" avec des teintes,
/// ou tout autre libellé choisi par la vendeuse.
/// Choix d'une variante — taille (texte) ou teinte (carré de couleur).
///
/// Le mode couleur a été ajouté le 6 septembre 2026, d'après les captures
/// "Concealer Color" / "Lipliner color" envoyées par Emina : carrés
/// arrondis alignés, nom de la teinte sous la rangée une fois choisie, et
/// **trait en diagonale sur les teintes épuisées** — visibles mais non
/// commandables, exactement comme sur ses captures.
class _OptionPicker extends StatelessWidget {
  final String label;
  final List<String> values;
  final List<String> colors;
  final List<bool> soldOut;
  final bool isColor;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _OptionPicker({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.colors = const [],
    this.soldOut = const [],
    this.isColor = false,
  });

  bool _isSoldOut(int i) => i < soldOut.length && soldOut[i];

  @override
  Widget build(BuildContext context) {
    // Puces (couleur) inchangées ; le choix "texte" (tailles, la plupart du
    // temps) passe par un champ façon menu déroulant depuis le 15
    // septembre 2026, demande explicite avec photo de référence — plus
    // proche de ce qu'on voit sur les sites de mode haut de gamme qu'une
    // rangée de puces.
    if (isColor) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              if (selected != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: AppTheme.ink2),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < values.length; i++)
                _Swatch(
                  hex: i < colors.length ? colors[i] : '#CCCCCC',
                  selected: values[i] == selected,
                  soldOut: _isSoldOut(i),
                  onTap: _isSoldOut(i) ? null : () => onSelect(values[i]),
                ),
            ],
          ),
        ],
      );
    }
    return _SizeDropdownField(
      label: label,
      values: values,
      soldOut: soldOut,
      selected: selected,
      onSelect: onSelect,
    );
  }
}

/// Champ "Select your size" — remplace la rangée de puces pour les options
/// textuelles (tailles, essentiellement). Ouvre une feuille avec la liste
/// complète au lieu d'un `Wrap` de puces, plus proche des sites de mode de
/// référence envoyés le 15 septembre 2026.
class _SizeDropdownField extends StatelessWidget {
  final String label;
  final List<String> values;
  final List<bool> soldOut;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SizeDropdownField({
    required this.label,
    required this.values,
    required this.soldOut,
    required this.selected,
    required this.onSelect,
  });

  bool _isSoldOut(int i) => i < soldOut.length && soldOut[i];

  Future<void> _openPicker(BuildContext context) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select your ${label.toLowerCase()}',
                      style: AppTheme.system(size: 17, weight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22, color: AppTheme.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.hair),
                itemBuilder: (context, i) {
                  final isSoldOut = _isSoldOut(i);
                  final isSelected = values[i] == selected;
                  return ListTile(
                    enabled: !isSoldOut,
                    title: Text(
                      values[i],
                      style: AppTheme.system(
                        size: 15,
                        weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        color: isSoldOut ? AppTheme.muted : AppTheme.ink,
                      ).copyWith(decoration: isSoldOut ? TextDecoration.lineThrough : null),
                    ),
                    trailing: isSelected ? const Icon(Icons.check, size: 18, color: AppTheme.ink) : null,
                    onTap: isSoldOut ? null : () => Navigator.of(context).pop(values[i]),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (chosen != null) onSelect(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected != null && selected!.isNotEmpty;
    return InkWell(
      onTap: () => _openPicker(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.ink, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasSelection ? selected! : 'Select your ${label.toLowerCase()}',
                overflow: TextOverflow.ellipsis,
                style: AppTheme.system(
                  size: 15,
                  weight: FontWeight.w400,
                  color: hasSelection ? AppTheme.ink : AppTheme.ink2,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 22, color: AppTheme.ink),
          ],
        ),
      ),
    );
  }
}

/// Carré de couleur. Le trait en diagonale marque une teinte épuisée.
class _Swatch extends StatelessWidget {
  final String hex;
  final bool selected;
  final bool soldOut;
  final VoidCallback? onTap;

  const _Swatch({required this.hex, required this.selected, required this.soldOut, this.onTap});

  @override
  Widget build(BuildContext context) {
    // **Zone de toucher élargie le 10 septembre 2026.** Emina : "je ne peux
    // pas cliquer sur une teinte". Le carré faisait 46 points mais collait
    // à ses voisins ; `behavior: opaque` et le rembourrage autour rendent
    // le toucher fiable même à côté du carré. La sélection est aussi
    // beaucoup plus visible : anneau sombre épais et coche, au lieu d'une
    // bordure de 2 points invisible sur une teinte foncée.
    //
    // **Réduit de 46 à 30 points le 15 septembre 2026** (demande explicite,
    // photo de référence à l'appui : "le size est trop grand") — 46 points
    // dépassait largement la taille des puces de couleur des sites de
    // référence (~28-32 pt). La zone de toucher réelle reste large grâce
    // au `Padding` + `HitTestBehavior.opaque` ci-dessous, donc réduire le
    // visuel ne redonne pas le problème du 10 septembre.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: hexToColor(hex),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppTheme.ink : AppTheme.line,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: soldOut
              ? const CustomPaint(painter: _SoldOutLinePainter())
              : (selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white, shadows: [Shadow(blurRadius: 4)])
                  : null),
        ),
      ),
    );
  }
}

/// Le trait des captures : une diagonale sombre en travers du carré.
class _SoldOutLinePainter extends CustomPainter {
  const _SoldOutLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3D3D3D)
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(size.width * 0.12, size.height * 0.12), Offset(size.width * 0.88, size.height * 0.88), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
/// Fenêtre de dépôt d'avis — étoiles + commentaire facultatif (15
/// septembre 2026, demande explicite). N'apparaît que depuis un bouton
/// déjà gardé par [_ProductScreenState._reviewableOrderId] ; la base
/// revérifie de toute façon l'achat de son côté (voir
/// `supabase/reviews_patch_purchase_required.sql`).
class _WriteReviewSheet extends StatefulWidget {
  final CatalogService catalog;
  final String productId;
  final String orderId;

  const _WriteReviewSheet({required this.catalog, required this.productId, required this.orderId});

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  int _rating = 5;
  final _comment = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.catalog.createReview(
        productId: widget.productId,
        orderId: widget.orderId,
        rating: _rating,
        comment: _comment.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Write a review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 30,
                      color: i <= _rating ? AppTheme.ink : AppTheme.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Share a few words about this product (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.red, fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit review'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductData {
  final Product? product;
  final Shop? shop;
  final List<Review> reviews;

  _ProductData({required this.product, required this.shop, required this.reviews});
}

/// Fenêtre "Added to your bag" — voir [_ProductScreenState._addToCart].
/// Mise en page calquée sur la capture de référence (photo à gauche,
/// nom + marque + option + prix à droite, puis un bouton "Go to bag" pleine
/// largeur qui ferme la fenêtre et bascule directement sur l'onglet Bag).
class _AddedToBagSheet extends StatelessWidget {
  final Product product;
  final String? option;

  const _AddedToBagSheet({required this.product, required this.option});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final brand = (product.brand?.isNotEmpty ?? false) ? product.brand! : (product.shopName ?? '');
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('added_to_bag_title'),
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppTheme.ink),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22, color: AppTheme.ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppImage(
                    url: product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (brand.isNotEmpty)
                        Text(brand.toUpperCase(), style: AppTheme.productBrand),
                      const SizedBox(height: 3),
                      Text(product.name, style: AppTheme.productName.copyWith(fontSize: 14)),
                      if (option != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '${product.optionName ?? 'Option'} $option',
                          style: const TextStyle(fontSize: 13, color: AppTheme.ink2),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(Money.format(product.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((r) => r.isFirst);
                Shell.navKey.currentState?.goToBag();
              },
              child: Text(t('go_to_bag').toUpperCase(), style: const TextStyle(letterSpacing: 0.6)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('keep_shopping'), style: const TextStyle(color: AppTheme.ink2)),
            ),
          ],
        ),
      ),
    );
  }
}
