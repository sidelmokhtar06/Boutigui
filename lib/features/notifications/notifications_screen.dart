import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../core/theme.dart';
import '../../services/notification_service.dart';
import '../widgets.dart';

/// Écran "Notifications" — 6 septembre 2026.
///
/// Ouvert depuis la cloche de l'accueil. Tout est marqué comme lu à
/// l'ouverture : la pastille rouge sert à signaler qu'il y a du nouveau,
/// pas à tenir une liste de tâches.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetch();
    // Après le premier rendu : sinon on modifierait un `ChangeNotifier`
    // pendant que Flutter construit déjà l'arbre, ce qu'il refuse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsController>().markAllRead();
    });
  }

  Future<void> _refresh() async {
    setState(() => _future = _service.fetch());
    await _future;
  }

  String _ago(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return 'Il y a ${diff.inDays} jours';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AppNotification>>(
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
                  title: 'Une erreur est survenue.',
                  subtitle: snapshot.error.toString(),
                ),
              ]);
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 100),
                EmptyState(
                  icon: Icons.notifications_none,
                  title: 'Aucune notification',
                  subtitle: 'You will be notified here about your orders.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = items[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.kind == 'order_new' ? Icons.shopping_bag_outlined : Icons.local_shipping_outlined,
                        size: 20,
                        color: AppTheme.ink2,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                            if (item.body != null && item.body!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(item.body!, style: const TextStyle(fontSize: 13, color: AppTheme.ink2, height: 1.35)),
                            ],
                            const SizedBox(height: 6),
                            Text(_ago(item.createdAt), style: const TextStyle(fontSize: 11.5, color: AppTheme.muted)),
                          ],
                        ),
                      ),
                    ],
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
