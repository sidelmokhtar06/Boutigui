import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../products/all_products_screen.dart';
import '../widgets.dart';

/// Onglet "Catégories" — grandes bandes pleine largeur, photo + nom de la
/// catégorie par-dessus, séparées par une barre noire.
///
/// **Refait le 5 septembre 2026 à partir de MESURES prises sur la capture
/// de référence** (Emina : "les catégories doivent être de cette manière le
/// même font de l'écriture le même size ; pour mon application n'est pas le
/// même font ni le même size est plus grand"). Les versions précédentes de
/// cet écran ont été construites à l'oeil, ce qui explique les allers-
/// retours ; cette fois chaque valeur vient d'une mesure sur l'image
/// envoyée (largeur de référence : 728 px) :
///
/// | Élément                | Mesuré sur la capture | Ici                      |
/// |------------------------|-----------------------|--------------------------|
/// | hauteur d'une bande    | 262 px (= 2,78 : 1)   | 1920x480, demandé par Emina après avoir vu le rendu |
/// | barre de séparation    | 32 px, noire          | blanche et plus courte, demandé par Emina |
/// | fond de bande          | #EAEAEA               | [AppTheme.categoryBand]  |
/// | hauteur des capitales  | 22,5 px               | corps 15,5 (réduit à sa demande, voir [AppTheme.categoryLabel]) |
/// | couleur du texte       | ~#232323              | [AppTheme.ink]           |
/// | marge à gauche du texte| ~14 px (= 8 pt)       | 8                        |
/// | marge sur les côtés    | aucune (pleine largeur) | aucune, ni coins arrondis |
///
/// Les trois écarts avec les versions précédentes qui expliquent la
/// remarque d'Emina : la police (Inter → Montserrat, voir
/// [AppTheme.categoryLabel]), la bande deux fois trop courte (le nom
/// paraissait donc énorme dedans), et les bandes qui étaient encadrées
/// (marge de 20 px + coins arrondis) alors que la capture les montre
/// bord à bord.
///
/// **Onglets Femme / Homme ajoutés le 13 septembre 2026** (captures Level
/// envoyées par Emina : "Women" / "Men", chacun avec sa propre liste de
/// catégories — New In / Clothing / Shoes côté homme, plus Dresses côté
/// femme). Revient sur l'écart assumé lors du tour précédent, qui omettait
/// cette rangée faute d'un genre sur les catégories : `Category.gender`
/// ('women' / 'men' / '*' pour les deux) permet maintenant de la recréer.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _catalog = CatalogService();
  late Future<List<Category>> _future;
  // Onglet actif — Femme par défaut, comme sur la capture de référence.
  String _gender = 'women';

  @override
  void initState() {
    super.initState();
    _future = _catalog.fetchCategories(gender: _gender);
  }

  void _selectGender(String gender) {
    if (gender == _gender) return;
    setState(() {
      _gender = gender;
      _future = _catalog.fetchCategories(gender: gender);
    });
  }

  void _openSearch(String query) {
    if (query.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AllProductsScreen(search: query.trim())),
    );
  }

  void _openCategory(Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AllProductsScreen(categoryId: category.id, categoryName: category.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Scaffold(
      // Fond blanc très légèrement chaud (#FFFFFB), relevé au pixel sur la
      // capture de référence — "le même couleur à 100 %".
      backgroundColor: AppTheme.shopPageBg,
      body: SafeArea(
        child: Column(
          children: [
            // En-tête refait le 5 septembre 2026 d'après la capture de
            // référence ("exactement la photo 2, même couleur"), mesurée
            // sur un écran de 1178 px de large :
            //  - titre : hauteur des capitales 37 px = 12,3 pt → corps 17,
            //    en demi-gras (l'app était à 26 en gras) ;
            //  - champ : gris NEUTRE #F6F6F4 au lieu du gris légèrement
            //    rosé de l'accueil (c'était la différence de couleur),
            //    hauteur 44, coins 12, loupe et texte gris #A8A6A7,
            //    texte du champ au même corps que le titre.
            // Ces réglages ne s'appliquent qu'ici : l'accueil garde son
            // champ tel quel (valeurs par défaut de [AppSearchField]).
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  // Mot repris tel quel de la capture (Emina, 5 septembre
                  // 2026 : "au lieu de catégories tu dois mettre le mot
                  // Shop") — donc pas de traduction, c'est le titre voulu
                  // dans les trois langues. Le libellé de l'onglet en bas
                  // de l'écran, lui, reste traduit.
                  'Shop',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.shopTitle),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 21, 20, 14),
              child: AppSearchField(
                hint: t('search_hint_short'),
                onSubmitted: _openSearch,
                fillColor: AppTheme.searchFillNeutral,
                iconColor: AppTheme.searchGrey,
                hintColor: AppTheme.searchGrey,
                height: 44,
                radius: 12,
                fontSize: 16.5,
                iconSize: 21,
              ),
            ),
            _GenderTabs(
              selected: _gender,
              womenLabel: t('gender_women'),
              menLabel: t('gender_men'),
              onSelect: _selectGender,
            ),
            Expanded(
              child: FutureBuilder<List<Category>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: t('error_generic'),
                      subtitle: snapshot.error.toString(),
                    );
                  }
                  final categories = snapshot.data ?? [];
                  if (categories.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 100),
                      EmptyState(icon: Icons.grid_view_outlined, title: t('no_results')),
                    ]);
                  }
                  // Mesuré au pixel sur la capture de référence (IMG_0846,
                  // 1179 px de large, échelle ×3) le 15 septembre 2026 :
                  // la bande grise s'arrête à 48 px du bord gauche et à
                  // 49 px du bord droit — 16 pt de marge de CHAQUE côté,
                  // pas de bord à bord. Espace blanc avant la première
                  // bande : 36 px = 12 pt, la même valeur que l'espace
                  // entre deux bandes ([AppTheme.categorySeparatorHeight]).
                  return ListView.separated(
                    // Voir home_screen.dart (10 septembre 2026, révisé le
                    // 13) : petite marge plutôt que zéro, contre les photos
                    // noires lors d'un aller-retour de défilement.
                    cacheExtent: 800,
                    padding: const EdgeInsets.only(top: AppTheme.categorySeparatorHeight),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const _CategorySeparator(),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _CategoryBand(category: categories[i], onTap: () => _openCategory(categories[i])),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Onglets "FEMME" / "HOMME" au-dessus de la liste de catégories (13
/// septembre 2026) — mesuré sur la capture Level de référence : deux
/// libellés centrés côte à côte, celui actif en gras avec un trait bleu en
/// dessous, une fine ligne grise sous toute la rangée pour les deux.
class _GenderTabs extends StatelessWidget {
  final String selected;
  final String womenLabel;
  final String menLabel;
  final ValueChanged<String> onSelect;

  const _GenderTabs({
    required this.selected,
    required this.womenLabel,
    required this.menLabel,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Expanded(child: _tab(womenLabel, 'women')),
          Expanded(child: _tab(menLabel, 'men')),
        ],
      ),
    );
  }

  Widget _tab(String label, String value) {
    final active = value == selected;
    return InkWell(
      onTap: () => onSelect(value),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: active ? AppTheme.ink : AppTheme.muted,
              ),
            ),
          ),
          Container(height: 2, color: active ? AppTheme.ink : AppTheme.line),
        ],
      ),
    );
  }
}

/// Espace blanc pleine largeur entre deux bandes — pas une ligne colorée :
/// mesuré à 12 pt sur la capture de référence (voir `categorySeparator`
/// dans theme.dart, corrigé le 15 septembre 2026).
class _CategorySeparator extends StatelessWidget {
  const _CategorySeparator();

  @override
  Widget build(BuildContext context) {
    return Container(height: AppTheme.categorySeparatorHeight, color: AppTheme.categorySeparator);
  }
}

/// Une bande de catégorie : photo pleine largeur, nom en capitales par
/// dessus, aligné à gauche et centré verticalement.
///
/// Pas de voile sombre sur la photo : le cadrage/zoom choisi côté admin
/// (voir categories_admin_screen.dart et [Category.focalX]/[focalY]/[zoom])
/// place déjà le sujet à l'écart du texte, exactement comme sur la capture
/// où les mannequins sont à droite et le fond clair à gauche.
class _CategoryBand extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  const _CategoryBand({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Largeur réelle de la bande : plein écran moins les 16 pt de marge
    // ajoutés de chaque côté dans `CategoriesScreen` (Padding autour de
    // chaque `_CategoryBand`). `AspectRatio` s'adapte déjà tout seul à
    // cette largeur réduite ; seule la hauteur *explicite* passée à
    // `AppImage` doit être recalculée à partir d'elle, sinon l'image
    // garde l'ancienne hauteur pleine largeur.
    final bandWidth = MediaQuery.sizeOf(context).width - 32;
    return InkWell(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: kCategoryImageAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppTheme.categoryBand),
            AppImage(
              url: category.imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment(category.focalX * 2 - 1, category.focalY * 2 - 1),
              zoom: category.zoom,
              height: bandWidth / kCategoryImageAspectRatio,
            ),
            Positioned(
              // 24 pt — mesuré sur la capture de référence : le texte
              // commence à 40 pt du bord de l'écran, moins les 16 pt de
              // marge de la bande elle-même = 24 pt depuis le bord de la
              // bande.
              left: 24,
              top: 0,
              bottom: 0,
              right: 12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  // Casse naturelle, plus de majuscules forcées — 15
                  // septembre 2026, pour coller à la référence envoyée par
                  // Emina ("Balenciaga", pas "BALENCIAGA").
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.categoryLabel(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
