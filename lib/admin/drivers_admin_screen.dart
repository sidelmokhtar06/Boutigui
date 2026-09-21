import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/delivery_service.dart';
import 'admin_widgets.dart';

/// Validation des candidatures livreur — ajouté le 15 septembre 2026,
/// demande explicite : "il ne peut recevoir les livraisons que si
/// l'administrateur accepte ce livreur". Ne montre que les candidatures
/// "pending" : une fois approuvée ou rejetée, une candidature quitte cet
/// écran (voir `DeliveryService.fetchPendingDrivers`, filtré côté base).
class DriversAdminScreen extends StatefulWidget {
  const DriversAdminScreen({super.key});

  @override
  State<DriversAdminScreen> createState() => _DriversAdminScreenState();
}

class _DriversAdminScreenState extends State<DriversAdminScreen> {
  final _delivery = DeliveryService();
  late Future<List<Map<String, dynamic>>> _future;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _future = _delivery.fetchPendingDrivers();
  }

  void _refresh() => setState(() => _future = _delivery.fetchPendingDrivers());

  Future<void> _decide(String driverId, String status) async {
    setState(() => _busy.add(driverId));
    try {
      await _delivery.setDriverStatus(driverId, status);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(driverId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminPageHeader(
              title: 'Driver applications',
              subtitle: "Approve a driver before they can see or accept any delivery.",
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('${snapshot.error}', style: const TextStyle(color: AdminTheme.red)));
                  }
                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('No pending applications.', style: TextStyle(color: AdminTheme.muted)),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final driverId = row['id'] as String;
                      final profile = (row['profiles'] as Map?) ?? {};
                      final name = (profile['full_name'] as String?)?.trim();
                      final email = profile['email'] as String?;
                      final phone = profile['phone'] as String?;
                      final vehicle = row['vehicle_type'] as String?;
                      final busy = _busy.contains(driverId);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AdminCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (name?.isNotEmpty ?? false) ? name! : (email ?? driverId),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminTheme.ink),
                                  ),
                                  if (email != null) Text(email, style: const TextStyle(fontSize: 12.5, color: AdminTheme.muted)),
                                  if (phone != null) Text(phone, style: const TextStyle(fontSize: 12.5, color: AdminTheme.muted)),
                                  if (vehicle != null) ...[
                                    const SizedBox(height: 4),
                                    Text('Vehicle: $vehicle', style: const TextStyle(fontSize: 12.5, color: AdminTheme.ink2)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (busy)
                              const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            else
                              Column(
                                children: [
                                  FilledButton(
                                    onPressed: () => _decide(driverId, 'approved'),
                                    child: const Text('Approve'),
                                  ),
                                  const SizedBox(height: 6),
                                  OutlinedButton(
                                    onPressed: () => _decide(driverId, 'rejected'),
                                    child: const Text('Reject'),
                                  ),
                                ],
                              ),
                          ],
                          ),
                        ),
                      );
                    },
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
