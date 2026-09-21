import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/money.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../services/vendor_service.dart';
import '../widgets.dart';
import 'vendor_dashboard_screen.dart';

/// "Ma boutique" — création de boutique en libre-service (façon profil
/// Instagram) et gestion de ses propres produits, directement depuis
/// l'application cliente. Ajouté le 4 septembre 2026, en remplacement de
/// l'ancien formulaire de candidature : n'importe quel compte connecté
/// peut créer sa boutique tout de suite ; elle reste CACHÉE (donc ses
/// produits n'apparaissent nulle part côté client) tant que l'admin ne
/// l'a pas validée depuis le site admin.
class MyShopScreen extends StatefulWidget {
  /// Première catégorie choisie à l'inscription vendeuse
  /// ([VendorCategoriesScreen]) — si fournie, le premier ajout de produit
  /// s'ouvre automatiquement avec cette catégorie déjà sélectionnée.
  final String? initialCategoryId;

  /// Catégories choisies à l'inscription vendeuse (6 septembre 2026,
  /// [VendorCategoriesScreen]) — enregistrées sur la boutique dès sa
  /// création. Vide quand on revient simplement sur son tableau de bord.
  final List<String> initialCategoryIds;

  const MyShopScreen({super.key, this.initialCategoryId, this.initialCategoryIds = const []});

  @override
  State<MyShopScreen> createState() => _MyShopScreenState();
}

class _MyShopScreenState extends State<MyShopScreen> {
  final _vendor = VendorService();
  late Future<Shop?> _future;

  @override
  void initState() {
    super.initState();
    _future = _vendor.fetchMyShop();
  }

  void _refresh() => setState(() => _future = _vendor.fetchMyShop());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: AppTheme.bg,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        title: const Text('My shop', style: TextStyle(color: AppTheme.ink)),
      ),
      body: SafeArea(
        child: FutureBuilder<Shop?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final shop = snapshot.data;
            if (shop == null) {
              return _CreateShopView(
                vendor: _vendor,
                onCreated: _refresh,
                categoryIds: widget.initialCategoryIds,
              );
            }
            return _MyShopDashboard(
              vendor: _vendor,
              shop: shop,
              onShopUpdated: _refresh,
              initialCategoryId: widget.initialCategoryId,
            );
          },
        ),
      ),
    );
  }
}

/// Formulaire de création — comme un profil (nom, photo, description,
/// ville, WhatsApp). Rien à valider avant l'envoi côté admin : la boutique
/// est créée tout de suite, mais reste cachée jusqu'à validation.
class _CreateShopView extends StatefulWidget {
  final VendorService vendor;
  final VoidCallback onCreated;
  final List<String> categoryIds;

  const _CreateShopView({required this.vendor, required this.onCreated, this.categoryIds = const []});

  @override
  State<_CreateShopView> createState() => _CreateShopViewState();
}

class _CreateShopViewState extends State<_CreateShopView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _whatsapp = TextEditingController();
  // Code marchand de la banque mobile (6 septembre 2026) — obligatoire :
  // sans lui, aucune cliente ne peut payer cette boutique, puisque le
  // paiement se fait par "paiement commerçant" dans son application
  // bancaire.
  final _merchantCode = TextEditingController();
  String _merchantProvider = _kMerchantProviders.first;
  bool? _womenLed;
  double? _pickupLat;
  double? _pickupLng;
  final _storage = StorageService();
  Uint8List? _logoBytes;
  String? _logoName;
  bool _saving = false;
  // Photo obligatoire (4 septembre 2026, nuit — Emina : "il y a des
  // informations que le vendeur il doit mettre", capture du profil boutique
  // Oskelly avec avatar) : pas de champ de formulaire classique pour la
  // photo (c'est un cercle qu'on touche), donc pas de `validator` — on
  // affiche/masque ce message d'erreur nous-mêmes à la place.
  bool _logoMissingError = false;

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _logoBytes = bytes;
      _logoName = picked.name;
      _logoMissingError = false;
    });
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    setState(() => _logoMissingError = _logoBytes == null);
    if (!formOk || _logoBytes == null) return;
    setState(() => _saving = true);
    try {
      String? logoUrl;
      if (_logoBytes != null) {
        final ext = (_logoName ?? '').contains('.') ? _logoName!.split('.').last : 'jpg';
        final path = _storage.ownedPath('${DateTime.now().millisecondsSinceEpoch}.$ext');
        logoUrl = await _storage.uploadPublic(bucket: 'shop-images', path: path, bytes: _logoBytes!);
      }
      final shop = await widget.vendor.createMyShop(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        logoUrl: logoUrl,
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        whatsappPhone: _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
        merchantCode: _merchantCode.text.trim(),
        merchantProvider: _merchantProvider,
        womenLed: _womenLed,
        lat: _pickupLat,
        lng: _pickupLng,
      );
      // Catégories choisies à l'étape précédente (6 septembre 2026).
      if (widget.categoryIds.isNotEmpty) {
        await widget.vendor.setMyShopCategories(shopId: shop.id, categoryIds: widget.categoryIds);
      }
      widget.onCreated();
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _whatsapp.dispose();
    _merchantCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create your shop',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppTheme.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            "Like a profile: the photo and WhatsApp number are required (customers need them to recognize and contact you). Your shop stays private until the admin approves it — you'll then be visible on the home page.",
            style: TextStyle(fontSize: 13.5, color: AppTheme.ink2, height: 1.4),
          ),
          const SizedBox(height: 22),
          Center(
            child: GestureDetector(
              onTap: _pickLogo,
              child: Stack(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.panel,
                      border: _logoMissingError ? Border.all(color: AppTheme.red, width: 1.5) : null,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: _logoBytes != null
                        ? Image.memory(_logoBytes!, fit: BoxFit.cover)
                        : const Icon(Icons.storefront_outlined, color: AppTheme.muted, size: 32),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.ink),
                      alignment: Alignment.center,
                      child: const Icon(Icons.add, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_logoMissingError) ...[
            const SizedBox(height: 8),
            const Center(
              child: Text('Photo required — tap the circle to add one.', style: TextStyle(fontSize: 12, color: AppTheme.red)),
            ),
          ],
          const SizedBox(height: 26),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Shop name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
                const SizedBox(height: 12),
                TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City (optional)')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _whatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'WhatsApp number'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required — customers need it to contact you' : null,
                ),
                const SizedBox(height: 12),
                _MerchantCodeFields(
                  codeController: _merchantCode,
                  provider: _merchantProvider,
                  onProviderChanged: (v) => setState(() => _merchantProvider = v),
                ),
                _WomenLedField(
                  value: _womenLed,
                  onChanged: (v) => setState(() => _womenLed = v),
                ),
                const SizedBox(height: 16),
                _PickupLocationField(
                  initialLat: _pickupLat,
                  initialLng: _pickupLng,
                  onLocated: (pos) => setState(() {
                    _pickupLat = pos.$1;
                    _pickupLng = pos.$2;
                  }),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('CREATE MY SHOP'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formulaire de modification d'une boutique déjà créée — ajouté le
/// 4 septembre 2026 (Emina : "le boutique il ne peut pas mettre un photo de
/// profile ni le modifier"). Mêmes champs que [_CreateShopView] (nom,
/// photo, description, ville, WhatsApp), pré-remplis avec les valeurs
/// actuelles, dans une boîte de dialogue plutôt qu'un écran plein pour
/// rester léger (peu de champs, pas de multi-photos comme pour un produit).
class _EditShopDialog extends StatefulWidget {
  final VendorService vendor;
  final Shop shop;

  const _EditShopDialog({required this.vendor, required this.shop});

  @override
  State<_EditShopDialog> createState() => _EditShopDialogState();
}

class _EditShopDialogState extends State<_EditShopDialog> {
  final _formKey = GlobalKey<FormState>();
  final _storage = StorageService();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _city;
  late final TextEditingController _whatsapp;
  late final TextEditingController _merchantCode;
  late String _merchantProvider;
  bool? _womenLed;
  double? _pickupLat;
  double? _pickupLng;
  Uint8List? _newLogoBytes;
  String? _newLogoName;
  bool _saving = false;
  // Même règle qu'à la création (4 septembre 2026, nuit) : photo
  // obligatoire — ici une boutique déjà créée AVANT ce changement peut ne
  // pas en avoir, donc on vérifie la photo existante autant que la
  // nouvelle avant d'autoriser l'enregistrement.
  bool _logoMissingError = false;

  bool get _hasLogo => _newLogoBytes != null || (widget.shop.logoUrl != null && widget.shop.logoUrl!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final s = widget.shop;
    _name = TextEditingController(text: s.name);
    _description = TextEditingController(text: s.description ?? '');
    _city = TextEditingController(text: s.city ?? '');
    _whatsapp = TextEditingController(text: s.whatsappPhone ?? '');
    _merchantCode = TextEditingController(text: s.merchantCode ?? '');
    _merchantProvider = _kMerchantProviders.contains(s.merchantProvider) ? s.merchantProvider! : _kMerchantProviders.first;
    _womenLed = s.womenLed;
    _pickupLat = s.lat;
    _pickupLng = s.lng;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _whatsapp.dispose();
    _merchantCode.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _newLogoBytes = bytes;
      _newLogoName = picked.name;
      _logoMissingError = false;
    });
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    setState(() => _logoMissingError = !_hasLogo);
    if (!formOk || !_hasLogo) return;
    setState(() => _saving = true);
    try {
      String? logoUrl;
      if (_newLogoBytes != null) {
        final ext = (_newLogoName ?? '').contains('.') ? _newLogoName!.split('.').last : 'jpg';
        final path = _storage.ownedPath('${DateTime.now().millisecondsSinceEpoch}.$ext');
        logoUrl = await _storage.uploadPublic(bucket: 'shop-images', path: path, bytes: _newLogoBytes!);
      }
      await widget.vendor.updateMyShop(
        shopId: widget.shop.id,
        name: _name.text.trim(),
        description: _description.text.trim(),
        logoUrl: logoUrl,
        city: _city.text.trim(),
        whatsappPhone: _whatsapp.text.trim(),
        merchantCode: _merchantCode.text.trim(),
        merchantProvider: _merchantProvider,
        womenLed: _womenLed,
        lat: _pickupLat,
        lng: _pickupLng,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return AlertDialog(
      title: Text(t('shop_edit')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickLogo,
                    child: Stack(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.panel,
                            border: _logoMissingError ? Border.all(color: AppTheme.red, width: 1.5) : null,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _newLogoBytes != null
                              ? Image.memory(_newLogoBytes!, fit: BoxFit.cover)
                              : (widget.shop.logoUrl != null && widget.shop.logoUrl!.isNotEmpty)
                                  ? Image.network(widget.shop.logoUrl!, fit: BoxFit.cover)
                                  : const Icon(Icons.storefront_outlined, color: AppTheme.muted, size: 28),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.ink),
                            alignment: Alignment.center,
                            child: const Icon(Icons.edit, size: 13, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_logoMissingError) ...[
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('Photo required', style: TextStyle(fontSize: 12, color: AppTheme.red)),
                  ),
                ],
                const SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Shop name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
                const SizedBox(height: 12),
                TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City (optional)')),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _whatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'WhatsApp number'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                _MerchantCodeFields(
                  codeController: _merchantCode,
                  provider: _merchantProvider,
                  onProviderChanged: (v) => setState(() => _merchantProvider = v),
                ),
                _WomenLedField(
                  value: _womenLed,
                  onChanged: (v) => setState(() => _womenLed = v),
                ),
                const SizedBox(height: 16),
                _PickupLocationField(
                  initialLat: _pickupLat,
                  initialLng: _pickupLng,
                  onLocated: (pos) => setState(() {
                    _pickupLat = pos.$1;
                    _pickupLng = pos.$2;
                  }),
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
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Tableau de bord d'une boutique déjà créée — statut, infos, et gestion
/// de ses propres produits.
class _MyShopDashboard extends StatefulWidget {
  final VendorService vendor;
  final Shop shop;
  final VoidCallback onShopUpdated;
  final String? initialCategoryId;

  const _MyShopDashboard({required this.vendor, required this.shop, required this.onShopUpdated, this.initialCategoryId});

  @override
  State<_MyShopDashboard> createState() => _MyShopDashboardState();
}

class _MyShopDashboardState extends State<_MyShopDashboard> {
  final _catalog = CatalogService();
  late Future<List<Product>> _productsFuture;
  late Future<List<OrderModel>> _ordersFuture;
  late Future<int> _followerCountFuture;
  // 0 = Produits, 1 = Commandes — ajouté le 4 septembre 2026 : jusque-là,
  // une vendeuse en libre-service n'avait AUCUN moyen de voir ses commandes
  // ni de vérifier une capture de paiement, alors que l'app permet déjà à
  // un client de commander et de payer chez elle.
  int _tab = 0;
  // Espace vendeur plus confortable (6 septembre 2026) : trois compteurs en
  // haut, un filtre par statut sur les commandes, une recherche dans ses
  // propres produits. Rien de tout ça n'existait — il fallait faire défiler
  // toute la liste à la main.
  String _orderFilter = 'all';
  final _productSearch = TextEditingController();
  String _productQuery = '';

  @override
  void initState() {
    super.initState();
    _productsFuture = widget.vendor.fetchMyProducts(widget.shop.id);
    _ordersFuture = widget.vendor.fetchMyShopOrders(widget.shop.id);
    _followerCountFuture = _catalog.fetchShopFollowerCount(widget.shop.id);
    // Venu du parcours "Créer" (catégorie choisie avant même la connexion) —
    // on ouvre directement le formulaire d'ajout, catégorie déjà sélectionnée.
    if (widget.initialCategoryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAddProduct(initialCategoryId: widget.initialCategoryId));
    }
  }

  @override
  void dispose() {
    _productSearch.dispose();
    super.dispose();
  }

  void _refreshProducts() => setState(() => _productsFuture = widget.vendor.fetchMyProducts(widget.shop.id));
  void _refreshOrders() => setState(() => _ordersFuture = widget.vendor.fetchMyShopOrders(widget.shop.id));

  /// Ouvre le formulaire de modification (nom, photo, description, ville,
  /// WhatsApp) — ajouté le 4 septembre 2026 : `VendorService.updateMyShop()`
  /// existait déjà côté code mais aucun écran ne l'appelait, donc il n'y
  /// avait en pratique aucun moyen de changer la photo de la boutique (ni
  /// rien d'autre) une fois créée.
  Future<void> _editShop() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditShopDialog(vendor: widget.vendor, shop: widget.shop),
    );
    if (updated == true) widget.onShopUpdated();
  }

  /// Supprime la boutique elle-même (pas seulement un produit) — ajouté le
  /// 4 septembre 2026 : avant, seul l'admin pouvait supprimer une boutique.
  /// Nécessite le correctif RLS `shops_delete_owner_or_admin`
  /// (admin_patch.sql, même date) : sans lui, cet appel échoue avec une
  /// erreur de permission, affichée via le SnackBar ci-dessous.
  Future<void> _deleteShop() async {
    final t = context.read<SettingsController>().t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('shop_delete_confirm_title')),
        content: Text(t('shop_delete_confirm_message')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('shop_delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.vendor.deleteMyShop(widget.shop.id);
      widget.onShopUpdated();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openOrderDetail(OrderModel order) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _MyOrderDetailDialog(vendor: widget.vendor, order: order),
    );
    if (changed == true) _refreshOrders();
  }

  Future<void> _openAddProduct({String? initialCategoryId}) async {
    // Écran plein (pas un dialogue) depuis le 5 septembre 2026, nuit —
    // Emina : "essai aussi d'améliorer le design c'est un peu moins
    // moderne" : une petite boîte de dialogue avec des champs empilés est
    // moins moderne que le reste de l'app (comparer avec la création de
    // boutique, `_CreateShopView` — même mise en page maintenant).
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _MyProductScreen(vendor: widget.vendor, shopId: widget.shop.id, initialCategoryId: initialCategoryId)),
    );
    if (created == true) _refreshProducts();
  }

  Future<void> _openEditProduct(Product p) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _MyProductScreen(vendor: widget.vendor, shopId: widget.shop.id, existing: p)),
    );
    if (updated == true) _refreshProducts();
  }

  Future<void> _toggleVisible(Product p) async {
    await widget.vendor.setMyProductVisible(p.id, !p.isVisible);
    _refreshProducts();
  }

  Future<void> _delete(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.vendor.deleteMyProduct(p.id);
    _refreshProducts();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final shop = widget.shop;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShopAvatar(name: shop.name, logoUrl: shop.logoUrl, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shop.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: shop.isVisible ? const Color(0xFFE3F3E9) : const Color(0xFFF3EEE6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      shop.isVisible ? 'Boutique active' : "En attente de validation par l'administration",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: shop.isVisible ? const Color(0xFF2E9C5B) : const Color(0xFF8A6D2F),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Abonnés — façon Oskelly (4 septembre 2026, voir
                  // catalog_service.dart pour pourquoi ça passe par une
                  // fonction plutôt qu'une lecture directe de la table).
                  FutureBuilder<int>(
                    future: _followerCountFuture,
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Text(
                        '$count ${count > 1 ? t('shop_followers') : t('shop_follower')}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Modifier / Supprimer la boutique — ajouté le 4 septembre 2026 :
            // avant, aucun des deux n'était possible depuis l'application.
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.ink2),
              onSelected: (value) {
                if (value == 'edit') _editShop();
                if (value == 'delete') _deleteShop();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(t('shop_edit'))),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(t('shop_delete'), style: const TextStyle(color: AppTheme.red)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Les trois chiffres qui comptent pour une vendeuse, en haut de son
        // tableau de bord (6 septembre 2026).
        _DashboardCounters(
          productsFuture: _productsFuture,
          ordersFuture: _ordersFuture,
          followersFuture: _followerCountFuture,
        ),
        const SizedBox(height: 16),
        // Entrée vers le tableau de bord fintech (20 septembre 2026).
        // Mise en avant plutôt que cachée dans un menu : c'est l'écran
        // qui porte toute la valeur « comprendre son activité ».
        _AnalyticsEntryCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VendorDashboardScreen(
                shopId: widget.shop.id,
                shopName: widget.shop.name,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(color: AppTheme.line, height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _DashboardTabButton(label: 'Produits', active: _tab == 0, onTap: () => setState(() => _tab = 0))),
            const SizedBox(width: 8),
            Expanded(child: _DashboardTabButton(label: 'Commandes', active: _tab == 1, onTap: () => setState(() => _tab = 1))),
          ],
        ),
        const SizedBox(height: 20),
        if (_tab == 1) ...[
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final entry in const [
                  ['all', 'Toutes'],
                  ['pending', 'En attente'],
                  ['confirmed', 'Confirmed'],
                  ['preparing', 'Preparing'],
                  ['delivering', 'En livraison'],
                  ['delivered', 'Delivered'],
                  ['cancelled', 'Cancelled'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: entry[1],
                      active: _orderFilter == entry[0],
                      onTap: () => setState(() => _orderFilter = entry[0]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<OrderModel>>(
            future: _ordersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              final all = snapshot.data ?? [];
              final orders = _orderFilter == 'all' ? all : all.where((o) => o.status == _orderFilter).toList();
              if (orders.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _orderFilter == 'all' ? 'No orders yet.' : 'No orders in this state.',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: orders.map((o) => _MyOrderRow(order: o, onTap: () => _openOrderDetail(o))).toList(),
              );
            },
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('My products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              TextButton.icon(
                onPressed: _openAddProduct,
                icon: const Icon(Icons.add, size: 18, color: AppTheme.ink),
                label: const Text('Add', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Recherche dans ses propres produits (6 septembre 2026) : au-delà
          // d'une vingtaine d'articles, retrouver le bon dans la liste
          // devenait pénible.
          TextField(
            controller: _productSearch,
            onChanged: (v) => setState(() => _productQuery = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search my products',
              prefixIcon: const Icon(Icons.search, size: 19, color: AppTheme.muted),
              isDense: true,
              suffixIcon: _productQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18, color: AppTheme.muted),
                      onPressed: () => setState(() {
                        _productSearch.clear();
                        _productQuery = '';
                      }),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Product>>(
            future: _productsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              final all = snapshot.data ?? [];
              final products = _productQuery.isEmpty
                  ? all
                  : all.where((p) => p.name.toLowerCase().contains(_productQuery)).toList();
              if (products.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _productQuery.isEmpty ? 'Aucun produit pour le moment.' : 'Aucun produit ne correspond.',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: products
                    .map((p) => _MyProductRow(
                          product: p,
                          onToggleVisible: () => _toggleVisible(p),
                          onEdit: () => _openEditProduct(p),
                          onDelete: () => _delete(p),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Petit interrupteur "Produits / Commandes" en haut du tableau de bord —
/// pas de vrai `TabBar` (pas de contenu à faire défiler horizontalement,
/// juste deux sections qui s'excluent) : deux boutons pleine largeur, l'un
/// des deux souligné en encre.
class _DashboardTabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DashboardTabButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? AppTheme.ink : Colors.transparent, width: 2))),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? AppTheme.ink : AppTheme.muted),
        ),
      ),
    );
  }
}

/// Bandeau d'entrée vers [VendorDashboardScreen].
class _AnalyticsEntryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AnalyticsEntryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.line),
        ),
        child: const Row(
          children: [
            Icon(Icons.show_chart, size: 20, color: AppTheme.copper),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mon activité',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  SizedBox(height: 2),
                  Text('Ventes, encaissements et préparation financière',
                      style: TextStyle(fontSize: 12, color: AppTheme.ink2)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}

class _MyProductRow extends StatelessWidget {
  final Product product;
  final VoidCallback onToggleVisible;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MyProductRow({required this.product, required this.onToggleVisible, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 48, height: 48, child: AppImage(url: p.coverImage, fit: BoxFit.cover, thumbnail: true)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                const SizedBox(height: 2),
                Text(Money.format(p.price), style: const TextStyle(fontSize: 12.5, color: AppTheme.ink2)),
              ],
            ),
          ),
          Switch(value: p.isVisible, activeColor: AppTheme.ink, onChanged: (_) => onToggleVisible()),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.ink2), onPressed: onEdit),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.red), onPressed: onDelete),
        ],
      ),
    );
  }
}

/// Fiche produit plein écran (remplace l'ancienne boîte de dialogue le
/// 5 septembre 2026, nuit — Emina : "essaie aussi d'améliorer le design,
/// c'est un peu moins moderne", même esprit que [_CreateShopView]) :
/// - la "Marque" est le premier champ du formulaire (Emina : "tu dois
///   changer ce qui apparaît pour le vendeur quand il ajoute un nouveau
///   produit, premièrement — à la place du nom du produit / brand du
///   produit") ;
/// - une section "Photos" permet à la vendeuse de choisir elle-même quelle
///   photo sert de couverture et dans quel ordre elles apparaissent (Emina :
///   "le vendeur il peut contrôler la photo, c'est à dire ce que le vendeur
///   il veut apparaître pour le client").
///
/// En modification, les photos existent déjà en base : chaque suppression
/// ou changement d'ordre est appliqué tout de suite. En création, il n'y a
/// pas encore d'identifiant produit : les photos choisies sont mises en
/// attente localement puis envoyées, dans l'ordre choisi, juste après la
/// création du produit.
class _MyProductScreen extends StatefulWidget {
  final VendorService vendor;
  final String shopId;
  final Product? existing;
  final String? initialCategoryId;

  const _MyProductScreen({required this.vendor, required this.shopId, this.existing, this.initialCategoryId});

  @override
  State<_MyProductScreen> createState() => _MyProductScreenState();
}

class _MyProductScreenState extends State<_MyProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _catalog = CatalogService();
  final _storage = StorageService();
  late final TextEditingController _brand;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _compareAtPrice;
  late final TextEditingController _stock;
  late final TextEditingController _optionName;
  late final TextEditingController _optionValues;
  // Variantes — 6 septembre 2026 (Emina : "si quelqu'un vend du maquillage
  // il existe des couleurs pour le concealer, le vendeur doit mettre les
  // couleurs possibles, ou la size pour les chaussures... et c'est aussi
  // obligatoire").
  //
  // Obligatoire, SAUF si la vendeuse coche explicitement "ce produit n'a
  // pas de variantes" : un parfum ou une crème n'a ni taille ni teinte, et
  // rendre le champ obligatoire pour tout aurait bloqué ces produits-là.
  // La case doit être cochée volontairement — on ne peut pas enregistrer en
  // laissant simplement les champs vides.
  bool _noVariants = false;
  String _optionType = 'text';
  // Teintes choisies, dans l'ordre de sélection, et celles marquées
  // épuisées. Plus de nom à saisir depuis le 10 septembre 2026 : il vient
  // de la palette.
  final List<String> _selectedHex = [];
  final Set<String> _soldOutHex = {};
  String? _optionsError;
  String? _categoryId;
  List<Category> _categories = [];
  bool _saving = false;
  bool _loadingImages = false;

  // Modification : photos déjà en base.
  List<ProductImage> _existingImages = [];

  // Création : photos choisies localement, envoyées après la création.
  final List<Uint8List> _queuedBytes = [];
  final List<String> _queuedNames = [];
  // Point à garder visible sur chaque photo en attente, et son zoom — voir
  // `PhotoPositionScreen` (widgets.dart — 5 septembre 2026, nuit).
  final List<double> _queuedFocalX = [];
  final List<double> _queuedFocalY = [];
  final List<double> _queuedZoom = [];

  bool get _isEditing => widget.existing != null;

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
    _optionName = TextEditingController(text: p?.optionName ?? '');
    _optionValues = TextEditingController(text: (p?.optionValues ?? const []).join(', '));
    _optionType = p?.optionType == 'color' ? 'color' : 'text';
    if (p != null && p.optionType == 'color') {
      for (var i = 0; i < p.optionColors.length; i++) {
        final hex = p.optionColors[i];
        _selectedHex.add(hex);
        if (i < p.optionSoldOut.length && p.optionSoldOut[i]) _soldOutHex.add(hex);
      }
    }
    // Un produit existant sans option a forcément été enregistré sans
    // variantes : la case est donc déjà cochée à l'ouverture, sinon la
    // vendeuse ne pourrait plus rien modifier sans en inventer une.
    _noVariants = p != null && (p.optionName == null || p.optionName!.trim().isEmpty);
    _categoryId = p?.categoryId ?? widget.initialCategoryId;
    _catalog.fetchCategories().then((cats) {
      if (mounted) setState(() => _categories = cats);
    });
    if (_isEditing) _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _loadingImages = true);
    try {
      final images = await widget.vendor.fetchMyProductImages(widget.existing!.id);
      if (!mounted) return;
      setState(() {
        _existingImages = images;
        _loadingImages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingImages = false);
    }
  }

  @override
  void dispose() {
    _brand.dispose();
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _compareAtPrice.dispose();
    _stock.dispose();
    _optionName.dispose();
    _optionValues.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    // Demande à la vendeuse de choisir le point à toujours garder visible,
    // ET le zoom, AVANT d'ajouter/envoyer la photo (5 septembre 2026 —
    // Emina : "tu dois donner à le vendeur de contrôler la photo" puis,
    // après un premier essai sans zoom : "ça reste un problème que je ne
    // peux pas zoomer ni dezoomer, [...] la point la plus importante pour
    // moi"). Si elle annule, la photo n'est pas ajoutée.
    if (!mounted) return;
    final result = await Navigator.of(context).push<(double, double, double)>(
      MaterialPageRoute(builder: (_) => PhotoPositionScreen(bytes: bytes)),
    );
    if (result == null) return;
    if (!_isEditing) {
      setState(() {
        _queuedBytes.add(bytes);
        _queuedNames.add(picked.name);
        _queuedFocalX.add(result.$1);
        _queuedFocalY.add(result.$2);
        _queuedZoom.add(result.$3);
      });
      return;
    }
    // En modification, le produit existe déjà : on envoie la photo tout de
    // suite plutôt que de la mettre en attente.
    setState(() => _loadingImages = true);
    try {
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final path = _storage.ownedPath('${widget.existing!.id}/${DateTime.now().millisecondsSinceEpoch}.$ext');
      final url = await _storage.uploadPublic(bucket: 'product-images', path: path, bytes: bytes);
      await widget.vendor.addMyProductImage(
        productId: widget.existing!.id,
        url: url,
        sortOrder: _existingImages.length,
        focalX: result.$1,
        focalY: result.$2,
        zoom: result.$3,
      );
      await _loadImages();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingImages = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _removeQueuedPhoto(int index) {
    setState(() {
      _queuedBytes.removeAt(index);
      _queuedNames.removeAt(index);
      _queuedFocalX.removeAt(index);
      _queuedFocalY.removeAt(index);
      _queuedZoom.removeAt(index);
    });
  }

  void _moveQueuedPhoto(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _queuedBytes.length) return;
    setState(() {
      _queuedBytes.insert(target, _queuedBytes.removeAt(index));
      _queuedNames.insert(target, _queuedNames.removeAt(index));
      _queuedFocalX.insert(target, _queuedFocalX.removeAt(index));
      _queuedFocalY.insert(target, _queuedFocalY.removeAt(index));
      _queuedZoom.insert(target, _queuedZoom.removeAt(index));
    });
  }

  /// Repositionne (point + zoom) une photo déjà en attente (pas encore
  /// envoyée) — rouvre [PhotoPositionScreen] avec ses valeurs actuelles.
  Future<void> _repositionQueuedPhoto(int index) async {
    final result = await Navigator.of(context).push<(double, double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoPositionScreen(
          bytes: _queuedBytes[index],
          initialFocalX: _queuedFocalX[index],
          initialFocalY: _queuedFocalY[index],
          initialZoom: _queuedZoom[index],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _queuedFocalX[index] = result.$1;
      _queuedFocalY[index] = result.$2;
      _queuedZoom[index] = result.$3;
    });
  }

  /// Repositionne (point + zoom) une photo déjà en base — enregistrée tout
  /// de suite.
  Future<void> _repositionExistingPhoto(ProductImage image) async {
    final result = await Navigator.of(context).push<(double, double, double)>(
      MaterialPageRoute(
        builder: (_) => PhotoPositionScreen(
          url: image.url,
          initialFocalX: image.focalX,
          initialFocalY: image.focalY,
          initialZoom: image.zoom,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _loadingImages = true);
    try {
      await widget.vendor.updateMyProductImageFocal(imageId: image.id, focalX: result.$1, focalY: result.$2, zoom: result.$3);
      await _loadImages();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingImages = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteExistingPhoto(ProductImage image) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('This photo will be removed from the product.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loadingImages = true);
    try {
      await widget.vendor.deleteMyProductImage(image.id);
      final remaining = _existingImages.where((i) => i.id != image.id).map((i) => i.id).toList();
      await widget.vendor.reorderMyProductImages(remaining);
      await _loadImages();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingImages = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _moveExistingPhoto(int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= _existingImages.length) return;
    final ids = _existingImages.map((i) => i.id).toList();
    ids.insert(target, ids.removeAt(index));
    setState(() => _loadingImages = true);
    try {
      await widget.vendor.reorderMyProductImages(ids);
      await _loadImages();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingImages = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// `null` si tout va bien, sinon le message à afficher.
  String? _validateVariants() {
    if (_noVariants) return null;
    if (_optionName.text.trim().isEmpty) {
      return "Give the option a name (Size, Color...), or check \u201cthis product has no variants\u201d.";
    }
    if (_optionType == 'color') {
      if (_selectedHex.isEmpty) return 'Touche au moins une teinte dans la palette.';
    } else {
      final values = _optionValues.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty);
      if (values.isEmpty) return 'Ajoute au moins un choix (ex : 36, 37, 38).';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Variantes obligatoires, sauf case cochée (6 septembre 2026). La
    // vérification est ici plutôt que dans un `validator` : les teintes ne
    // sont pas un champ de formulaire classique mais une liste dynamique.
    final variantsError = _validateVariants();
    setState(() => _optionsError = variantsError);
    if (variantsError != null) return;
    setState(() => _saving = true);
    try {
      final price = double.parse(_price.text.trim().replaceAll(',', '.'));
      final compareAtText = _compareAtPrice.text.trim();
      final compareAtPrice = compareAtText.isEmpty ? null : double.tryParse(compareAtText.replaceAll(',', '.'));
      final stock = int.tryParse(_stock.text.trim()) ?? 0;
      // Options (taille, couleur, ...) — valeurs séparées par une virgule,
      // espaces retirés, vides ignorées (5 septembre 2026).
      final optionNameText = _optionName.text.trim();
      // Le nom de chaque teinte vient de la palette : plus aucun risque
      // d'avoir une liste de choix vide, qui rendait le produit
      // impossible à commander (10 septembre 2026).
      final optionValuesList = _optionType == 'color'
          ? [for (final hex in _selectedHex) swatchName(hex)]
          : _optionValues.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      final optionColorsList = _optionType == 'color' ? List<String>.from(_selectedHex) : <String>[];
      final optionSoldOutList =
          _optionType == 'color' ? [for (final hex in _selectedHex) _soldOutHex.contains(hex)] : <bool>[];
      final hasOptions = !_noVariants && optionNameText.isNotEmpty && optionValuesList.isNotEmpty;
      final brandText = _brand.text.trim();
      String productId;
      if (widget.existing == null) {
        productId = await widget.vendor.createMyProduct(
          shopId: widget.shopId,
          categoryId: _categoryId,
          name: _name.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          price: price,
          compareAtPrice: compareAtPrice,
          stock: stock,
          optionName: hasOptions ? optionNameText : null,
          optionValues: hasOptions ? optionValuesList : const [],
          optionType: hasOptions ? _optionType : 'text',
          optionColors: hasOptions ? optionColorsList : const [],
          optionSoldOut: hasOptions ? optionSoldOutList : const [],
          brand: brandText.isEmpty ? null : brandText,
        );
        // Envoi des photos mises en attente, dans l'ordre choisi par la
        // vendeuse (5 septembre 2026, nuit).
        for (var i = 0; i < _queuedBytes.length; i++) {
          final name = _queuedNames[i];
          final ext = name.contains('.') ? name.split('.').last : 'jpg';
          final path = _storage.ownedPath('$productId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext');
          final url = await _storage.uploadPublic(bucket: 'product-images', path: path, bytes: _queuedBytes[i]);
          await widget.vendor.addMyProductImage(
            productId: productId,
            url: url,
            sortOrder: i,
            focalX: _queuedFocalX[i],
            focalY: _queuedFocalY[i],
            zoom: _queuedZoom[i],
          );
        }
      } else {
        productId = widget.existing!.id;
        await widget.vendor.updateMyProduct(
          id: productId,
          name: _name.text.trim(),
          description: _description.text.trim(),
          price: price,
          compareAtPrice: compareAtPrice,
          clearCompareAtPrice: compareAtPrice == null,
          stock: stock,
          optionName: hasOptions ? optionNameText : '',
          clearOptionName: !hasOptions,
          optionValues: hasOptions ? optionValuesList : const [],
          optionType: hasOptions ? _optionType : 'text',
          optionColors: hasOptions ? optionColorsList : const [],
          optionSoldOut: hasOptions ? optionSoldOutList : const [],
          brand: brandText.isEmpty ? '' : brandText,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        title: Text(
          _isEditing ? 'Modifier le produit' : 'Nouveau produit',
          style: const TextStyle(color: AppTheme.ink, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Photos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              const SizedBox(height: 4),
              const Text(
                "The first photo is the one shown on the product page and in listings — use the arrows to reorder, and tap a photo to choose the part to always keep visible.",
                style: TextStyle(fontSize: 12, color: AppTheme.ink2, height: 1.4),
              ),
              const SizedBox(height: 12),
              _buildPhotosSection(),
              const SizedBox(height: 24),
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Brand (optional — otherwise your shop name is shown)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Product name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 12),
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
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 0) return 'Stock invalide';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _compareAtPrice,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Crossed-out price (optional)'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  return double.tryParse(v.trim().replaceAll(',', '.')) == null ? 'Prix invalide' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 20),
              _buildVariantsSection(),
              const SizedBox(height: 26),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('SAVE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Variantes du produit — taille pour une chaussure, teinte pour du
  /// maquillage (6 septembre 2026, captures "Concealer Color" / "Lipliner
  /// color" envoyées par Emina).
  ///
  /// En mode "Couleur", chaque teinte a un vrai carré de couleur, choisi
  /// dans une palette, plus une case "épuisée" — c'est le trait en
  /// diagonale des captures : la teinte reste visible pour la cliente mais
  /// ne peut pas être commandée.
  Widget _buildVariantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Variants', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
        const SizedBox(height: 4),
        const Text(
          'Une taille pour une chaussure, une teinte pour du maquillage. '
          'La cliente devra en choisir une avant de commander.',
          style: TextStyle(fontSize: 12, color: AppTheme.ink2, height: 1.35),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _noVariants,
          onChanged: (v) => setState(() {
            _noVariants = v ?? false;
            _optionsError = null;
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text("Ce produit n'a pas de variantes", style: TextStyle(fontSize: 13.5, color: AppTheme.ink)),
        ),
        if (!_noVariants) ...[
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'text', label: Text('Text'), icon: Icon(Icons.straighten, size: 16)),
              ButtonSegment(value: 'color', label: Text('Color'), icon: Icon(Icons.palette_outlined, size: 16)),
            ],
            selected: {_optionType},
            onSelectionChanged: (set) => setState(() {
              _optionType = set.first;
              _optionsError = null;
              // Un nom par défaut, pour ne pas laisser le champ vide : la
              // vendeuse peut le remplacer.
              if (_optionName.text.trim().isEmpty) {
                _optionName.text = _optionType == 'color' ? 'Couleur' : 'Taille';
              }
            }),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _optionName,
            decoration: const InputDecoration(labelText: "Nom de l'option (ex : Taille, Couleur)"),
          ),
          const SizedBox(height: 12),
          if (_optionType == 'text')
            TextFormField(
              controller: _optionValues,
              decoration: const InputDecoration(labelText: 'Options, comma-separated (e.g. 36, 37, 38)'),
            )
          else ...[
            // **Refait le 10 septembre 2026** : plus rien à taper. La
            // vendeuse touche les teintes qu'elle vend dans la palette,
            // point. Le nom de chaque teinte vient de la palette
            // elle-même (voir [kSwatchPalette]) — avant, une teinte laissée
            // sans nom était filtrée à l'enregistrement, ce qui rendait le
            // produit impossible à commander côté cliente.
            const Text(
              'Touche les teintes que tu vends.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.ink2),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final swatch in kSwatchPalette)
                  _PaletteSwatch(
                    swatch: swatch,
                    selected: _selectedHex.contains(swatch.hex),
                    onTap: () => setState(() {
                      if (_selectedHex.contains(swatch.hex)) {
                        _selectedHex.remove(swatch.hex);
                        _soldOutHex.remove(swatch.hex);
                      } else {
                        _selectedHex.add(swatch.hex);
                      }
                      _optionsError = null;
                    }),
                  ),
              ],
            ),
            if (_selectedHex.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Chosen shades — check the ones that are out of stock',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.ink),
              ),
              const SizedBox(height: 8),
              for (final hex in _selectedHex)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: hexToColor(hex),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.line),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(swatchName(hex), style: const TextStyle(fontSize: 13.5, color: AppTheme.ink))),
                      const Text('Out of stock', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
                      Checkbox(
                        value: _soldOutHex.contains(hex),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _soldOutHex.add(hex);
                          } else {
                            _soldOutHex.remove(hex);
                          }
                        }),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18, color: AppTheme.muted),
                        onPressed: () => setState(() {
                          _selectedHex.remove(hex);
                          _soldOutHex.remove(hex);
                        }),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
        if (_optionsError != null) ...[
          const SizedBox(height: 8),
          Text(_optionsError!, style: const TextStyle(fontSize: 12.5, color: AppTheme.red)),
        ],
      ],
    );
  }

  Widget _buildPhotosSection() {
    final tiles = <Widget>[];
    if (_isEditing) {
      for (var i = 0; i < _existingImages.length; i++) {
        final image = _existingImages[i];
        tiles.add(_PhotoTile(
          bytes: null,
          url: image.url,
          alignment: Alignment(image.focalX * 2 - 1, image.focalY * 2 - 1),
          zoom: image.zoom,
          isCover: i == 0,
          onMoveLeft: i > 0 ? () => _moveExistingPhoto(i, -1) : null,
          onMoveRight: i < _existingImages.length - 1 ? () => _moveExistingPhoto(i, 1) : null,
          onDelete: () => _deleteExistingPhoto(image),
          onReposition: () => _repositionExistingPhoto(image),
        ));
      }
    } else {
      for (var i = 0; i < _queuedBytes.length; i++) {
        tiles.add(_PhotoTile(
          bytes: _queuedBytes[i],
          url: null,
          alignment: Alignment(_queuedFocalX[i] * 2 - 1, _queuedFocalY[i] * 2 - 1),
          zoom: _queuedZoom[i],
          isCover: i == 0,
          onMoveLeft: i > 0 ? () => _moveQueuedPhoto(i, -1) : null,
          onMoveRight: i < _queuedBytes.length - 1 ? () => _moveQueuedPhoto(i, 1) : null,
          onDelete: () => _removeQueuedPhoto(i),
          onReposition: () => _repositionQueuedPhoto(i),
        ));
      }
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...tiles,
        GestureDetector(
          onTap: _loadingImages ? null : _pickPhoto,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.line),
            ),
            alignment: Alignment.center,
            child: _loadingImages
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_a_photo_outlined, color: AppTheme.muted, size: 24),
          ),
        ),
      ],
    );
  }
}

/// Une vignette dans le gestionnaire de photos d'un produit — croix pour
/// supprimer, flèches pour déplacer, bandeau "Couverture" sur la première
/// (5 septembre 2026, nuit). Touche la photo elle-même (en dehors des
/// boutons) pour la repositionner (`onReposition` — voir
/// [PhotoPositionScreen]) : la vignette applique déjà `alignment` pour que
/// la vendeuse voie tout de suite l'effet de son choix.
class _PhotoTile extends StatelessWidget {
  final Uint8List? bytes;
  final String? url;
  final Alignment alignment;
  final double zoom;
  final bool isCover;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback onDelete;
  final VoidCallback onReposition;

  const _PhotoTile({
    required this.bytes,
    required this.url,
    required this.alignment,
    required this.zoom,
    required this.isCover,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onDelete,
    required this.onReposition,
  });

  @override
  Widget build(BuildContext context) {
    final image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover, alignment: alignment)
        : Image.network(url!, fit: BoxFit.cover, alignment: alignment);
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCover ? AppTheme.ink : AppTheme.line, width: isCover ? 1.5 : 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: onReposition,
            child: zoom == 1.0 ? image : Transform.scale(scale: zoom, alignment: alignment, child: image),
          ),
          if (isCover)
            Positioned(
              left: 0,
              bottom: 0,
              right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                child: const Text('Cover', style: TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                alignment: Alignment.center,
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
          // Indice visuel : la photo entière est touchable pour la
          // repositionner (`onReposition`) — sans cette icône, rien ne
          // suggérerait que la photo réagit au toucher.
          Positioned(
            left: 2,
            bottom: 2,
            child: IgnorePointer(
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                alignment: Alignment.center,
                child: const Icon(Icons.control_camera, size: 12, color: Colors.white),
              ),
            ),
          ),
          if (onMoveLeft != null || onMoveRight != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _arrowButton(Icons.chevron_left, onMoveLeft),
                  _arrowButton(Icons.chevron_right, onMoveRight),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback? onTap) {
    if (onTap == null) return const SizedBox(width: 18, height: 18);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
        alignment: Alignment.center,
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }
}

/// Une ligne "commande" — nom du client, total, statut. Tape dessus pour
/// voir le détail (articles, coordonnées, capture de paiement) et changer
/// le statut.
class _MyOrderRow extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const _MyOrderRow({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.clientFullName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                  const SizedBox(height: 3),
                  Text(Money.format(order.total), style: const TextStyle(fontSize: 12.5, color: AppTheme.ink2)),
                ],
              ),
            ),
            OrderStatusChip(status: order.status, label: t('order_status_${order.status}')),
          ],
        ),
      ),
    );
  }
}

/// Détail d'une commande côté vendeuse — mêmes informations que côté admin
/// (`lib/admin/orders_admin_screen.dart`), en thème clair : articles,
/// coordonnées du client, capture de paiement (URL signée, le bucket est
/// privé), changement de statut.
class _MyOrderDetailDialog extends StatefulWidget {
  final VendorService vendor;
  final OrderModel order;

  const _MyOrderDetailDialog({required this.vendor, required this.order});

  @override
  State<_MyOrderDetailDialog> createState() => _MyOrderDetailDialogState();
}

class _MyOrderDetailDialogState extends State<_MyOrderDetailDialog> {
  static const _statuses = ['pending', 'confirmed', 'preparing', 'delivering', 'delivered', 'cancelled'];

  late Future<List<OrderItemModel>> _itemsFuture;
  late String _status;
  String _paymentStatus = 'submitted';
  double? _amountReceived;
  bool _saving = false;
  String? _proofSignedUrl;
  bool _loadingProof = false;

  @override
  void initState() {
    super.initState();
    _itemsFuture = widget.vendor.fetchOrderItems(widget.order.id);
    _status = widget.order.status;
    _paymentStatus = widget.order.paymentStatus;
    _amountReceived = widget.order.paymentAmountReceived;
  }

  /// Vérification du paiement par la vendeuse (20 septembre 2026).
  ///
  /// L'application ne vérifie rien toute seule : aucun fournisseur
  /// mauritanien n'expose d'API de vérification aujourd'hui. C'est la
  /// vendeuse qui retrouve la référence dans l'historique de son
  /// application bancaire, et c'est pour ça que le statut par défaut est
  /// « soumise » et jamais « vérifiée ».
  /// Demande le montant reçu avant de confirmer (21 septembre 2026).
  ///
  /// C'est le seul moment où quelqu'un a sous les yeux À LA FOIS la
  /// commande et le relevé bancaire. Le champ est prérempli avec le total
  /// attendu : dans le cas normal, il n'y a qu'à valider ; dans le cas qui
  /// nous intéresse, la vendeuse corrige et l'écart devient visible.
  Future<double?> _askAmount() async {
    final controller = TextEditingController(
      text: widget.order.total.toStringAsFixed(0),
    );
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Montant reçu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quel montant avez-vous réellement reçu pour cette commande ? '
              'Le total attendu est ${Money.format(widget.order.total)}.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.ink2),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant reçu'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              Navigator.of(context).pop(v);
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  Future<void> _setPayment(String status) async {
    double? amount;
    if (status == 'verified') {
      amount = await _askAmount();
      // Annulé : on ne change rien. Confirmer un paiement sans avoir
      // relevé le montant ferait exactement ce qu'on cherche à éviter.
      if (amount == null || !mounted) return;
    }
    final previous = _paymentStatus;
    final previousAmount = _amountReceived;
    setState(() {
      _paymentStatus = status;
      _amountReceived = status == 'verified' ? amount : null;
    });
    try {
      await widget.vendor
          .setPaymentStatus(widget.order.id, status, amountReceived: amount);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentStatus = previous;
        _amountReceived = previousAmount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _loadProof() async {
    final path = widget.order.paymentProofUrl;
    if (path == null || path.isEmpty) return;
    setState(() => _loadingProof = true);
    try {
      final url = await StorageService().signedPaymentProofUrl(path);
      if (mounted) setState(() => _proofSignedUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loadingProof = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.vendor.updateOrderStatus(widget.order.id, _status);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    final order = widget.order;
    return AlertDialog(
      title: Text(order.clientFullName),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.clientPhone, style: const TextStyle(fontSize: 13, color: AppTheme.ink2)),
              if ((order.clientCity ?? '').isNotEmpty || (order.clientAddress ?? '').isNotEmpty)
                Text(
                  [order.clientAddress, order.clientCity].where((s) => s != null && s.isNotEmpty).join(', '),
                  style: const TextStyle(fontSize: 13, color: AppTheme.ink2),
                ),
              const SizedBox(height: 16),
              const Text('Items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink)),
              const SizedBox(height: 6),
              FutureBuilder<List<OrderItemModel>>(
                future: _itemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
                  }
                  final items = snapshot.data ?? [];
                  return Column(
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${item.productName} × ${item.quantity}', style: const TextStyle(fontSize: 13, color: AppTheme.ink))),
                              Text(Money.format(item.subtotal), style: const TextStyle(fontSize: 13, color: AppTheme.ink)),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(height: 20, color: AppTheme.line),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                  Text(Money.format(order.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                ],
              ),
              const SizedBox(height: 16),
              // Paiement par code marchand (6 septembre 2026) : la cliente
              // paie avec le code marchand de la boutique et saisit la
              // référence renvoyée par sa banque. Elle est unique en base :
              // la même ne peut pas servir pour deux commandes. Il reste à
              // la vendeuse à la retrouver dans son historique bancaire
              // avant de confirmer.
              const Text('Payment reference', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink)),
              const SizedBox(height: 6),
              if (order.paymentReference == null || order.paymentReference!.isEmpty)
                const Text('No code (order placed before code-based payment).', style: TextStyle(fontSize: 12.5, color: AppTheme.muted))
              else
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        order.paymentReference!,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppTheme.ink),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_outlined, size: 18, color: AppTheme.ink2),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: order.paymentReference!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied.')),
                        );
                      },
                    ),
                  ],
                ),
              // Statut du paiement (20 septembre 2026). Couleur ET texte,
              // jamais la couleur seule : une information portée par la
              // seule couleur est invisible pour une partie des gens.
              if (order.paymentReference != null && order.paymentReference!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      switch (_paymentStatus) {
                        'verified' => Icons.check_circle_outline,
                        'rejected' => Icons.cancel_outlined,
                        _ => Icons.schedule_outlined,
                      },
                      size: 16,
                      color: switch (_paymentStatus) {
                        'verified' => AppTheme.whatsapp,
                        'rejected' => AppTheme.red,
                        _ => AppTheme.stockWarn,
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        switch (_paymentStatus) {
                          'verified' => 'Paiement confirmé',
                          'rejected' => 'Référence introuvable en banque',
                          _ => 'Référence soumise — à vérifier',
                        },
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.ink2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Retrouvez cette référence dans l\'historique de votre '
                  'application bancaire, puis confirmez ici.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.muted, height: 1.3),
                ),
                // Écart entre le montant reçu et le total dû
                // (21 septembre 2026). Une référence de paiement peut être
                // authentique, unique, et correspondre malgré tout à une
                // transaction d'un tout autre montant : c'est le seul
                // contrôle que ni l'index unique ni le recalcul des totaux
                // ne couvraient.
                if (_amountReceived != null) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final gap = _amountReceived! - order.total;
                    final off = gap.abs() > 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: off ? AppTheme.redTint : AppTheme.panel,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            off ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            size: 16,
                            color: off ? AppTheme.red : AppTheme.whatsapp,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              off
                                  ? 'Écart de ${Money.format(gap.abs())} '
                                      '${gap > 0 ? 'en trop' : 'manquant'} — '
                                      'reçu ${Money.format(_amountReceived!)} '
                                      'pour ${Money.format(order.total)}'
                                  : 'Montant conforme — ${Money.format(_amountReceived!)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: off ? FontWeight.w700 : FontWeight.w400,
                                color: off ? AppTheme.red : AppTheme.ink2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _paymentStatus == 'verified'
                            ? null
                            : () => _setPayment('verified'),
                        child: const Text('Je l\'ai reçu'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _paymentStatus == 'rejected'
                            ? null
                            : () => _setPayment('rejected'),
                        child: const Text('Introuvable'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text('Delivery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink)),
              const SizedBox(height: 6),
              if (order.deliveryMapUrl == null)
                const Text('No location shared.', style: TextStyle(fontSize: 12.5, color: AppTheme.muted))
              else
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(order.deliveryMapUrl!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
              const SizedBox(height: 16),
              // Conservé pour les commandes passées AVANT le 6 septembre
              // 2026, qui ont encore une capture : masqué s'il n'y en a pas.
              if (order.paymentProofUrl != null && order.paymentProofUrl!.isNotEmpty) ...[
                const Text('Payment screenshot (old order)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink)),
                const SizedBox(height: 6),
                if (_proofSignedUrl == null)
                OutlinedButton.icon(
                  onPressed: _loadingProof ? null : _loadProof,
                  icon: _loadingProof
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined, size: 18),
                  label: const Text('View screenshot'),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    _proofSignedUrl!,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text('Image not found.', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _status,
                items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(t('order_status_$s')))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Close')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save status'),
        ),
      ],
    );
  }
}

/// Banques mobiles mauritaniennes qui proposent le paiement commerçant.
/// Liste simple et modifiable : le code marchand est saisi à la main, l'app
/// ne dialogue avec aucune de ces banques (aucune ne publie d'API
/// développeur ouverte à ce jour).
/// Déclaration d'impact facultative (20 septembre 2026).
///
/// Boutigui est ouvert à tous les entrepreneurs mauritaniens ; les femmes en
/// sont le public principal. Cette case sert UNIQUEMENT à mesurer l'impact
/// du produit — c'est écrit sous la case, en toutes lettres, parce qu'on
/// demande là une information personnelle et que la personne a le droit de
/// savoir à quoi elle sert avant de répondre.
///
/// Trois règles tenues dans le code :
///
///  * facultative — `null` est une réponse valable, et la case part de là ;
///  * sans effet — aucune fonctionnalité, aucun classement, aucune
///    visibilité ne change selon la réponse ;
///  * hors du score — `analytics_service._readiness()` ne lit que
///    l'activité commerciale. Faire peser un attribut personnel protégé
///    sur un signal qui peut orienter un financement, ce serait de la
///    discrimination à l'octroi de crédit.
class _WomenLedField extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _WomenLedField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            // Trois états : cochée, décochée, non renseignée. Un simple
            // `Checkbox` ne sait pas dire « je préfère ne pas répondre ».
            onTap: () => onChanged(value == true ? null : true),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    value == true ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 22,
                    color: value == true ? AppTheme.green : AppTheme.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('women_led_label'),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('women_led_help'),
            style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

const List<String> _kMerchantProviders = ['Bankily', 'Masrvi', 'Sedad', 'Autre'];

/// Code marchand de la boutique — 6 septembre 2026.
///
/// Obligatoire, au même titre que la photo et le WhatsApp : c'est ce code
/// que la cliente saisit dans son application bancaire ("paiement
/// commerçant" → code du commerçant → montant) pour payer la boutique.
/// L'argent va directement à la vendeuse ; l'app ne touche pas aux fonds.
class _MerchantCodeFields extends StatelessWidget {
  final TextEditingController codeController;
  final String provider;
  final ValueChanged<String> onProviderChanged;

  const _MerchantCodeFields({
    required this.codeController,
    required this.provider,
    required this.onProviderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: provider,
          decoration: const InputDecoration(labelText: 'Mobile bank'),
          items: [for (final p in _kMerchantProviders) DropdownMenuItem(value: p, child: Text(p))],
          onChanged: (v) => onProviderChanged(v ?? _kMerchantProviders.first),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: 'Merchant code',
            helperText: 'Customers will pay with this code from their banking app.',
            helperMaxLines: 2,
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Required — without it, no one can pay you'
              : null,
        ),
      ],
    );
  }
}

/// Point de collecte pour l'espace Livreur (15 septembre 2026) — même
/// bouton "Use my location" que côté cliente au moment de payer (voir
/// `_LocationField` dans cart_screen.dart), en facultatif : une boutique
/// qui ne le renseigne pas reste vendable normalement, ses courses de
/// livraison apparaissent simplement sans distance calculée tant qu'elle
/// n'a pas donné sa position.
class _PickupLocationField extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final ValueChanged<(double, double)> onLocated;

  const _PickupLocationField({required this.initialLat, required this.initialLng, required this.onLocated});

  @override
  State<_PickupLocationField> createState() => _PickupLocationFieldState();
}

class _PickupLocationFieldState extends State<_PickupLocationField> {
  final _location = LocationService();
  double? _lat;
  double? _lng;
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lng = widget.initialLng;
  }

  Future<void> _useMyPosition() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final position = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _locating = false;
      });
      widget.onLocated((position.latitude, position.longitude));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _usePlace(PlaceResult place) {
    setState(() {
      _lat = place.lat;
      _lng = place.lng;
      _error = null;
    });
    widget.onLocated((place.lat, place.lng));
  }

  @override
  Widget build(BuildContext context) {
    final located = _lat != null && _lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Pickup location (for delivery drivers)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          "Optional, but needed for drivers to see the distance before accepting a delivery for your shop.",
          style: TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.3),
        ),
        const SizedBox(height: 8),
        PlaceSearchField(onSelected: _usePlace, hintText: 'Search your shop address'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _locating ? null : _useMyPosition,
          icon: _locating
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(located ? Icons.check_circle_outline : Icons.my_location, size: 18),
          label: Text(located ? 'Location saved (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})' : 'Or use my current location'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(fontSize: 12, color: AppTheme.red)),
        ],
      ],
    );
  }
}


/// Un carré de la palette, dans le formulaire de la vendeuse.
/// Sélectionné = anneau sombre + coche, pour que ce soit visible même sur
/// une teinte claire.
class _PaletteSwatch extends StatelessWidget {
  final Swatch swatch;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteSwatch({required this.swatch, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: swatch.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: hexToColor(swatch.hex),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppTheme.ink : AppTheme.line,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 18, color: Colors.white, shadows: [Shadow(blurRadius: 3)])
              : null,
        ),
      ),
    );
  }
}

/// Les trois chiffres du haut du tableau de bord vendeuse (6 septembre
/// 2026) : produits en ligne, commandes à traiter, abonnés. "Commandes à
/// traiter" compte les commandes encore en attente — c'est ce qui demande
/// une action, pas le total.
class _DashboardCounters extends StatelessWidget {
  final Future<List<Product>> productsFuture;
  final Future<List<OrderModel>> ordersFuture;
  final Future<int> followersFuture;

  const _DashboardCounters({
    required this.productsFuture,
    required this.ordersFuture,
    required this.followersFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<List<Product>>(
            future: productsFuture,
            builder: (context, snapshot) => _CounterTile(
              value: snapshot.hasData ? '${snapshot.data!.length}' : '—',
              label: 'produits',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FutureBuilder<List<OrderModel>>(
            future: ordersFuture,
            builder: (context, snapshot) {
              final pending = snapshot.hasData ? snapshot.data!.where((o) => o.status == 'pending').length : null;
              return _CounterTile(
                value: pending == null ? '—' : '$pending',
                label: 'to process',
                highlight: (pending ?? 0) > 0,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FutureBuilder<int>(
            future: followersFuture,
            builder: (context, snapshot) => _CounterTile(
              value: snapshot.hasData ? '${snapshot.data}' : '—',
              label: 'followers',
            ),
          ),
        ),
      ],
    );
  }
}

class _CounterTile extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;

  const _CounterTile({required this.value, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.ink : AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: highlight ? Colors.white : AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: highlight ? Colors.white70 : AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

/// Puce de filtre des commandes par statut, sur le tableau de bord de la
/// vendeuse.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppTheme.ink : AppTheme.panel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppTheme.ink,
          ),
        ),
      ),
    );
  }
}
