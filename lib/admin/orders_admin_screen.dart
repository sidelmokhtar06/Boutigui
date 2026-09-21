import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import 'admin_widgets.dart';

const List<String> kOrderStatuses = ['pending', 'confirmed', 'preparing', 'delivering', 'delivered', 'cancelled'];

const Map<String, String> kOrderStatusLabels = {
  'pending': 'Pending',
  'confirmed': 'Confirmed',
  'preparing': 'Preparing',
  'delivering': 'Delivering',
  'delivered': 'Delivered',
  'cancelled': 'Cancelled',
};

Color orderStatusColor(String status) {
  switch (status) {
    case 'delivered':
      return const Color(0xFF2E9C5B);
    case 'cancelled':
      return AdminTheme.red;
    case 'confirmed':
    case 'preparing':
    case 'delivering':
      return const Color(0xFFC4682F);
    default:
      return AdminTheme.muted;
  }
}

/// Écran "Commandes" — ajouté le 4 septembre 2026. Jusqu'ici, une commande
/// passée par un client n'était visible NULLE PART côté admin : ni la
/// commande elle-même, ni la capture de paiement envoyée (voir le correctif
/// sur le bucket `payment-proofs` dans `admin_patch.sql`, même date).
class OrdersAdminScreen extends StatefulWidget {
  const OrdersAdminScreen({super.key});

  @override
  State<OrdersAdminScreen> createState() => _OrdersAdminScreenState();
}

class _OrdersAdminScreenState extends State<OrdersAdminScreen> {
  final _admin = AdminService();
  String? _statusFilter;
  late Future<List<OrderModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _admin.fetchOrders();
  }

  void _refresh() => setState(() => _future = _admin.fetchOrders(status: _statusFilter));

  void _setFilter(String? status) {
    setState(() {
      _statusFilter = status;
      _future = _admin.fetchOrders(status: status);
    });
  }

  Future<void> _openDetail(OrderModel order) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _OrderDetailDialog(admin: _admin, order: order),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminPageHeader(title: 'Orders', subtitle: 'Across all shops'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isNarrowAdmin(context) ? 16 : 28),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(label: 'Toutes', selected: _statusFilter == null, onTap: () => _setFilter(null)),
                for (final s in kOrderStatuses) ...[
                  const SizedBox(width: 8),
                  _FilterChip(label: kOrderStatusLabels[s]!, selected: _statusFilter == s, onTap: () => _setFilter(s)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<OrderModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return const Center(child: Text('No orders.', style: TextStyle(color: AdminTheme.muted)));
              }
              final pad = isNarrowAdmin(context) ? 16.0 : 28.0;
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _OrderRow(order: orders[i], onTap: () => _openDetail(orders[i])),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AdminTheme.red.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: selected ? AdminTheme.red : AdminTheme.ink2, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
      backgroundColor: AdminTheme.card,
      side: const BorderSide(color: AdminTheme.hair),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const _OrderRow({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(order.shopName ?? '—', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AdminTheme.ink)),
        const SizedBox(height: 2),
        Text(order.clientFullName, style: const TextStyle(fontSize: 12, color: AdminTheme.muted)),
      ],
    );
    final pill = AdminStatusPill(label: kOrderStatusLabels[order.status] ?? order.status, color: orderStatusColor(order.status));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AdminCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameBlock,
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(Money.format(order.total), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AdminTheme.ink)),
                      pill,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 2, child: nameBlock),
                Expanded(child: Text(Money.format(order.total), style: const TextStyle(fontSize: 13.5, color: AdminTheme.ink2))),
                Expanded(child: Text('${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}', style: const TextStyle(fontSize: 13, color: AdminTheme.muted))),
                pill,
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AdminTheme.muted, size: 18),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Détail d'une commande — coordonnées client, articles, capture de
/// paiement (URL signée temporaire, le bucket est privé) et changement de
/// statut. Utilisé aussi bien par l'admin que, dans sa propre version
/// (thème clair, "Ma boutique"), par la vendeuse — voir
/// `lib/features/vendor/my_shop_screen.dart`.
class _OrderDetailDialog extends StatefulWidget {
  final AdminService admin;
  final OrderModel order;

  const _OrderDetailDialog({required this.admin, required this.order});

  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  late Future<List<OrderItemModel>> _itemsFuture;
  late String _status;
  bool _saving = false;
  String? _proofSignedUrl;
  bool _loadingProof = false;

  @override
  void initState() {
    super.initState();
    _itemsFuture = widget.admin.fetchOrderItems(widget.order.id);
    _status = widget.order.status;
  }

  Future<void> _loadProof() async {
    final path = widget.order.paymentProofUrl;
    if (path == null || path.isEmpty) return;
    setState(() => _loadingProof = true);
    try {
      final url = await StorageService().signedPaymentProofUrl(path);
      if (mounted) setState(() => _proofSignedUrl = url);
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _loadingProof = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.admin.updateOrderStatus(widget.order.id, _status);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return AlertDialog(
      title: Text(order.shopName ?? 'Commande'),
      content: SizedBox(
        width: adminDialogWidth(context, 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Customer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Text(order.clientFullName, style: const TextStyle(fontSize: 13)),
              Text(order.clientPhone, style: const TextStyle(fontSize: 13, color: AdminTheme.ink2)),
              if ((order.clientCity ?? '').isNotEmpty || (order.clientAddress ?? '').isNotEmpty)
                Text(
                  [order.clientAddress, order.clientCity].where((s) => s != null && s.isNotEmpty).join(', '),
                  style: const TextStyle(fontSize: 13, color: AdminTheme.ink2),
                ),
              const SizedBox(height: 16),
              const Text('Items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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
                              Expanded(child: Text('${item.productName} × ${item.quantity}', style: const TextStyle(fontSize: 13))),
                              Text(Money.format(item.subtotal), style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(height: 20, color: AdminTheme.hair),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(Money.format(order.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 16),
              // Paiement par code marchand (6 septembre 2026) — la
              // référence renvoyée par la banque de la cliente remplace la
              // capture d'écran. Unique en base : la même ne peut pas
              // servir pour deux commandes.
              const Text('Payment reference', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              if (order.paymentReference == null || order.paymentReference!.isEmpty)
                const Text('No code (order placed before code-based payment).', style: TextStyle(fontSize: 12.5, color: AdminTheme.muted))
              else
                SelectableText(
                  order.paymentReference!,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                ),
              const SizedBox(height: 16),
              const Text('Delivery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              if (order.deliveryMapUrl == null)
                const Text('No location shared.', style: TextStyle(fontSize: 12.5, color: AdminTheme.muted))
              else
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(order.deliveryMapUrl!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
              const SizedBox(height: 16),
              // Conservé pour les commandes passées AVANT le 6 septembre
              // 2026, qui ont encore une capture.
              if (order.paymentProofUrl != null && order.paymentProofUrl!.isNotEmpty) ...[
                const Text('Payment screenshot (old order)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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
                    errorBuilder: (_, __, ___) => const Text('Image not found.', style: TextStyle(color: AdminTheme.muted, fontSize: 12)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _status,
                items: [for (final s in kOrderStatuses) DropdownMenuItem(value: s, child: Text(kOrderStatusLabels[s]!))],
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
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Save status'),
        ),
      ],
    );
  }
}
