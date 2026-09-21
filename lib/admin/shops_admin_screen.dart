import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/admin_service.dart';
import 'admin_widgets.dart';

const double _rowBreakpoint = 560;

class ShopsAdminScreen extends StatefulWidget {
  const ShopsAdminScreen({super.key});

  @override
  State<ShopsAdminScreen> createState() => _ShopsAdminScreenState();
}

class _ShopsAdminScreenState extends State<ShopsAdminScreen> {
  final _admin = AdminService();
  late Future<List<AdminShopRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _admin.fetchAllShops();
  }

  void _refresh() => setState(() => _future = _admin.fetchAllShops());

  Future<void> _toggleVisible(AdminShopRow row) async {
    try {
      await _admin.setShopVisible(row.shop.id, !row.shop.isVisible);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _delete(AdminShopRow row) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${row.shop.name}"?',
      message: 'Its products and orders will be deleted too. This action cannot be undone.',
    );
    if (!ok) return;
    try {
      await _admin.deleteShop(row.shop.id);
      _refresh();
    } catch (e) {
      if (mounted) showAdminError(context, e);
    }
  }

  Future<void> _openAddShop() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddShopDialog(admin: _admin),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Shops',
          subtitle: 'Shops pending approval are at the top of the list',
          action: FilledButton.icon(
            onPressed: _openAddShop,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a shop'),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AdminShopRow>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              // Corrigé le 4 septembre 2026 (nuit) : avant, une erreur ici
              // (réseau, requête invalide...) tombait dans `snapshot.data ??
              // []` et s'affichait comme "Aucune boutique." — indiscernable
              // d'un vrai état vide. C'est exactement ce qui a caché à
              // Emina une boutique bien réelle et déjà en attente.
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AdminTheme.red)));
              }
              final rows = snapshot.data ?? [];
              if (rows.isEmpty) {
                return const Center(child: Text('No shops.', style: TextStyle(color: AdminTheme.muted)));
              }
              final pad = isNarrowAdmin(context) ? 16.0 : 28.0;
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ShopRow(
                  row: rows[i],
                  onToggleVisible: () => _toggleVisible(rows[i]),
                  onDelete: () => _delete(rows[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Une ligne "boutique" — côte à côte sur écran large, empilée en petite
/// carte sur écran étroit (2 septembre 2026, site admin utilisable sur
/// téléphone).
class _ShopRow extends StatelessWidget {
  final AdminShopRow row;
  final VoidCallback onToggleVisible;
  final VoidCallback onDelete;

  const _ShopRow({required this.row, required this.onToggleVisible, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(row.shop.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AdminTheme.ink)),
        const SizedBox(height: 2),
        Text(row.ownerName ?? row.ownerEmail ?? row.shop.ownerId, style: const TextStyle(fontSize: 12, color: AdminTheme.muted)),
      ],
    );
    final statusPill = AdminStatusPill(
      label: row.shop.isVisible ? 'Visible' : 'Hidden',
      color: row.shop.isVisible ? const Color(0xFF2E9C5B) : AdminTheme.muted,
    );
    final actions = [
      Switch(value: row.shop.isVisible, activeColor: AdminTheme.red, onChanged: (_) => onToggleVisible()),
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
                nameBlock,
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(row.shop.city ?? '—', style: const TextStyle(fontSize: 13, color: AdminTheme.ink2)),
                    Text(row.shop.whatsappPhone ?? '—', style: const TextStyle(fontSize: 13, color: AdminTheme.ink2)),
                    statusPill,
                  ],
                ),
                const Divider(height: 20, color: AdminTheme.hair),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ),
          );
        }
        return AdminCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(flex: 2, child: nameBlock),
              Expanded(child: Text(row.shop.city ?? '—', style: const TextStyle(fontSize: 13, color: AdminTheme.ink2))),
              Expanded(child: Text(row.shop.whatsappPhone ?? '—', style: const TextStyle(fontSize: 13, color: AdminTheme.ink2))),
              statusPill,
              const SizedBox(width: 8),
              ...actions,
            ],
          ),
        );
      },
    );
  }
}

class _AddShopDialog extends StatefulWidget {
  final AdminService admin;

  const _AddShopDialog({required this.admin});

  @override
  State<_AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends State<_AddShopDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _whatsapp = TextEditingController();
  final _search = TextEditingController();
  Profile? _selectedOwner;
  List<Profile> _results = [];
  bool _saving = false;
  bool _searching = false;

  Future<void> _searchProfiles(String value) async {
    setState(() => _searching = true);
    final results = await widget.admin.fetchProfiles(search: value);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedOwner == null) {
      if (_selectedOwner == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose an owner for the shop.')));
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.admin.createShop(
        ownerId: _selectedOwner!.id,
        name: _name.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        whatsappPhone: _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
      );
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
      title: const Text('Add a shop'),
      content: SizedBox(
        width: adminDialogWidth(context, 420),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Shop name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
                const SizedBox(height: 10),
                TextFormField(controller: _whatsapp, decoration: const InputDecoration(labelText: 'WhatsApp number')),
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft, child: Text('Owner', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                const SizedBox(height: 6),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(hintText: 'Search by name or email', prefixIcon: Icon(Icons.search)),
                  onChanged: _searchProfiles,
                ),
                const SizedBox(height: 8),
                if (_selectedOwner != null)
                  Chip(
                    label: Text(_selectedOwner!.fullName ?? _selectedOwner!.email ?? _selectedOwner!.id),
                    onDeleted: () => setState(() => _selectedOwner = null),
                  )
                else if (_searching)
                  const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
                else
                  SizedBox(
                    height: 160,
                    child: _results.isEmpty
                        ? const Center(child: Text('Type a name or email to search for an account.', style: TextStyle(color: AdminTheme.muted, fontSize: 12)))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final p = _results[i];
                              return ListTile(
                                dense: true,
                                title: Text(p.fullName ?? '(sans nom)'),
                                subtitle: Text(p.email ?? ''),
                                trailing: Text(p.role, style: const TextStyle(fontSize: 11, color: AdminTheme.muted)),
                                onTap: () => setState(() => _selectedOwner = p),
                              );
                            },
                          ),
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
              : const Text('Create'),
        ),
      ],
    );
  }
}
