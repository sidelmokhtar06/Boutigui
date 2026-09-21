import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import 'admin_widgets.dart';

/// Gestion des bannières — ajoutée le 2 septembre 2026 (uniquement pour
/// l'accueil à l'époque). Étendue le 4 septembre 2026 (nuit) : une bannière
/// peut maintenant être rattachée à une catégorie précise plutôt qu'à
/// l'accueil (captures d'Emina, façon Level : une bannière "Aquazzura"
/// visible seulement dans la section Chaussures) — d'où le sélecteur
/// d'emplacement en haut de cet écran. Chaque emplacement (accueil, ou une
/// catégorie donnée) garde son propre plafond de 5 photos.
class BannersAdminScreen extends StatefulWidget {
  const BannersAdminScreen({super.key});

  @override
  State<BannersAdminScreen> createState() => _BannersAdminScreenState();
}

class _BannersAdminScreenState extends State<BannersAdminScreen> {
  final _admin = AdminService();
  final _storage = StorageService();
  late Future<List<HomeBanner>> _future;
  Future<List<Category>>? _categoriesFuture;
  // null = emplacement "Accueil".
  String? _placementCategoryId;
  String _placementLabel = 'Accueil';
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = _admin.fetchCategories();
    _future = _admin.fetchBanners(categoryId: _placementCategoryId);
  }

  void _refresh() => setState(() => _future = _admin.fetchBanners(categoryId: _placementCategoryId));

  void _selectPlacement(String? categoryId, String label) {
    setState(() {
      _placementCategoryId = categoryId;
      _placementLabel = label;
    });
    _refresh();
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final path = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      // Compression déjà faite automatiquement par `uploadPublic` (voir
      // storage_service.dart) — pas besoin de la refaire ici.
      final url = await _storage.uploadPublic(bucket: 'banner-images', path: path, bytes: bytes);
      await _admin.addBanner(url, categoryId: _placementCategoryId);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleVisible(HomeBanner b) async {
    try {
      await _admin.setBannerVisible(b.id, !b.isVisible);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _delete(HomeBanner b) async {
    final ok = await confirmDialog(context, title: 'Delete this photo?', message: 'It will disappear from the banner rotation.');
    if (!ok) return;
    try {
      await _admin.deleteBanner(b.id);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _move(List<HomeBanner> banners, int index, int delta) async {
    final other = index + delta;
    if (other < 0 || other >= banners.length) return;
    try {
      await _admin.swapBannerOrder(banners[index], banners[other]);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _pickPlacement() async {
    final categories = await (_categoriesFuture ?? Future.value(<Category>[]));
    if (!mounted) return;
    final chosen = await showModalBottomSheet<_Placement>(
      context: context,
      backgroundColor: AdminTheme.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AdminTheme.line, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose a location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminTheme.ink)),
              ),
            ),
            ListTile(
              title: const Text('Home', style: TextStyle(color: AdminTheme.ink)),
              trailing: _placementCategoryId == null ? const Icon(Icons.check, color: AdminTheme.red) : null,
              onTap: () => Navigator.of(context).pop(const _Placement(null, 'Accueil')),
            ),
            for (final c in categories)
              ListTile(
                title: Text(c.name, style: const TextStyle(color: AdminTheme.ink)),
                trailing: _placementCategoryId == c.id ? const Icon(Icons.check, color: AdminTheme.red) : null,
                onTap: () => Navigator.of(context).pop(_Placement(c.id, c.name)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) _selectPlacement(chosen.categoryId, chosen.label);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Banners',
          subtitle: 'Up to ${AdminService.maxBanners} photos per location — they scroll automatically. '
              'Home keeps its usual banner; a category only shows its banner at the top of that specific category, in addition to the home one.',
          action: FutureBuilder<List<HomeBanner>>(
            future: _future,
            builder: (context, snapshot) {
              final count = snapshot.data?.length ?? 0;
              final full = count >= AdminService.maxBanners;
              return FilledButton.icon(
                onPressed: (_uploading || full) ? null : _addPhoto,
                icon: _uploading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(full ? 'Maximum atteint ($count/${AdminService.maxBanners})' : 'Ajouter une photo'),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isNarrowAdmin(context) ? 16 : 28),
          child: InkWell(
            onTap: _pickPlacement,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AdminTheme.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminTheme.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: AdminTheme.muted),
                  const SizedBox(width: 8),
                  const Text('Location: ', style: TextStyle(fontSize: 13, color: AdminTheme.muted)),
                  Text(_placementLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AdminTheme.ink)),
                  const Spacer(),
                  const Icon(Icons.unfold_more, size: 18, color: AdminTheme.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<HomeBanner>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final banners = snapshot.data ?? [];
              if (banners.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _placementCategoryId == null
                          ? "No photo added for the home page — the app currently shows the default photo shipped with the project."
                          : "No banner for \"$_placementLabel\" — nothing shows at the top of this category for now.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AdminTheme.muted),
                    ),
                  ),
                );
              }
              final pad = isNarrowAdmin(context) ? 16.0 : 28.0;
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                itemCount: banners.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final b = banners[i];
                  return AdminCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(b.imageUrl, width: 64, height: 64, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Photo ${i + 1}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AdminTheme.ink)),
                        ),
                        if (!b.isVisible)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: AdminStatusPill(label: 'Hidden', color: AdminTheme.muted),
                          ),
                        IconButton(tooltip: 'Move up', icon: const Icon(Icons.arrow_upward, size: 18), onPressed: i == 0 ? null : () => _move(banners, i, -1)),
                        IconButton(tooltip: 'Move down', icon: const Icon(Icons.arrow_downward, size: 18), onPressed: i == banners.length - 1 ? null : () => _move(banners, i, 1)),
                        Switch(value: b.isVisible, activeColor: AdminTheme.red, onChanged: (_) => _toggleVisible(b)),
                        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: 18, color: AdminTheme.red), onPressed: () => _delete(b)),
                      ],
                    ),
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

class _Placement {
  final String? categoryId;
  final String label;

  const _Placement(this.categoryId, this.label);
}
