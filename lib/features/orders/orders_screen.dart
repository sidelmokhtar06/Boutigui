import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/money.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/order_service.dart';
import '../widgets.dart';

/// "Mes commandes", côté cliente.
///
/// Refait le 6 septembre 2026 : le bouton d'envoi de capture de paiement a
/// disparu (le paiement se fait maintenant par code marchand, et la
/// référence est saisie au moment de commander — voir cart_screen.dart), et
/// une commande encore en attente peut être ANNULÉE. Jusqu'ici, une
/// commande passée par erreur restait là pour toujours : aucune règle de la
/// base n'autorisait la cliente à y toucher.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _orderService = OrderService();
  late Future<List<OrderModel>> _future;
  String? _busyOrderId;

  @override
  void initState() {
    super.initState();
    _future = _orderService.fetchMyOrders();
  }

  Future<void> _refresh() async {
    setState(() => _future = _orderService.fetchMyOrders());
  }

  Future<void> _cancel(OrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text(
          "The shop will no longer see this order. If you already paid, "
          "contact them to get a refund.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Back')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Annuler la commande'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyOrderId = order.id);
    try {
      await _orderService.cancelOrder(order.id);
      if (!mounted) return;
      setState(() => _busyOrderId = null);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyOrderId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String _statusLabel(String status, String Function(String) t) => t('order_status_$status');

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Scaffold(
      appBar: AppBar(title: Text(t('my_orders'))),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<OrderModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                const SizedBox(height: 100),
                EmptyState(
                  icon: Icons.error_outline,
                  title: t('error_generic'),
                  subtitle: snapshot.error.toString(),
                ),
              ]);
            }
            final orders = snapshot.data ?? [];
            if (orders.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 100),
                EmptyState(icon: Icons.receipt_long_outlined, title: t('no_results')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final order = orders[i];
                final busy = _busyOrderId == order.id;
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(order.shopName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            OrderStatusChip(status: order.status, label: _statusLabel(order.status, t)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(Money.format(order.total),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.ink)),
                        if (order.paymentReference != null && order.paymentReference!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          // ÉTAT RÉEL du paiement — corrigé le 20 septembre
                          // 2026. Cet écran affichait une coche « vérifié »
                          // à côté de CHAQUE référence, quelle que soit la
                          // réalité : une référence tout juste soumise, ou
                          // même introuvable en banque, se montrait à la
                          // cliente comme un paiement validé.
                          //
                          // L'état vient maintenant de `payment_status`, et
                          // il est porté par l'icône ET par le texte —
                          // jamais par la couleur seule.
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.panel,
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      switch (order.paymentStatus) {
                                        'verified' => Icons.check_circle_outline,
                                        'rejected' => Icons.cancel_outlined,
                                        _ => Icons.schedule_outlined,
                                      },
                                      size: 15,
                                      color: switch (order.paymentStatus) {
                                        'verified' => AppTheme.whatsapp,
                                        'rejected' => AppTheme.red,
                                        _ => AppTheme.stockWarn,
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        order.paymentLabel,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.ink),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Référence : ${order.paymentReference}'
                                  '${order.paymentProvider != null ? ' · ${order.paymentProvider}' : ''}',
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.ink2),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (order.status == 'pending') ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: busy ? null : () => _cancel(order),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.red,
                              side: const BorderSide(color: AppTheme.line),
                            ),
                            child: busy
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Cancel order'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
