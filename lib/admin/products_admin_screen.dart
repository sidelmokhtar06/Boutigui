import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import 'admin_widgets.dart';

/// Sous cette largeur DE LA LIGNE elle-même (pas de l'écran — une ligne a
/// déjà perdu le padding de page), une ligne produit passe de côte-à-côte à
/// empilée verticalement.
const double _rowBreakpoint = 560;

class ProductsAdminScreen extends StatefulWidget {
  const ProductsAdminScreen({super.key});

  @override
  State<ProductsAdminScreen> createState() => _ProductsAdminScreenState();
}

class _ProductsAdminScreenState extends State<ProductsAdminScreen> {
  final _admin = AdminService();
  late Future<List<Product>> _future;
  late Future<List<AdminShopRow>> _shopsFuture;
  String? _shopFilter;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _shopsFuture = _admin.fetchAllShops();
    _future = _admin.fetchAllProducts();
  }

  void _refresh() {
    setState(() => _future = _admin.fetchAllProducts(shopId: _shopFilter, search: _search.text.trim().isEmpty ? null : _search.text.trim()));
  }

  Future<void> _toggleVisible(Product p) async {
    try {
      await _admin.setProductVisible(p.id, !p.isVisible);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _delete(Product p) async {
    final ok = await confirmDialog(context, title: 'Delete "${p.name}"?', message: 'This action cannot be undone.');
    if (!ok) return;
    try {
      await _admin.deleteProduct(p.id);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _openAdd() async {
    final shops = await _shopsFuture;
    if (!mounted) return;
    if (shops.isEmpty) {
      showAdminError(context, "Create at least one shop first.");
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(admin: _admin, shops: shops),
    );
    if (created == true) _refresh();
  }

  Future<void> _openEdit(Product p) async {
    final shops = await _shopsFuture;
    if (!mounted) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(admin: _admin, shops: shops, existing: p),
    );
    if (updated == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Products',
          subtitle: "Le vendeur ET l'admin peuvent ajouter, modifier, supprimer",
          action: FilledButton.icon(onPressed: _openAdd, icon: const Icon(Icons.add, size: 18), label: const Text('New product')),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(isNarrowAdmin(context) ? 16 : 28, 0, isNarrowAdmin(context) ? 16 : 28, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shopDropdown = FutureBuilder<List<AdminShopRow>>(
                future: _shopsFuture,
                builder: (context, snapshot) {
                  final shops = snapshot.data ?? [];
                  return DropdownButtonFormField<String>(
                    value: _shopFilter,
                    decoration: const InputDecoration(labelText: 'Shop'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All shops')),
                      ...shops.map((s) => DropdownMenuItem(value: s.shop.id, child: Text(s.shop.name, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) {
                      setState(() => _shopFilter = v);
                      _refresh();
                    },
                  );
                },
              );
              final searchField = TextField(
                controller: _search,
                decoration: const InputDecoration(hintText: 'Search a product', prefixIcon: Icon(Icons.search)),
                onSubmitted: (_) => _refresh(),
              );
              if (constraints.maxWidth < 480) {
                return Column(children: [searchField, const SizedBox(height: 10), shopDropdown]);
              }
              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  SizedBox(width: 240, child: shopDropdown),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final products = snapshot.data ?? [];
              if (products.isEmpty) {
                return const Center(child: Text('No products.', style: TextStyle(color: AdminTheme.muted)));
              }
              final pad = isNarrowAdmin(context) ? 16.0 : 28.0;
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ProductRow(
                  product: products[i],
                  onToggleVisible: () => _toggleVisible(products[i]),
                  onEdit: () => _openEdit(products[i]),
                  onDelete: () => _delete(products[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Une ligne "produit" — côte à côte sur écran large, empilée en petite
/// carte sur écran étroit (ajouté le 2 septembre 2026, pour que le site
/// admin reste utilisable sur téléphone).
class _ProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback onToggleVisible;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductRow({required this.product, required this.onToggleVisible, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: p.coverImage != null
          ? Image.network(p.coverImage!, width: 44, height: 44, fit: BoxFit.cover)
          : Container(width: 44, height: 44, color: const Color(0xFFF2EDEB), child: const Icon(Icons.image_outlined, color: AdminTheme.muted, size: 18)),
    );
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.ink)),
        Text(p.shopName ?? '', style: const TextStyle(fontSize: 12, color: AdminTheme.muted)),
      ],
    );
    final statusPill = AdminStatusPill(label: p.isVisible ? 'Visible' : 'Hidden', color: p.isVisible ? const Color(0xFF2E9C5B) : AdminTheme.muted);
    final salePill = p.isOnSale ? AdminStatusPill(label: 'Promo -${p.discountPercent}%', color: AdminTheme.red) : null;
    final actions = [
      Switch(value: p.isVisible, activeColor: AdminTheme.red, onChanged: (_) => onToggleVisible()),
      IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit),
      IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AdminTheme.red), onPressed: onDelete),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _rowBreakpoint) {
          return AdminCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [thumb, const SizedBox(width: 12), Expanded(child: nameBlock)]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(Money.format(p.price), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminTheme.ink)),
                    Text('Stock: ${p.stock}', style: const TextStyle(fontSize: 12.5, color: AdminTheme.ink2)),
                    statusPill,
                    if (salePill != null) salePill,
                  ],
                ),
                const Divider(height: 20, color: AdminTheme.hair),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ),
          );
        }
        return AdminCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              thumb,
              const SizedBox(width: 12),
              Expanded(flex: 2, child: nameBlock),
              Expanded(child: Text(Money.format(p.price), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminTheme.ink))),
              Expanded(child: Text('Stock: ${p.stock}', style: const TextStyle(fontSize: 12.5, color: AdminTheme.ink2))),
              statusPill,
              if (salePill != null) ...[const SizedBox(width: 6), salePill],
              const SizedBox(width: 4),
              ...actions,
            ],
          ),
        );
      },
    );
  }
}

class _ProductDialog extends StatefulWidget {
  final AdminService admin;
  final List<AdminShopRow> shops;
  final Product? existing;

  const _ProductDialog({required this.admin, required this.shops, this.existing});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _storage = StorageService();
  late final TextEditingController _brand;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _compareAtPrice;
  late final TextEditingController _stock;
  String? _shopId;
  String? _categoryId;
  List<Category> _categories = [];
  bool _saving = false;
  Uint8ListHolder? _pickedImage;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _brand = TextEditingController(text: p?.brand ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _price = TextEditingController(text: p != null ? p.price.toStringAsFixed(0) : '');
    _compareAtPrice = TextEditingController(text: p?.compareAtPrice != null ? p!.compareAtPrice!.toStringAsFixed(0) : '');
    _stock = TextEditingController(text: p != null ? '${p.stock}' : '0');
    _shopId = p?.shopId ?? (widget.shops.isNotEmpty ? widget.shops.first.shop.id : null);
    _categoryId = p?.categoryId;
    widget.admin.fetchAllCategoriesFlat().then((cats) {
      if (mounted) setState(() => _categories = cats);
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _pickedImage = Uint8ListHolder(bytes, picked.name));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _shopId == null) return;
    setState(() => _saving = true);
    try {
      final price = double.parse(_price.text.trim().replaceAll(',', '.'));
      final compareAtText = _compareAtPrice.text.trim();
      final compareAtPrice = compareAtText.isEmpty ? null : double.tryParse(compareAtText.replaceAll(',', '.'));
      final stock = int.tryParse(_stock.text.trim()) ?? 0;
      final brandText = _brand.text.trim();
      String productId;
      if (widget.existing == null) {
        productId = await widget.admin.createProduct(
          shopId: _shopId!,
          categoryId: _categoryId,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          price: price,
          compareAtPrice: compareAtPrice,
          stock: stock,
          brand: brandText.isEmpty ? null : brandText,
        );
      } else {
        productId = widget.existing!.id;
        await widget.admin.updateProduct(
          id: productId,
          name: _name.text.trim(),
          description: _description.text.trim(),
          price: price,
          compareAtPrice: compareAtPrice,
          clearCompareAtPrice: compareAtPrice == null,
          stock: stock,
          categoryId: _categoryId,
          brand: brandText.isEmpty ? '' : brandText,
        );
      }
      if (_pickedImage != null) {
        final ext = _pickedImage!.name.contains('.') ? _pickedImage!.name.split('.').last : 'jpg';
        final path = _storage.ownedPath('$productId/${DateTime.now().millisecondsSinceEpoch}.$ext');
        final url = await _storage.uploadPublic(bucket: 'product-images', path: path, bytes: _pickedImage!.bytes);
        await widget.admin.addProductImage(productId: productId, url: url);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nouveau produit' : 'Modifier le produit'),
      content: SizedBox(
        width: adminDialogWidth(context, 440),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _shopId,
                  decoration: const InputDecoration(labelText: 'Shop'),
                  items: widget.shops.map((s) => DropdownMenuItem(value: s.shop.id, child: Text(s.shop.name))).toList(),
                  onChanged: widget.existing == null ? (v) => setState(() => _shopId = v) : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _brand,
                  decoration: const InputDecoration(labelText: 'Brand (optional — otherwise the shop name is shown)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Price (MRU)'),
                        validator: (v) => (v == null || double.tryParse(v.trim().replaceAll(',', '.')) == null) ? 'Prix invalide' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stock'),
                        // Ajouté le 4 septembre 2026 : sans validation, un
                        // stock non numérique ou négatif devenait 0 en
                        // silence (voir `int.tryParse(...) ?? 0` dans
                        // `_save()`), sans que l'admin s'en rende compte.
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n < 0) return 'Stock invalide';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _compareAtPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Crossed-out price (optional — for a promotion)',
                    helperText: "Leave empty = no promotion. Filled in and higher than the price: shows the crossed-out price + the discount.",
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return double.tryParse(v.trim().replaceAll(',', '.')) == null ? 'Prix invalide' : null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_pickedImage == null ? 'Ajouter une photo' : _pickedImage!.name),
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

class Uint8ListHolder {
  final Uint8List bytes;
  final String name;

  Uint8ListHolder(this.bytes, this.name);
}
