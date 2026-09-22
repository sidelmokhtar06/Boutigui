import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../../services/notification_service.dart';
import '../notifications/notifications_screen.dart';
import '../product/product_screen.dart';
import '../products/all_products_screen.dart';
import '../profile/favorites_screen.dart';
import '../shops/shop_detail_screen.dart';
import '../widgets.dart';

/// Écran Accueil — façon Level / Oskelly / Farfetch (captures d'Emina).
/// Revu le 4 septembre 2026 (nuit), PUIS corrigé le même soir, plus tard :
/// le premier essai avait mis la barre de statut ET le bandeau "New in /
/// cœur / recherche" sur un fond blanc uni, séparés de la photo — Emina a
/// renvoyé exactement la même capture Level ("Women", caniche) en précisant
/// "Ce que je veux la photo 2 / Ce que tu as fait la photo 1" : sur cette
/// capture, l'heure/batterie ET le bandeau sont bien SUPERPOSÉS en blanc
/// directement sur la photo, qui commence tout en haut de l'écran (pas de
/// bande blanche du tout). C'est ce que fait maintenant [_PromoBanner], qui
/// intègre le bandeau superposé (voir sa doc). Elle est aussi beaucoup plus
/// grande (quasi plein écran). Juste en dessous : des PRODUITS à la place
/// des catégories, INCHANGÉ depuis le 4 septembre 2026 ([_ProductShowcaseRow]
/// — Emina a confirmé le 5 septembre 2026, nuit, qu'il ne fallait PAS le
/// supprimer : "tu as supprimé ce qui est avant [...] il doit être comme ça
/// après ces produits il doit être un nouveau bannière", après une première
/// tentative erronée qui l'avait remplacé). Puis, APRÈS cette rangée : des
/// "Collections" gérées par l'admin (bannière secondaire + produits choisis,
/// voir [_CollectionSection]) — qui remplacent l'ancienne rangée titrée
/// "Nouveautés" (Emina : "enlevé (nouveauté) [...] pour mettre une nouvelle
/// bannière"). Ensuite, inchangé : "Réductions", façon Oskelly.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _catalog = CatalogService();
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final products = await _catalog.fetchProducts();
    final favorites = await _catalog.fetchFavoriteProductIds();
    final banners = await _catalog.fetchActiveBanners();
    final discounted = await _catalog.fetchDiscountedProducts();
    // "Collections" — remplace l'ancienne rangée sans titre juste sous la
    // bannière (5 septembre 2026, nuit — Emina : "enlevé [ce qui est] après
    // juste la bannière pour mettre une nouvelle bannière [...] Les produits
    // sont présentés de cette manière exactement mais vers le bas"). Gérées
    // depuis le site admin (Collections) : chacune choisit sa propre photo,
    // son titre, un sous-titre optionnel, et soit une catégorie précise soit
    // "tous mélangés", avec un nombre de produits au choix de l'admin.
    final collections = await _catalog.fetchHomeCollections();
    final collectionProducts = <String, List<Product>>{};
    for (final c in collections) {
      // Plafonné à 8 quel que soit le réglage de l'admin (10 septembre
      // 2026) : chaque produit affiché est une photo décodée en mémoire, et
      // c'est leur NOMBRE simultané qui sature un iPhone. Au-delà de huit,
      // on remplit la page sans rien apporter — la cliente passe par
      // "Tout voir" pour la suite.
      final limit = c.productLimit > 8 ? 8 : c.productLimit;
      collectionProducts[c.id] = await _catalog.fetchCollectionProducts(categoryId: c.categoryId, limit: limit);
    }
    return _HomeData(
      products: products,
      favoriteIds: favorites,
      banners: banners,
      discounted: discounted,
      collections: collections,
      collectionProducts: collectionProducts,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _openSearch(String query) {
    if (query.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AllProductsScreen(search: query.trim())),
    );
  }

  Future<void> _openSearchSheet() async {
    final controller = TextEditingController();
    final t = context.read<SettingsController>().t;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
        child: AppSearchField(
          controller: controller,
          hint: t('search_hint'),
          onSubmitted: (q) {
            Navigator.of(sheetContext).pop();
            _openSearch(q);
          },
        ),
      ),
    );
  }

  void _openAllProducts() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllProductsScreen()));
  }

  void _openFavorites() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FavoritesScreen()));
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) context.read<NotificationsController>().refresh();
  }

  void _openShop(String shopId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shopId)));
  }

  Future<void> _toggleFavorite(_HomeData data, Product product) async {
    final isFav = data.favoriteIds.contains(product.id);
    setState(() {
      if (isFav) {
        data.favoriteIds.remove(product.id);
      } else {
        data.favoriteIds.add(product.id);
      }
    });
    await _catalog.toggleFavoriteProduct(product.id, !isFav);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    // Icônes de la barre de statut en SOMBRE (22 septembre 2026) : le haut
    // de l'écran est de nouveau une barre BLANCHE ([_HomeTopBar]) et non
    // plus la photo. En blanc, l'heure et la batterie seraient invisibles.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return SafeArea(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(children: [
                    const SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.error_outline,
                      title: t('error_generic'),
                      action: FilledButton(onPressed: _refresh, child: Text(t('retry'))),
                    ),
                  ]),
                ),
              );
            }
            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              // SafeArea complet depuis le 22 septembre 2026 : l'en-tête
              // blanc commence SOUS la barre de statut. `top: false` ne se
              // justifiait que tant que la photo remontait jusqu'en haut.
              child: SafeArea(
                child: ListView(
                  // **`cacheExtent` — 10 septembre 2026, RÉVISÉ le 13 puis
                  // le 14 septembre 2026.** Par défaut, Flutter garde
                  // vivants les éléments situés 250 points au-delà de
                  // l'écran, dans les deux sens. Passé à ZÉRO le 10
                  // septembre pour ne garder décodées que les images à
                  // l'écran — mais Emina a signalé ensuite l'effet de bord :
                  // descendre puis remonter de quelques centimètres
                  // suffisait à faire réapparaître des photos NOIRES pendant
                  // plusieurs secondes.
                  //
                  // Cause : à zéro, la moindre sortie d'écran DÉTRUIT le
                  // widget photo (donc sa texture déjà décodée) au lieu de
                  // le garder ; le moindre retour en repart de zéro — décode
                  // + upload GPU d'une texture neuve.
                  //
                  // Remonté à 120 le 13 septembre (une image de plus de
                  // chaque côté), insuffisant pour un vrai geste de
                  // défilement (plusieurs écrans, pas quelques centimètres).
                  // Le 14 septembre, la densité de décodage plafonnée à ×2
                  // (voir `AppImage`, widgets.dart) libère assez de budget
                  // mémoire (voir main.dart) pour garder plusieurs écrans
                  // vivants sans redécoder : 800 couvre large un aller-
                  // retour normal sans revenir au comportement par défaut
                  // (~250, mais SANS le plafond de densité — donc plus
                  // lourd) qui causait le bug d'origine.
                  cacheExtent: 800,
                  children: [
                    // En-tête blanc puis photo, sans espace entre les deux
                    // (22 septembre 2026) : sur la capture, la photo touche
                    // le bas de la barre blanche. Les 8 px qui précédaient
                    // la bannière n'ont donc plus lieu d'être ici.
                    _HomeTopBar(
                      onSearchTap: _openSearchSheet,
                      onNotificationsTap: _openNotifications,
                      onFavoritesTap: _openFavorites,
                    ),
                    _PromoBanner(
                      imageUrls: data.banners.map((b) => b.imageUrl).toList(),
                      onTap: _openAllProducts,
                    ),
                    // Des produits à la place des catégories, juste sous la
                    // bannière — INCHANGÉ (4 septembre 2026, nuit ; confirmé
                    // le 5 septembre 2026 : voir doc de la classe).
                    //
                    // Chaque section horizontale est enveloppée dans son
                    // propre `RepaintBoundary` depuis le 15 septembre 2026 —
                    // remontée : plusieurs lignes de prix et le titre
                    // "Discounts" se superposant au même endroit à l'écran
                    // pendant le défilement. Un `RepaintBoundary` force
                    // chaque section à peindre sur sa PROPRE surface,
                    // indépendante des autres : si un artefact de rendu
                    // apparaît (mémoire graphique saturée sur Safari
                    // iPhone — même famille que les "photos noires"), il
                    // reste confiné à sa section au lieu de "baver" sur la
                    // section suivante. Vient s'ajouter aux deux autres
                    // correctifs déjà en place pour la même cause
                    // (`--web-renderer html` dans netlify.toml, cache
                    // d'images réduit dans main.dart) plutôt que les
                    // remplacer.
                    // **Sections verticales — 22 septembre 2026.** Les
                    // produits se parcouraient en faisant glisser chaque
                    // rangée vers la DROITE ; ils se parcourent maintenant
                    // vers le BAS, deux par ligne, regroupés par thème
                    // (Nouveautés, Réductions, collections de l'admin).
                    //
                    // C'est la disposition que les collections utilisaient
                    // déjà depuis le 6 septembre 2026 — elle est
                    // simplement étendue au reste de l'accueil, via
                    // [_ProductGrid].
                    //
                    // **Plafonné à 6 par section**, et c'est le point
                    // délicat : une rangée horizontale ne construisait que
                    // les deux ou trois cartes visibles, alors qu'une
                    // grille verticale garde vivantes toutes celles de la
                    // section. Or c'est le NOMBRE de photos décodées en
                    // même temps qui sature Safari sur iPhone (voir la
                    // longue note de `main.dart`, et le plafond de 8 déjà
                    // imposé aux collections dans [_load]). Six par
                    // section laisse trois lignes pleines et reste sous ce
                    // plafond ; « Tout voir » mène à la suite.
                    if (data.products.isNotEmpty) ...[
                      _SectionHeader(
                        title: t('section_new'),
                        seeAllLabel: t('see_all'),
                        onSeeAll: _openAllProducts,
                      ),
                      RepaintBoundary(
                        child: _ProductGrid(
                          products: data.products.take(6).toList(),
                          favoriteIds: data.favoriteIds,
                          onToggleFavorite: (p) => _toggleFavorite(data, p),
                          onOpenShop: _openShop,
                        ),
                      ),
                    ],
                    // Collections gérées par l'admin, APRÈS la rangée
                    // ci-dessus (5 septembre 2026, nuit — voir doc de
                    // [_load]) : cette section reste vide tant qu'aucune
                    // collection n'a été créée depuis le site admin
                    // (Collections) — remplace l'ancienne rangée "Nouveautés".
                    for (final collection in data.collections)
                      if ((data.collectionProducts[collection.id] ?? const []).isNotEmpty)
                        RepaintBoundary(
                          child: _CollectionSection(
                            collection: collection,
                            products: data.collectionProducts[collection.id]!,
                            favoriteIds: data.favoriteIds,
                            onToggleFavorite: (p) => _toggleFavorite(data, p),
                            onOpenShop: _openShop,
                          ),
                        ),
                    if (data.discounted.isNotEmpty) ...[
                      // Le titre était écrit en dur en anglais
                      // (« Discounts »), donc affiché tel quel même en
                      // français et en arabe — il passe par `strings.dart`.
                      _SectionHeader(title: t('section_discounts')),
                      RepaintBoundary(
                        child: _ProductGrid(
                          products: data.discounted.take(6).toList(),
                          favoriteIds: data.favoriteIds,
                          onToggleFavorite: (p) => _toggleFavorite(data, p),
                          onOpenShop: _openShop,
                        ),
                      ),
                    ],
                    // "Meilleures boutiques" retiré du menu Accueil (4
                    // septembre 2026, demande explicite d'Emina) — on
                    // accède toujours à une boutique en touchant son nom
                    // au-dessus d'un de ses produits.
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Bannière — beaucoup plus grande depuis le 4 septembre 2026 (nuit),
/// captures "Level" à l'appui : occupe la quasi-totalité de l'écran
/// (hauteur calculée à partir de l'écran plutôt qu'un simple ratio largeur/
/// hauteur, pour rester très grande sur toutes les tailles de téléphone).
///
/// Corrigé le 4 septembre 2026 (nuit), plus tard : le bandeau "New in /
/// cœur / recherche" (ex-`_HeaderBar`, séparé sur fond blanc) est
/// maintenant SUPERPOSÉ directement sur la photo, en blanc, avec un léger
/// voile dégradé en haut pour rester lisible sur n'importe quelle image —
/// exactement la disposition de la capture Level envoyée deux fois par
/// Emina (caniche + "Women >" en blanc sur la photo, aucune bande blanche
/// séparée). La barre de statut (heure/batterie) passe aussi en blanc,
/// voir [HomeScreen.build].
class _PromoBanner extends StatefulWidget {
  final List<String> imageUrls;
  final VoidCallback onTap;

  const _PromoBanner({
    required this.imageUrls,
    required this.onTap,
  });

  @override
  State<_PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<_PromoBanner> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _timer?.cancel();
    if (widget.imageUrls.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.imageUrls.length;
      _controller.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void didUpdateWidget(covariant _PromoBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls.length != widget.imageUrls.length) _startAutoplay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    // Corrigé le 15 septembre 2026 : avec une seule bannière (ou aucune),
    // `dotCount` retombait avant sur 5 par défaut — des points de
    // pagination apparaissaient donc même sans rien à faire défiler. Ils
    // ne doivent s'afficher que s'il y a au moins deux bannières.
    final hasMultiple = urls.length >= 2;
    // 58 % de la hauteur d'écran — mesuré sur la capture du 22 septembre
    // 2026 : la photo y occupe environ 510 px des ~885 px utiles entre le
    // bas de l'en-tête et le haut de la barre d'onglets, et la première
    // rangée de produits est déjà entamée en bas.
    //
    // C'était 72 % tant que la photo remontait jusque sous la barre de
    // statut : depuis que [_HomeTopBar] lui prend une barre blanche en
    // haut, garder 72 % repousserait les produits hors de l'écran.
    final height = MediaQuery.sizeOf(context).height * 0.58;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            urls.isEmpty
                ? Image.asset('assets/images/home_banner.jpg', fit: BoxFit.cover, width: double.infinity)
                : PageView.builder(
                    controller: _controller,
                    itemCount: urls.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => AppImage(url: urls[i], fit: BoxFit.cover, height: height),
                  ),
            // Le voile dégradé et le bandeau superposé (« New in », cloche,
            // cœur, loupe) ont été retirés le 22 septembre 2026 : ces
            // commandes vivent maintenant dans [_HomeTopBar], au-dessus de
            // la photo. Le dégradé n'existait que pour rendre ce texte
            // blanc lisible sur une photo claire — sans texte par-dessus,
            // il ne ferait qu'assombrir la photo pour rien.
            if (hasMultiple)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(urls.length, (i) {
                    final on = i == _page;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: on ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: on ? Colors.white : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grille de produits : DEUX PAR LIGNE, qui se déroule vers le BAS.
///
/// **Pourquoi une `Column` de `Row` et pas un `GridView`.** La hauteur
/// d'une carte dépend de son contenu (en-tête vendeur + photo + trois
/// lignes de texte), alors qu'une grille impose un rapport
/// largeur/hauteur FIXE : au moindre écart — un nom de boutique plus
/// long, un prix barré sur deux lignes — Flutter affiche les rayures
/// jaunes de débordement. Ici, chaque ligne prend la hauteur qu'il lui
/// faut. C'est la solution déjà retenue pour les collections le
/// 10 septembre 2026 ; ce widget ne fait que la rendre réutilisable.
///
/// `CrossAxisAlignment.start` et surtout PAS `stretch` : cette grille vit
/// dans une page qui défile, donc de hauteur non bornée — `stretch`
/// demanderait aux cartes une hauteur infinie et ferait planter la mise
/// en page.
class _ProductGrid extends StatelessWidget {
  final List<Product> products;
  final Set<String> favoriteIds;
  final ValueChanged<Product> onToggleFavorite;
  final ValueChanged<String> onOpenShop;

  const _ProductGrid({
    required this.products,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onOpenShop,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        children: [
          for (var i = 0; i < products.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _card(context, products[i])),
                const SizedBox(width: 14),
                // Deuxième colonne vide quand le nombre de produits est
                // impair : un `Expanded` vide garde la dernière carte à la
                // même largeur que les autres au lieu de l'étirer sur
                // toute la ligne.
                Expanded(
                  child: i + 1 < products.length
                      ? _card(context, products[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Product product) {
    // `RepaintBoundary` par carte — même raison qu'ailleurs sur cet écran
    // (15 septembre 2026) : confiner un éventuel artefact de rendu à sa
    // carte au lieu de le laisser baver sur la suivante.
    return RepaintBoundary(
      child: ProductCard(
        key: ValueKey(product.id),
        product: product,
        leftAlign: true,
        showSellerHeader: true,
        onOpenShop: () => onOpenShop(product.shopId),
        isFavorite: favoriteIds.contains(product.id),
        onToggleFavorite: () => onToggleFavorite(product),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)),
        ),
      ),
    );
  }
}

/// En-tête d'une section de l'accueil : son titre, et à droite un
/// « Tout voir » quand il existe un écran qui montre la suite.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? seeAllLabel;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.seeAllLabel, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: AppTheme.ink),
            ),
          ),
          if (seeAllLabel != null && onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                seeAllLabel!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Une "collection" — bannière secondaire (photo + titre + sous-titre
/// optionnel) suivie d'une rangée de produits choisis par l'admin, ajoutée
/// le 5 septembre 2026 (nuit) en remplacement de l'ancienne rangée sans
/// titre juste sous la bannière principale (Emina : "enlevé [...] ce qui est
/// après juste la bannière pour mettre une nouvelle bannière", exemple "Hermès
/// for Less" — photo + titre + phrase d'accroche — "Les produits sont
/// présentés de cette manière exactement mais vers le bas", en référence à
/// la même disposition que la grille de produits façon Level déjà utilisée
/// ailleurs sur l'accueil : réutilise donc [ProductCard] plutôt qu'une
/// nouvelle mise en page).
///
/// Peut être répétée plusieurs fois sur l'accueil — l'admin choisit, pour
/// chaque collection, une catégorie précise ou "tous mélangés", et combien
/// de produits afficher (site admin > Collections).
class _CollectionSection extends StatelessWidget {
  final HomeCollection collection;
  final List<Product> products;
  final Set<String> favoriteIds;
  final ValueChanged<Product> onToggleFavorite;
  final ValueChanged<String> onOpenShop;

  const _CollectionSection({
    required this.collection,
    required this.products,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onOpenShop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // **Mesuré sur la capture de référence** envoyée par Emina le
        // 10 septembre 2026 (largeur d'écran : 1179 px) :
        //  - photo : 1179 x 943, soit un rapport de 1,25 — presque carrée,
        //    bien plus haute que le 16/9 utilisé jusqu'ici.
        //
        // Repris et précisé le 15 septembre 2026 (nouvelle mesure directe
        // dans l'outil de design, plus fiable que l'estimation à la
        // hauteur de lettre du 10 septembre) :
        //  - coins carrés (border-radius 0), pas arrondis ;
        //  - titre : ≈52 px → corps 17,5 pt, gras, sans empattement ;
        //  - espace entre l'image et le titre : ≈45 px → 15 pt (précisé le
        //    15 septembre 2026, remplace la mesure ≈43 px de la même
        //    journée) ;
        //  - description : ≈40 px → corps 13,5 pt, normal ;
        //  - espace entre le titre et la description : ≈50 px → 17 pt.
        //
        // **Corrigé à nouveau le 15 septembre 2026** : la photo avait
        // hérité par erreur de la marge de 17 pt gauche/droite du bloc de
        // texte en dessous d'elle (les deux partageaient le même Padding).
        // Or la spec dit "Position : X = 0 px" pour l'image — elle doit
        // prendre toute la largeur de l'écran, sans marge ; seul le texte
        // (titre/description) reste en retrait de 17 pt. Espace avant
        // l'image : 8 px, comme toutes les bannières.
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 15),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: AspectRatio(
              aspectRatio: 1.25,
              child: LayoutBuilder(
                // `height:` fourni explicitement (14 septembre 2026, voir
                // la doc de `AppImage`) — même correctif que la bannière
                // d'accueil et les bandes de catégorie : cette photo de
                // collection est elle aussi affichée en grand, sur toute la
                // largeur.
                builder: (context, constraints) => AppImage(
                  url: collection.imageUrl,
                  fit: BoxFit.cover,
                  height: constraints.maxHeight,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(17, 0, 17, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                collection.title,
                style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppTheme.ink),
              ),
              if (collection.subtitle != null && collection.subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 17),
                Text(
                  collection.subtitle!,
                  style: const TextStyle(fontSize: 13.5, color: AppTheme.ink, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        // Même grille que les autres sections de l'accueil depuis le
        // 22 septembre 2026 : cette disposition « deux par ligne, vers le
        // bas » est née ici (Emina, 6 septembre 2026 : « les produits [...]
        // j'avance pas vers la droite mais vers le bas ») puis a été
        // étendue au reste de la page. Le code vit maintenant dans
        // [_ProductGrid], en un seul exemplaire.
        _ProductGrid(
          products: products,
          favoriteIds: favoriteIds,
          onToggleFavorite: onToggleFavorite,
          onOpenShop: onOpenShop,
        ),
      ],
    );
  }
}


class _HomeData {
  final List<Product> products;
  final Set<String> favoriteIds;
  final List<HomeBanner> banners;
  final List<Product> discounted;
  final List<HomeCollection> collections;
  final Map<String, List<Product>> collectionProducts;

  _HomeData({
    required this.products,
    required this.favoriteIds,
    required this.banners,
    required this.discounted,
    required this.collections,
    required this.collectionProducts,
  });
}


/// Cloche des notifications, avec une pastille rouge quand il y a des
/// non-lues (6 septembre 2026). Le compteur est tenu par
/// [NotificationsController], relu toutes les 30 secondes.
/// En-tête blanc de l'accueil — 22 septembre 2026, d'après la capture
/// envoyée par Emina.
///
/// **Ce qu'il remplace.** Jusqu'ici le bandeau (cœur, cloche, loupe, plus
/// le fil d'Ariane « New in ») était SUPERPOSÉ en blanc sur la photo, qui
/// remontait jusque sous la barre de statut. La capture montre autre
/// chose : une barre blanche franche, le monogramme « b » à gauche, trois
/// icônes sombres à droite, et la photo qui commence SOUS cette barre.
///
/// **Conséquences, toutes visibles à l'écran :**
///  * les icônes de la barre de statut repassent en sombre
///    ([SystemUiOverlayStyle.dark]) — sur fond blanc, du blanc serait
///    invisible ;
///  * le `SafeArea` du haut est rétabli : plus rien ne doit passer sous
///    l'encoche ;
///  * le voile dégradé en haut de [_PromoBanner] n'a plus de raison
///    d'être — il n'existait que pour garder du texte blanc lisible sur
///    une photo claire.
///
/// **Le monogramme.** `logo_b.png` n'est PAS encore dans le dépôt : les
/// quatre images présentes (`logo.png`, `logo_mark.png`, les deux
/// `splash_*`) sont toutes le chariot + le mot, aucune n'est le « b »
/// seul de la capture. Tant que le fichier manque, `errorBuilder` retombe
/// sur le logo complet : l'accueil reste utilisable et ne lève pas
/// d'exception. Déposer le « b » en noir sur fond TRANSPARENT à
/// `assets/images/logo_b.png` suffit à le faire apparaître, sans toucher
/// au code.
class _HomeTopBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onFavoritesTap;

  const _HomeTopBar({
    required this.onSearchTap,
    required this.onNotificationsTap,
    required this.onFavoritesTap,
  });

  @override
  Widget build(BuildContext context) {
    // Décodage à la taille affichée — même budget serré qu'ailleurs (voir
    // la note de `main.dart` sur les photos noires de Safari iPhone).
    final decodeWidth = (34 * 2 * MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0)).round();

    return ColoredBox(
      color: AppTheme.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Image.asset(
              'assets/images/logo_b.png',
              height: 34,
              cacheWidth: decodeWidth,
              semanticLabel: 'Boutigui',
              // Repli tant que le monogramme n'est pas fourni — voir la
              // doc de la classe.
              errorBuilder: (context, _, __) => Image.asset(
                'assets/images/logo.png',
                height: 30,
                cacheWidth: decodeWidth,
                semanticLabel: 'Boutigui',
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.search, color: AppTheme.ink, size: 24),
              onPressed: onSearchTap,
            ),
            _NotificationBell(onTap: onNotificationsTap, color: AppTheme.ink),
            IconButton(
              // Un CŒUR, pas un marque-page : c'est ce que montre la
              // capture, et c'est aussi ce que l'écran d'arrivée appelle
              // « Favoris ».
              icon: const Icon(Icons.favorite_border, color: AppTheme.ink, size: 24),
              onPressed: onFavoritesTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;

  /// Couleur de la cloche. Blanche du temps où le bandeau était superposé
  /// à la photo ; depuis l'en-tête blanc du 22 septembre 2026, c'est
  /// [AppTheme.ink] qui est passé — d'où le paramètre plutôt qu'une
  /// constante en dur.
  final Color color;

  const _NotificationBell({required this.onTap, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsController>().unread;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_none, color: color, size: 23),
          onPressed: onTap,
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppTheme.red,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
