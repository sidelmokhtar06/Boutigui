import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/cart_controller.dart';
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
/// bande blanche du tout). Ce comportement a été REMPLACÉ le 20 septembre
/// 2026 par un en-tête blanc classique — voir [_HomeHeader]. Le texte ci-
/// dessous décrit l'ancienne disposition, conservé pour l'historique.
/// L'ancien bandeau superposé, qui
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
    // Catégories pour la grille « Explorer par catégorie » (20 septembre
    // 2026, maquette) — elles portent déjà une photo (`image_url`, ajouté
    // par rattrapage_patch.sql), donc rien à créer côté base.
    final categories = await _catalog.fetchAllCategories();
    // Statistiques d'inclusion — `null` tant que
    // `supabase/inclusion_patch.sql` n'a pas été joué, la section est
    // alors simplement masquée.
    final inclusion = await _catalog.fetchInclusionStats();
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
      categories: categories,
      inclusion: inclusion,
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
    // Icônes de la barre de statut en SOMBRE (20 septembre 2026) : depuis
    // la refonte, le haut de l'écran est un en-tête BLANC et non plus une
    // photo. Laisser l'heure et la batterie en blanc les rendait
    // invisibles.
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
              // SafeArea complet depuis le 20 septembre 2026 : l'en-tête
              // blanc commence sous la barre de statut. Avant, `top: false`
              // laissait la bannière passer dessous, ce qui n'a plus lieu
              // d'être.
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
                    // En-tête + bannière en carte (20 septembre 2026) —
                    // remplacent l'ancien bandeau, qui superposait son
                    // bandeau blanc à la photo. Voir le commentaire de
                    // bloc au-dessus de [_HomeHeader].
                    _HomeHeader(
                      onSearch: _openSearch,
                      onFavoritesTap: _openFavorites,
                      onNotificationsTap: _openNotifications,
                      onCartTap: _openAllProducts,
                    ),
                    _HeroCard(
                      imageUrls: data.banners.map((b) => b.imageUrl).toList(),
                      onTap: _openAllProducts,
                    ),
                    const SizedBox(height: 24),
                    _CategoryGrid(
                      categories: data.categories,
                      onTap: (c) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AllProductsScreen(categoryId: c.id, categoryName: c.name),
                        ),
                      ),
                      onSeeAll: _openAllProducts,
                    ),
                    const SizedBox(height: 24),
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
                    if (data.products.isNotEmpty)
                      RepaintBoundary(
                        child: _ProductShowcaseGrid(
                          products: data.products,
                          favoriteIds: data.favoriteIds,
                          onToggleFavorite: (p) => _toggleFavorite(data, p),
                          seeAllLabel: t('see_all'),
                          onSeeAll: _openAllProducts,
                        ),
                      ),
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
                    if (data.discounted.isNotEmpty)
                      RepaintBoundary(
                        child: _ThemedProductRow(
                          title: 'Discounts',
                          products: data.discounted,
                          favoriteIds: data.favoriteIds,
                          onToggleFavorite: (p) => _toggleFavorite(data, p),
                          onOpenShop: _openShop,
                        ),
                      ),
                    // "Meilleures boutiques" retiré du menu Accueil (4
                    // septembre 2026, demande explicite d'Emina) — on
                    // accède toujours à une boutique en touchant son nom
                    // au-dessus d'un de ses produits.
                    const SizedBox(height: 28),
                    if (data.inclusion != null)
                      _ImpactPanel(stats: data.inclusion!),
                    const SizedBox(height: 16),
                    const _TrustBar(),
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
/// Remplace la grille "Explorer" (catégories) le 4 septembre 2026 (nuit) —
/// Emina : "à la place de catégorie tu dois mettre des produits", captures
/// Level (image + cœur, marque en majuscules, nom, prix). Réutilise
/// [ProductCard] (déjà exactement ce design, aligné à gauche ici comme sur
/// les captures plutôt que centré) en défilement horizontal, terminé par
/// une carte "Tout voir" sobre — remplace aussi l'ancien gros bouton pleine
/// largeur (Emina : "un bouton plus professionnel et élégant [...] essai
/// de mettre le même size", capture "View All").
///
/// Conservé tel quel le 5 septembre 2026 (nuit) : une première tentative
/// l'avait remplacé par [_CollectionSection], mais Emina a précisé que
/// cette rangée devait rester (voir doc de [HomeScreen]) — seule la rangée
/// titrée "Nouveautés" qui suivait est remplacée par les collections.
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
        // Grille de 2 produits par ligne, qui se déroule VERS LE BAS
        // (Emina, 6 septembre 2026 : "les produits après la deuxième
        // bannière il doit être deux par pages [...] j'avance pas vers la
        // droite mais vers le bas"). Avant, c'était une rangée qui
        // défilait horizontalement.
        //
        // Construite en `Column` de `Row` plutôt qu'en `GridView` : la
        // hauteur d'une carte dépend de son contenu (en-tête vendeur +
        // photo + 3 lignes de texte), alors qu'une grille impose un
        // rapport largeur/hauteur fixe — au moindre écart, Flutter
        // afficherait les rayures jaunes de débordement. Ici chaque ligne
        // prend la hauteur qu'il lui faut.
        //
        // `CrossAxisAlignment.start` et surtout PAS `stretch` : cette
        // rangée vit dans une page qui défile, donc de hauteur non bornée
        // — `stretch` demanderait aux cartes de faire une hauteur infinie
        // et ferait planter la mise en page. Les deux cartes d'une ligne
        // ont de toute façon la même hauteur (mêmes éléments, textes
        // limités à une ligne).
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Column(
            children: [
              for (var i = 0; i < products.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 26),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _collectionCard(context, products[i])),
                    const SizedBox(width: 14),
                    // Deuxième colonne vide quand le nombre de produits est
                    // impair : un `Expanded` vide garde la dernière carte à
                    // la même largeur que les autres au lieu de l'étirer
                    // sur toute la ligne.
                    Expanded(
                      child: i + 1 < products.length ? _collectionCard(context, products[i + 1]) : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _collectionCard(BuildContext context, Product product) {
    return ProductCard(
      product: product,
      leftAlign: true,
      showSellerHeader: true,
      onOpenShop: () => onOpenShop(product.shopId),
      isFavorite: favoriteIds.contains(product.id),
      onToggleFavorite: () => onToggleFavorite(product),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)),
      ),
    );
  }
}

/// Liste horizontale thématique — façon Oskelly : le nom de la boutique
/// au-dessus de chaque produit ([ProductFeedCard]). Utilisée pour
/// "Nouveautés" et "Réductions".
class _ThemedProductRow extends StatelessWidget {
  final String title;
  final List<Product> products;
  final Set<String> favoriteIds;
  final ValueChanged<Product> onToggleFavorite;
  final ValueChanged<String> onOpenShop;

  const _ThemedProductRow({
    required this.title,
    required this.products,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onOpenShop,
  });

  @override
  Widget build(BuildContext context) {
    // Même spec que _ProductShowcaseRow (15 septembre 2026) : largeur ≈
    // 40 % de l'écran, image 5:7, espacement 6 px, coins carrés. +30 px de
    // hauteur ici pour la mini-ligne boutique (avatar + nom) au-dessus de
    // la photo, propre à [ProductFeedCard].
    final cardWidth = MediaQuery.sizeOf(context).width * 0.4;
    const imageRatio = 0.714;
    // +16 de marge de sécurité supplémentaire, même raison que
    // _ProductShowcaseRow (voir sa doc).
    final cardHeight = cardWidth / productGridAspectRatio(cardWidth, imageRatio: imageRatio) + 30 + 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 34, 20, 14),
          child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: AppTheme.ink)),
        ),
        ClipRect(
          child: SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: products.length,
            itemBuilder: (context, i) {
              final product = products[i];
              return Padding(
                key: ValueKey(product.id),
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: cardWidth,
                  // RepaintBoundary par carte, en plus de celui posé sur
                  // toute la section (home_screen.dart, plus haut) — 15
                  // septembre 2026, deuxième passage sur le même
                  // signalement persistant : granularité plus fine, pour
                  // isoler chaque carte individuellement si l'artefact
                  // vient d'une carte précise plutôt que de la section
                  // entière.
                  child: RepaintBoundary(
                    child: ProductFeedCard(
                      product: product,
                      imageAspectRatio: imageRatio,
                      borderRadius: BorderRadius.zero,
                      isFavorite: favoriteIds.contains(product.id),
                      onToggleFavorite: () => onToggleFavorite(product),
                      onShopTap: () => onOpenShop(product.shopId),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          ),
        ),
      ],
    );
  }
}

class _HomeData {
  final List<Product> products;
  final List<Category> categories;
  final Map<String, int>? inclusion;
  final Set<String> favoriteIds;
  final List<HomeBanner> banners;
  final List<Product> discounted;
  final List<HomeCollection> collections;
  final Map<String, List<Product>> collectionProducts;

  _HomeData({
    required this.products,
    required this.categories,
    required this.inclusion,
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
class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;

  const _NotificationBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsController>().unread;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          // Encre et non blanc depuis le 21 septembre 2026 : cette cloche
          // était posée sur la photo de la bannière ; elle vit maintenant
          // dans l'en-tête blanc.
          icon: const Icon(Icons.notifications_none, color: AppTheme.ink, size: 23),
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

// =====================================================================
// Accueil refait le 20 septembre 2026, d'après la maquette fournie.
//
// Ce qui change par rapport à la version précédente :
//
//  - Un vrai EN-TÊTE blanc au-dessus du contenu, au lieu d'un bandeau
//    blanc superposé à la photo. Le texte blanc sur une photo choisie par
//    la vendeuse depuis l'admin n'était lisible que par chance ; sur une
//    bannière claire il disparaissait. L'en-tête réglé ce problème pour
//    de bon, et permet d'afficher la recherche en clair plutôt que
//    derrière une loupe.
//  - Une bannière EN CARTE, encadrée et arrondie, au format 16:9 — donc
//    beaucoup plus courte. La première rangée de produits passe au-dessus
//    de la ligne de flottaison, ce qui est l'intérêt d'une place de
//    marché.
//  - Une grille de catégories, deux cartes promotionnelles et un bandeau
//    de réassurance, tous repris de la maquette.
// =====================================================================

/// En-tête : mot-symbole, recherche, notifications / favoris / panier.
///
/// Sur la maquette (large), le logo et la recherche tiennent sur une seule
/// ligne. Sur un téléphone de 393 points, les faire cohabiter écrase la
/// recherche à une largeur inutilisable : on empile donc en deux rangées.
class _HomeHeader extends StatelessWidget {
  /// Appelée avec le texte saisi, à la validation au clavier.
  final ValueChanged<String> onSearch;
  final VoidCallback onFavoritesTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onCartTap;

  const _HomeHeader({
    required this.onSearch,
    required this.onFavoritesTap,
    required this.onNotificationsTap,
    required this.onCartTap,
  });

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartController>().itemCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.eco, size: 22, color: AppTheme.green),
                        const SizedBox(width: 6),
                        Text('Boutigui', style: AppTheme.brand(size: 21, color: AppTheme.ink)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // La baseline de la maquette. En français, et sans
                    // promesse que le produit ne tient pas.
                    Text(
                      'COMMERCE · PAIEMENT · CROISSANCE',
                      style: AppTheme.brand(size: 8, color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              // La cloche porte la pastille des notifications non lues —
              // une icône nue la perdait (21 septembre 2026).
              _NotificationBell(onTap: onNotificationsTap),
              _HeaderIcon(
                icon: Icons.favorite_border,
                onTap: onFavoritesTap,
              ),
              _HeaderIcon(
                icon: Icons.shopping_bag_outlined,
                onTap: onCartTap,
                badge: cartCount > 0 ? '$cartCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // VRAI champ de saisie — corrigé le 21 septembre 2026.
          //
          // C'était un `InkWell` qui RESSEMBLAIT à un champ et ouvrait une
          // feuille contenant un second champ : on touchait une barre de
          // recherche pour en obtenir une autre, sans pouvoir écrire dans
          // la première. Une barre de recherche doit accepter la frappe là
          // où on la touche.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              style: const TextStyle(fontSize: 13, color: AppTheme.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppTheme.searchFill,
                hintText: 'Rechercher un produit, une boutique…',
                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.searchPlaceholder),
                prefixIcon: const Icon(Icons.search, size: 19, color: AppTheme.searchPlaceholder),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  borderSide: const BorderSide(color: AppTheme.green, width: 1.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  const _HeaderIcon({required this.icon, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 23, color: AppTheme.ink),
          if (badge != null)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15),
                decoration: BoxDecoration(
                  color: AppTheme.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bannière en carte, format 16:9, avec ses points de pagination.
///
/// Le format est FIXE et non plus une fraction de la hauteur d'écran : une
/// bannière qui contient du texte doit être cadrée pareil sur tous les
/// appareils.
///
/// **4:3 et pas 16:9**, bien que la maquette montre une bande plus large.
/// Les bannières sont envoyées depuis le site admin par des gens qui
/// cadrent ce qu'ils veulent, souvent au carré. Dans une boîte 16:9, une
/// image carrée perd 44 % de sa hauteur — sur `home_banner.jpg`, le titre
/// disparaissait entièrement. En 4:3 elle n'en perd que 25 %, et une
/// bannière mal cadrée reste présentable. Un format large n'est le bon
/// choix que si l'on maîtrise chaque image, ce qui n'est pas le cas ici.
///
/// Format idéal à fournir : 4:3, par exemple 1440 × 1080.
class _HeroCard extends StatefulWidget {
  final List<String> imageUrls;
  final VoidCallback onTap;
  const _HeroCard({required this.imageUrls, required this.onTap});

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    final hasMultiple = urls.length >= 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: AppTheme.sage,
                  child: urls.isEmpty
                      ? Image.asset('assets/images/home_banner.jpg', fit: BoxFit.cover)
                      : PageView.builder(
                          controller: _controller,
                          itemCount: urls.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) =>
                              AppImage(url: urls[i], fit: BoxFit.cover),
                        ),
                ),
                if (hasMultiple)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < urls.length; i++)
                          Container(
                            width: i == _page ? 16 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i == _page ? Colors.white : Colors.white70,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grille « Explorer par catégorie ».
///
/// Le nombre de colonnes suit la largeur disponible au lieu d'être figé :
/// trois sur un téléphone étroit, jusqu'à six sur une tablette. Chaque
/// cellule est une carte — photo en haut, libellé en bas — comme sur la
/// maquette.
class _CategoryGrid extends StatelessWidget {
  final List<Category> categories;
  final void Function(Category) onTap;
  final VoidCallback onSeeAll;

  const _CategoryGrid({
    required this.categories,
    required this.onTap,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / 118).floor().clamp(3, 6);
      // Deux rangées pleines, puis une case « Plus » pour le reste.
      final slots = columns * 2;
      final shown = categories.take(slots - 1).toList();
      const spacing = 10.0;
      final width = (c.maxWidth - 32 - (columns - 1) * spacing) / columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Explorer par catégorie',
            onSeeAll: onSeeAll,
            seeAllLabel: 'Tout voir',
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final cat in shown)
                  SizedBox(
                    width: width,
                    child: CategoryCard(category: cat, onTap: () => onTap(cat)),
                  ),
                SizedBox(
                  width: width,
                  child: CategoryCard(category: null, onTap: onSeeAll),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}


/// Bandeau de réassurance, en bas de l'accueil.
///
/// La maquette proposait « Secure Payment — 100% Safe ». Deux raisons de ne
/// pas l'écrire :
///
///  1. Le roadmap l'interdit explicitement (§27, « Do not claim 100%
///     secure ») — et un jury fintech relève ce genre de promesse.
///  2. Ce serait faux. Boutigui ne traite aucun paiement : l'argent va
///     directement de la cliente à la vendeuse par son application
///     bancaire. On ne peut pas garantir la sécurité d'une transaction
///     qu'on ne touche pas.
///
/// Les quatre arguments ci-dessous disent donc ce que le produit fait
/// vraiment — ce qui se trouve être une meilleure histoire.
class _TrustBar extends StatelessWidget {
  const _TrustBar();

  static const _items = [
    (Icons.account_balance_outlined, 'Paiement direct', 'Bankily · Masrvi · Sedad'),
    (Icons.receipt_long_outlined, 'Référence unique', 'Chaque paiement tracé'),
    (Icons.local_shipping_outlined, 'Livraison', 'Organisée par la boutique'),
    (Icons.storefront_outlined, 'Boutiques locales', 'Entrepreneurs mauritaniens'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.greenTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: LayoutBuilder(builder: (context, c) {
        // Quatre de front dès qu'il y a la place, deux par deux sinon.
        final columns = c.maxWidth < 380 ? 2 : 4;
        final width = (c.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 14,
          children: [
            for (final item in _items)
              SizedBox(
                width: width,
                child: Column(
                  children: [
                    Icon(item.$1, size: 20, color: AppTheme.green),
                    const SizedBox(height: 6),
                    Text(item.$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink)),
                    const SizedBox(height: 2),
                    Text(item.$3,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10, height: 1.25, color: AppTheme.ink2)),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Grille de produits de l'accueil — 20 septembre 2026.
///
/// Remplace [_ProductShowcaseRow], qui faisait défiler les produits
/// HORIZONTALEMENT. Trois raisons de passer à une grille qui descend :
///
///  - Une rangée horizontale ne montrait que deux produits et demi. Le
///    reste n'existait que pour qui devine qu'on peut pousser de côté —
///    et sur le web, où il n'y a pas de geste tactile, quasiment personne
///    ne le devine.
///  - Deux directions de défilement sur le même écran (la page descend,
///    la rangée va de côté) se gênent : on part de travers en voulant
///    descendre.
///  - La grille est déjà la façon dont les produits sont présentés dans
///    « Tous les produits » (`all_products_screen.dart`). Deux écrans qui
///    montrent la même chose devaient la montrer pareil.
///
/// Le calibrage est donc repris tel quel de cet écran : deux colonnes,
/// 2 px de filet, bord à bord, format calculé par [productGridAspectRatio].
class _ProductShowcaseGrid extends StatelessWidget {
  final List<Product> products;
  final Set<String> favoriteIds;
  final ValueChanged<Product> onToggleFavorite;
  final String seeAllLabel;
  final VoidCallback onSeeAll;

  const _ProductShowcaseGrid({
    required this.products,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.seeAllLabel,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    // Une page d'accueil n'est pas un catalogue : on en montre une
    // poignée, « Tout voir » fait le reste. 12 = six rangées de deux.
    final shown = products.take(12).toList();
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Produits',
          onSeeAll: onSeeAll,
          seeAllLabel: seeAllLabel,
        ),
        const SizedBox(height: 4),
        GridView.builder(
          // La page défile déjà : cette grille ne doit pas défiler pour son
          // propre compte, elle prend juste la hauteur qu'il lui faut.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: productGridAspectRatio((width - 2) / 2),
          ),
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final product = shown[i];
            return ProductCard(
              key: ValueKey(product.id),
              product: product,
              isFavorite: favoriteIds.contains(product.id),
              onToggleFavorite: () => onToggleFavorite(product),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProductScreen(productId: product.id)),
              ),
            );
          },
        ),
        if (products.length > shown.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton(
              onPressed: onSeeAll,
              child: Text(seeAllLabel),
            ),
          ),
      ],
    );
  }
}

/// Panneau d'impact (20 septembre 2026).
///
/// Boutigui est ouvert à tous les entrepreneurs mauritaniens ; les femmes en
/// sont le public principal. Ce panneau mesure cette réalité au lieu de
/// l'affirmer.
///
/// Deux précautions :
///
///  * la part de boutiques dirigées par des femmes est calculée sur les
///    boutiques qui ont RÉPONDU, pas sur le total — sinon celles qui
///    n'ont rien déclaré seraient comptées comme « non », ce qui est faux
///    et minore le chiffre ;
///  * elle n'est affichée qu'à partir de trois déclarations. En dessous,
///    un pourcentage sur un ou deux cas ne veut rien dire et se lirait
///    comme une statistique.
class _ImpactPanel extends StatelessWidget {
  final Map<String, int> stats;
  const _ImpactPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final total = stats['total'] ?? 0;
    final women = stats['women'] ?? 0;
    final declared = stats['declared'] ?? 0;
    final cities = stats['cities'] ?? 0;
    if (total == 0) return const SizedBox.shrink();

    final showShare = declared >= 3;
    final share = showShare ? (women / declared * 100).round() : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('impact_title').toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.ink)),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(value: '$total', label: t('impact_shops')),
              if (showShare) _Stat(value: '$share %', label: t('impact_women_led')),
              _Stat(value: '$cities', label: t('impact_cities')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.green)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, height: 1.2, color: AppTheme.ink2)),
        ],
      ),
    );
  }
}
