import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/delivery_service.dart';
import '../widgets.dart';

/// Tableau de courses du livreur — voir `supabase/livreur_patch.sql` pour
/// tout ce qui garantit, côté base, que le nom/téléphone/adresse de la
/// cliente ne sont jamais accessibles avant qu'une course soit acceptée.
///
/// Deux onglets : "Available" (les courses en attente, n'importe quel
/// livreur peut les voir et les accepter — en temps réel, voir
/// `DeliveryService.streamOpenBoard`) et "My deliveries" (celles que CE
/// livreur a acceptées, en cours ou déjà livrées).
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> with SingleTickerProviderStateMixin {
  final _delivery = DeliveryService();
  late final TabController _tabController;
  StreamSubscription<List<DeliveryRequest>>? _sub;

  List<DeliveryRequest> _board = [];
  Map<String, Shop> _shops = {};
  bool _available = false;
  bool _loadingAvailability = true;
  List<DeliveryRequest> _mine = [];
  bool _loadingMine = true;
  DriverProfile? _myProfile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAvailability();
    _loadMine();
    _sub = _delivery.streamOpenBoard().listen((rows) async {
      Map<String, Shop> shops = {};
      try {
        shops = await _delivery.fetchShopsFor(rows);
      } catch (_) {
        // Pas grave : les cartes retombent sur "Shop" tant que le nom n'a
        // pas pu être récupéré — la course reste utilisable.
      }
      if (!mounted) return;
      setState(() {
        _board = rows;
        _shops = {..._shops, ...shops};
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailability() async {
    try {
      final profile = await _delivery.fetchMyDriverProfile();
      if (!mounted) return;
      setState(() {
        _myProfile = profile;
        _available = profile?.isAvailable ?? false;
        _loadingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAvailability = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _available = value);
    try {
      await _delivery.setAvailability(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _available = !value);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _loadMine() async {
    if (!mounted) return;
    setState(() => _loadingMine = true);
    try {
      final rows = await _delivery.fetchMyDeliveries();
      Map<String, Shop> shops = {};
      try {
        shops = await _delivery.fetchShopsFor(rows);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _mine = rows;
        _shops = {..._shops, ...shops};
        _loadingMine = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMine = false);
    }
  }

  Future<void> _accept(DeliveryRequest req) async {
    try {
      await _delivery.acceptRequest(req.id);
      if (!mounted) return;
      _tabController.animateTo(1);
      await _loadMine();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery accepted — check "My deliveries" for the customer contact.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _markDelivered(DeliveryRequest req) async {
    try {
      await _delivery.markDelivered(req.id);
      await _loadMine();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showContact(DeliveryRequest req) async {
    DeliveryContact? contact;
    try {
      contact = await _delivery.fetchContact(req.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted || contact == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ContactSheet(contact: contact!),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le compte doit être APPROUVÉ par l'administrateur avant de voir quoi
    // que ce soit du tableau de courses — demande explicite du 15
    // septembre 2026 : "il ne peut recevoir les livraisons que si
    // l'administrateur accepte ce livreur". Tant que le profil n'est pas
    // encore chargé, on ne montre ni un refus ni le tableau — juste un
    // indicateur de chargement, pour ne pas afficher un message d'attente
    // à tort pendant une fraction de seconde.
    if (_loadingAvailability) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_myProfile == null || !_myProfile!.isApproved) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery space')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _myProfile?.isRejected ?? false ? Icons.block_outlined : Icons.hourglass_top_outlined,
                  size: 40,
                  color: AppTheme.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  _myProfile?.isRejected ?? false ? 'Application not approved' : 'Application under review',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.ink),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _myProfile?.isRejected ?? false
                      ? "Your driver application wasn't approved. Contact us if you think this is a mistake."
                      : "We're reviewing your driver application. You'll be able to accept deliveries once it's approved.",
                  style: const TextStyle(fontSize: 13.5, color: AppTheme.ink2, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _buildBoardScaffold();
  }

  Widget _buildBoardScaffold() {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Delivery space'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.ink,
          unselectedLabelColor: AppTheme.muted,
          indicatorColor: AppTheme.ink,
          tabs: const [Tab(text: 'Available'), Tab(text: 'My deliveries')],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: AppTheme.panel,
            child: Row(
              children: [
                Icon(_available ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: _available ? AppTheme.ink : AppTheme.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _available ? "You're online — visible for new deliveries" : "You're offline — no new deliveries will reach you",
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.ink2),
                  ),
                ),
                _loadingAvailability
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch(value: _available, onChanged: _toggleAvailability),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBoard(),
                _buildMine(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    if (_board.isEmpty) {
      return const EmptyState(
        icon: Icons.moped_outlined,
        title: 'No deliveries waiting',
        subtitle: 'New requests will appear here the moment a customer orders delivery.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      itemCount: _board.length,
      itemBuilder: (context, i) => _DeliveryCard(
        request: _board[i],
        shop: _shops[_board[i].shopId],
        trailing: FilledButton(
          onPressed: () => _accept(_board[i]),
          child: const Text('Accept'),
        ),
      ),
    );
  }

  Widget _buildMine() {
    if (_loadingMine) return const Center(child: CircularProgressIndicator());
    if (_mine.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'No deliveries yet',
        subtitle: 'Deliveries you accept will show up here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        itemCount: _mine.length,
        itemBuilder: (context, i) {
          final req = _mine[i];
          return _DeliveryCard(
            request: req,
            shop: _shops[req.shopId],
            trailing: req.isAccepted
                ? Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(onPressed: () => _showContact(req), child: const Text('Contact')),
                      FilledButton(onPressed: () => _markDelivered(req), child: const Text('Delivered')),
                    ],
                  )
                : Text(
                    req.isDelivered ? 'Delivered' : req.status,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.muted),
                  ),
          );
        },
      ),
    );
  }
}

/// Une course — point de départ, point d'arrivée (arrondi tant qu'elle
/// n'est pas acceptée, voir la note plus bas) et distance. JAMAIS de nom,
/// téléphone ou adresse ici : ces informations n'existent tout simplement
/// pas sur [DeliveryRequest] (voir la note de la classe dans models.dart).
class _DeliveryCard extends StatelessWidget {
  final DeliveryRequest request;
  final Shop? shop;
  final Widget trailing;

  const _DeliveryCard({required this.request, required this.shop, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final pickupLabel = shop?.name ?? 'Shop';
    final pickupCity = shop?.city;
    // Coordonnées d'arrivée arrondies à 2 décimales (~1 km de marge) tant
    // que la course n'est qu'affichée sur le tableau — assez précis pour
    // juger si la course vaut le détour, pas assez pour retrouver le point
    // exact avant d'avoir accepté.
    final dropLat = request.dropoffLat;
    final dropLng = request.dropoffLng;
    final roundedDrop = (dropLat != null && dropLng != null)
        ? '${dropLat.toStringAsFixed(request.isPending ? 2 : 5)}, ${dropLng.toStringAsFixed(request.isPending ? 2 : 5)}'
        : 'Not shared';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 16, color: AppTheme.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pickupCity != null && pickupCity.isNotEmpty ? '$pickupLabel · $pickupCity' : pickupLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (request.orderTotal != null)
                Text(Money.format(request.orderTotal!), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              height: 14,
              child: Row(children: [SizedBox(width: 7), Icon(Icons.more_vert, size: 14, color: AppTheme.muted)]),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delivery point ($roundedDrop)',
                  style: const TextStyle(fontSize: 13, color: AppTheme.ink2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  request.distanceKm != null ? '${request.distanceKm!.toStringAsFixed(1)} km' : 'Distance unknown',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.ink),
                ),
              ),
              const Spacer(),
              trailing,
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactSheet extends StatelessWidget {
  final DeliveryContact contact;

  const _ContactSheet({required this.contact});

  Future<void> _call() async {
    final uri = Uri.parse('tel:${contact.phone}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp() async {
    final clean = contact.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Customer contact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 4),
            const Text(
              'Visible because you accepted this delivery.',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 18),
            Text(contact.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.ink)),
            const SizedBox(height: 4),
            Text(contact.phone, style: const TextStyle(fontSize: 14, color: AppTheme.ink2)),
            if ((contact.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [contact.address, contact.city].where((s) => (s ?? '').isNotEmpty).join(', '),
                style: const TextStyle(fontSize: 13, color: AppTheme.ink2),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(onPressed: _call, icon: const Icon(Icons.call_outlined, size: 18), label: const Text('Call'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(onPressed: _whatsapp, icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('WhatsApp'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
