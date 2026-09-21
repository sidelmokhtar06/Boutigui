import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../features/widgets.dart';
import '../models/models.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import 'admin_widgets.dart';

// [kCategoryImageAspectRatio] (models.dart, 1920/480) sert de cadre à
// [PhotoPositionScreen] ici, pour que le cadrage choisi par
// l'administration corresponde exactement à ce que verra la cliente (voir
// aussi categories_screen.dart, qui utilise la même constante).

const double _categoryRowBreakpoint = 560;

/// Gestion des catégories — liste à plat depuis le 31 août 2026 (Emina a
/// retiré la possibilité d'avoir des sous-catégories : Skincare, Perfumes,
/// Health & Nutrition... sont maintenant toutes au même niveau). Chaque
/// catégorie peut avoir une photo, ajoutée ou changée directement ici.
///
/// Depuis le 5 septembre 2026 (Emina : "l'admin il peut contrôler le
/// photo, soit couper une partie ou faire un zoom"), la photo d'une
/// catégorie se cadre/zoome ici même — touche la photo (nouvellement
/// choisie ou déjà en ligne) dans le formulaire pour ouvrir
/// [PhotoPositionScreen], dans le format exact d'une bande de catégorie
/// (1920x690, voir [kCategoryImageAspectRatio]).
class CategoriesAdminScreen extends StatefulWidget {
  const CategoriesAdminScreen({super.key});

  @override
  State<CategoriesAdminScreen> createState() => _CategoriesAdminScreenState();
}

class _CategoriesAdminScreenState extends State<CategoriesAdminScreen> {
  final _admin = AdminService();
  late Future<List<Category>> _future;

  @override
  void initState() {
    super.initState();
    _future = _admin.fetchCategories();
  }

  void _refresh() => setState(() => _future = _admin.fetchCategories());

  Future<void> _openAdd() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(admin: _admin),
    );
    if (created == true) _refresh();
  }

  Future<void> _openEdit(Category category) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(admin: _admin, existing: category),
    );
    if (updated == true) _refresh();
  }

  Future<void> _toggleVisible(Category category) async {
    try {
      await _admin.setCategoryVisible(category.id, !category.isVisible);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _delete(Category category) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${category.name}"?',
      message: 'Products linked to it won\'t be deleted, but will lose this category.',
    );
    if (!ok) return;
    try {
      await _admin.deleteCategory(category.id);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  /// Boutons Monter/Descendre — ajoutés le 4 septembre 2026 : jusqu'ici rien
  /// ne permettait de contrôler l'ordre d'affichage des catégories dans
  /// l'application (contrairement à la bannière d'accueil, qui a toujours eu
  /// ces boutons).
  Future<void> _move(List<Category> categories, int index, int delta) async {
    final other = index + delta;
    if (other < 0 || other >= categories.length) return;
    try {
      await _admin.swapCategoryOrder(categories[index], categories[other]);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Categories',
          subtitle: 'Skincare, Perfumes, Health & Nutrition… all at the same level, with a photo',
          action: FilledButton.icon(
            onPressed: _openAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New category'),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Category>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final categories = snapshot.data ?? [];
              if (categories.isEmpty) {
                return const Center(child: Text('No categories yet.', style: TextStyle(color: AdminTheme.muted)));
              }
              final pad = isNarrowAdmin(context) ? 16.0 : 28.0;
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final category = categories[i];
                  return _CategoryRow(
                    category: category,
                    canMoveUp: i > 0,
                    canMoveDown: i < categories.length - 1,
                    onMoveUp: () => _move(categories, i, -1),
                    onMoveDown: () => _move(categories, i, 1),
                    onToggleVisible: () => _toggleVisible(category),
                    onEdit: () => _openEdit(category),
                    onDelete: () => _delete(category),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Une ligne "catégorie" — côte à côte sur écran large ; sur écran étroit,
/// les boutons Monter/Descendre ajoutés le 4 septembre 2026 (en plus de
/// Modifier/Supprimer/visibilité déjà présents) ne tiennent plus sur une
/// seule ligne, donc ils passent sur une deuxième rangée (`Wrap`) — même
/// principe que `_ShopRow` dans shops_admin_screen.dart.
class _CategoryRow extends StatelessWidget {
  final Category category;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onToggleVisible;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryRow({
    required this.category,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleVisible,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final categoryAlignment = Alignment(category.focalX * 2 - 1, category.focalY * 2 - 1);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: category.imageUrl != null && category.imageUrl!.isNotEmpty
          ? SizedBox(
              width: 44,
              height: 44,
              child: AppImage(url: category.imageUrl, fit: BoxFit.cover, alignment: categoryAlignment, zoom: category.zoom),
            )
          : Container(
              width: 44,
              height: 44,
              color: const Color(0xFFF2EDEB),
              child: const Icon(Icons.image_outlined, color: AdminTheme.muted, size: 18),
            ),
    );
    final nameBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            category.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: category.isVisible ? AdminTheme.ink : AdminTheme.muted,
            ),
          ),
        ),
        if (!category.isVisible) ...[
          const SizedBox(width: 8),
          const AdminStatusPill(label: 'Hidden', color: AdminTheme.muted),
        ],
        // Genre (13 septembre 2026) — masqué pour '*' (les deux onglets,
        // valeur par défaut) pour ne pas surcharger la ligne : seule une
        // catégorie limitée à Femme ou Homme affiche un badge.
        if (category.gender != '*') ...[
          const SizedBox(width: 8),
          AdminStatusPill(
            label: category.gender == 'women' ? 'Femme' : 'Homme',
            color: AdminTheme.muted,
          ),
        ],
      ],
    );
    final actions = [
      IconButton(tooltip: 'Move up', icon: const Icon(Icons.arrow_upward, size: 18), onPressed: canMoveUp ? onMoveUp : null),
      IconButton(tooltip: 'Move down', icon: const Icon(Icons.arrow_downward, size: 18), onPressed: canMoveDown ? onMoveDown : null),
      Switch(value: category.isVisible, activeColor: AdminTheme.red, onChanged: (_) => onToggleVisible()),
      IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit),
      IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: AdminTheme.red), onPressed: onDelete),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _categoryRowBreakpoint) {
          return AdminCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [thumb, const SizedBox(width: 12), Expanded(child: nameBlock)]),
                const Divider(height: 20, color: AdminTheme.hair),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ),
          );
        }
        return AdminCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [thumb, const SizedBox(width: 12), Expanded(child: nameBlock), ...actions],
          ),
        );
      },
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  final AdminService admin;
  final Category? existing;

  const _CategoryDialog({required this.admin, this.existing});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _storage = StorageService();
  late final TextEditingController _name;
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedExt;
  // Point à garder visible + zoom (5 septembre 2026 — Emina : "l'admin il
  // peut contrôler le photo, soit couper une partie ou faire un zoom") :
  // initialisés avec ceux de la catégorie existante (0.5/0.5/1.0 = centre,
  // pas de zoom, si nouvelle catégorie ou pas encore réglés).
  late double _focalX;
  late double _focalY;
  late double _zoom;
  // Sous quel onglet (Femme / Homme / les deux) — 13 septembre 2026.
  // Nullable depuis le 14 septembre : voir initState, plus de choix
  // présélectionné pour une NOUVELLE catégorie.
  String? _gender;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _focalX = widget.existing?.focalX ?? 0.5;
    _focalY = widget.existing?.focalY ?? 0.5;
    _zoom = widget.existing?.zoom ?? 1.0;
    // **14 septembre 2026** : plus de présélection automatique sur "Les
    // deux" pour une nouvelle catégorie — Emina a remarqué des catégories
    // Femme visibles par erreur dans l'onglet Homme, venant justement de ce
    // choix silencieux par défaut. En modification, la valeur déjà
    // enregistrée reste affichée normalement.
    _gender = widget.existing?.gender;
  }

  bool get _hasImage => _pickedBytes != null || (widget.existing?.imageUrl != null && widget.existing!.imageUrl!.isNotEmpty);

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    // Demande tout de suite le cadrage/zoom de cette nouvelle photo, dans le
    // format exact d'une bande de catégorie (1920x690) — si annulé, la
    // photo n'est pas retenue (5 septembre 2026, même principe que côté
    // vendeuse pour les photos produit).
    if (!mounted) return;
    final result = await Navigator.of(context).push<(double, double, double)>(
      MaterialPageRoute(builder: (_) => PhotoPositionScreen(bytes: bytes, frameAspectRatio: kCategoryImageAspectRatio)),
    );
    if (result == null) return;
    setState(() {
      _pickedBytes = bytes;
      _pickedExt = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      _focalX = result.$1;
      _focalY = result.$2;
      _zoom = result.$3;
    });
  }

  /// Recadre/zoome la photo actuelle (nouvellement choisie, ou déjà en
  /// ligne) sans forcément en changer le fichier — si la catégorie existe
  /// déjà et qu'aucune nouvelle photo n'a été choisie, le nouveau cadrage
  /// est enregistré tout de suite (pas besoin d'appuyer sur "Enregistrer").
  Future<void> _repositionImage() async {
    if (!_hasImage) return;
    final hasNewPick = _pickedBytes != null;
    final result = await Navigator.of(context).push<(double, double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoPositionScreen(
          bytes: hasNewPick ? _pickedBytes : null,
          url: hasNewPick ? null : widget.existing!.imageUrl,
          initialFocalX: _focalX,
          initialFocalY: _focalY,
          initialZoom: _zoom,
          frameAspectRatio: kCategoryImageAspectRatio,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _focalX = result.$1;
      _focalY = result.$2;
      _zoom = result.$3;
    });
    if (!hasNewPick && widget.existing != null) {
      try {
        await widget.admin.updateCategoryImagePosition(id: widget.existing!.id, focalX: _focalX, focalY: _focalY, zoom: _zoom);
      } catch (e) {
        if (mounted) showAdminError(context, e);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) {
      showAdminError(context, 'Choisissez Femme, Homme ou Les deux avant d\'enregistrer.');
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_pickedBytes != null) {
        final path = '${DateTime.now().millisecondsSinceEpoch}.$_pickedExt';
        imageUrl = await _storage.uploadPublic(bucket: 'category-images', path: path, bytes: _pickedBytes!);
      }
      if (widget.existing == null) {
        await widget.admin.createCategory(
          name: _name.text.trim(),
          imageUrl: imageUrl,
          focalX: _focalX,
          focalY: _focalY,
          zoom: _zoom,
          gender: _gender!,
        );
      } else {
        await widget.admin.renameCategory(widget.existing!.id, _name.text.trim());
        if (imageUrl != null) {
          await widget.admin.setCategoryImage(widget.existing!.id, imageUrl, focalX: _focalX, focalY: _focalY, zoom: _zoom);
        }
        if (_gender != widget.existing!.gender) {
          await widget.admin.setCategoryGender(widget.existing!.id, _gender!);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showAdminError(context, e);
    }
  }

  /// Prévisualisation (photo choisie, ou déjà en ligne) avec le cadrage/
  /// zoom actuel déjà appliqué — pour que l'administration voie tout de
  /// suite l'effet de son choix, comme la vignette photo côté vendeuse.
  Widget _buildPreviewImage(String? existingImage) {
    final alignment = Alignment(_focalX * 2 - 1, _focalY * 2 - 1);
    final image = _pickedBytes != null
        ? Image.memory(_pickedBytes!, fit: BoxFit.cover, alignment: alignment)
        : Image.network(existingImage!, fit: BoxFit.cover, alignment: alignment);
    return _zoom == 1.0 ? image : Transform.scale(scale: _zoom, alignment: alignment, child: image);
  }

  @override
  Widget build(BuildContext context) {
    final existingImage = widget.existing?.imageUrl;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New category' : 'Edit category'),
      content: SizedBox(
        width: adminDialogWidth(context, 380),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 14),
                // Sous quel onglet de l'accueil (Femme / Homme) cette
                // catégorie apparaît (13 septembre 2026). **14 septembre**
                // : plus de présélection sur "Les deux" pour une nouvelle
                // catégorie — un choix explicite est maintenant obligatoire
                // (voir _save), pour éviter qu'une catégorie Femme se
                // retrouve par erreur dans l'onglet Homme faute d'y avoir
                // pensé.
                const Text('Gender', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AdminTheme.muted)),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: '*', label: Text('Both')),
                    ButtonSegment(value: 'women', label: Text('Women')),
                    ButtonSegment(value: 'men', label: Text('Men')),
                  ],
                  selected: _gender == null ? const <String>{} : {_gender!},
                  onSelectionChanged: (s) => setState(() => _gender = s.isEmpty ? null : s.first),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _hasImage ? _repositionImage : null,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: !_hasImage
                                  ? Container(
                                      color: const Color(0xFFF2EDEB),
                                      child: const Icon(Icons.image_outlined, color: AdminTheme.muted, size: 20),
                                    )
                                  : _buildPreviewImage(existingImage),
                            ),
                          ),
                          // Indice visuel : la photo est touchable pour la
                          // recadrer/zoomer (5 septembre 2026).
                          if (_hasImage)
                            Positioned(
                              left: 2,
                              bottom: 2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                                alignment: Alignment.center,
                                child: const Icon(Icons.control_camera, size: 11, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(_pickedBytes == null ? 'Choisir une photo' : 'Photo choisie'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Save'),
        ),
      ],
    );
  }
}
