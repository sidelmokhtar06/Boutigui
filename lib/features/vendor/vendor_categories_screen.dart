import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import 'vendor_gate_screen.dart';

/// Questions posées à l'inscription vendeuse — 6 septembre 2026.
///
/// Emina : « Si l'utilisateur choisit cette option, des questions doivent
/// lui être posées concernant la ou les catégories de produits qu'elle va
/// proposer (possibilité de sélectionner plusieurs choix) ».
///
/// Remplace l'ancien écran à choix UNIQUE (`sell_category_screen.dart`,
/// 4 septembre 2026), qui ne servait qu'à pré-remplir la catégorie du
/// premier produit. Les catégories choisies ici sont enregistrées sur la
/// boutique (table `shop_categories`), et la première sert toujours de
/// catégorie par défaut pour le premier produit.
class VendorCategoriesScreen extends StatefulWidget {
  const VendorCategoriesScreen({super.key});

  @override
  State<VendorCategoriesScreen> createState() => _VendorCategoriesScreenState();
}

class _VendorCategoriesScreenState extends State<VendorCategoriesScreen> {
  late final Future<List<Category>> _future;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _future = CatalogService().fetchCategories();
  }

  Future<void> _continue() async {
    // Le parcours reste le même qu'avant : écran de connexion/inscription
    // dédié à la vendeuse (même si elle a déjà un compte cliente), puis
    // "Ma boutique". Les catégories choisies sont transmises pour être
    // enregistrées à la création de la boutique.
    await openMyShop(
      context,
      initialCategoryId: _selected.isEmpty ? null : _selected.first,
      categoryIds: _selected.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: AppTheme.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        title: const Text('Categories', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w600, fontSize: 17)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<List<Category>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final categories = snapshot.data ?? [];
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    children: [
                      // Question en gris, centrée, sous le titre — comme la
                      // capture "In what category is the item you are
                      // selling?" (6 septembre 2026).
                      const Text(
                        'What categories will you sell in?\nYou can select more than one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15.5, color: AppTheme.muted, height: 1.35),
                      ),
                      const SizedBox(height: 26),
                      if (categories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No category available right now.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        )
                      else
                        // Lignes simples séparées d'un trait fin, comme la
                        // capture de référence envoyée par Emina ("In what
                        // category is the item you are selling?") — avec une
                        // coche à droite, puisqu'ici plusieurs réponses sont
                        // possibles.
                        for (final category in categories) ...[
                          InkWell(
                            onTap: () => setState(() {
                              if (_selected.contains(category.id)) {
                                _selected.remove(category.id);
                              } else {
                                _selected.add(category.id);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      category.name,
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        color: AppTheme.ink,
                                        fontWeight: _selected.contains(category.id) ? FontWeight.w700 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  // Chevron quand la catégorie n'est pas
                                  // choisie (comme la capture), coche noire
                                  // quand elle l'est — plusieurs réponses
                                  // sont possibles ici, contrairement à la
                                  // capture qui, elle, descend dans une
                                  // arborescence.
                                  Icon(
                                    _selected.contains(category.id) ? Icons.check : Icons.chevron_right,
                                    size: 22,
                                    color: AppTheme.ink,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1, color: AppTheme.line),
                        ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // Au moins une catégorie : une boutique sans aucune
                      // catégorie n'apparaîtrait nulle part.
                      onPressed: _selected.isEmpty ? null : _continue,
                      child: const Text('CONTINUE'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
