import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/admin_service.dart';
import 'admin_widgets.dart';

/// Réglages généraux — numéro de contact (utilisé dans "Aide et support"
/// côté client) et lien vers un site qui présente l'application au public.
/// Ajouté le 3 septembre 2026 (demande d'Emina : "l'administrateur a la
/// capacité de modifier le numéro ou changer un site qui présente
/// l'application, à l'accès à tous"). Une seule ligne en base, modifiable
/// par n'importe quel compte admin.
class SettingsAdminScreen extends StatefulWidget {
  const SettingsAdminScreen({super.key});

  @override
  State<SettingsAdminScreen> createState() => _SettingsAdminScreenState();
}

class _SettingsAdminScreenState extends State<SettingsAdminScreen> {
  final _admin = AdminService();
  final _formKey = GlobalKey<FormState>();
  late Future<AppSettings> _future;
  final _phone = TextEditingController();
  final _website = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<AppSettings> _load() async {
    final settings = await _admin.fetchAppSettings();
    _phone.text = settings.contactPhone ?? '';
    _website.text = settings.websiteUrl ?? '';
    _loaded = true;
    return settings;
  }

  Future<void> _save() async {
    // Validation ajoutée le 4 septembre 2026 : rien n'empêchait jusqu'ici
    // d'enregistrer un numéro ou un lien mal formé — le bouton "Voir le
    // site" ou "Contact WhatsApp" côté client échouait alors en silence,
    // sans qu'Emina ne comprenne pourquoi.
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _admin.updateAppSettings(
        contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        websiteUrl: _website.text.trim().isEmpty ? null : _website.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = isNarrowAdmin(context) ? 16.0 : 28.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminPageHeader(
          title: 'Settings',
          subtitle: "Contact number and website link — visible to every visitor of the app",
        ),
        Expanded(
          child: FutureBuilder<AppSettings>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done && !_loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
                child: AdminCard(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Contact number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminTheme.ink)),
                        const SizedBox(height: 4),
                        const Text(
                          "Used in \u201cHelp & support\u201d on the client side (WhatsApp button). International format, e.g. 22245123456",
                          style: TextStyle(fontSize: 12.5, color: AdminTheme.muted),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'WhatsApp number', hintText: '22245123456'),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return null;
                            final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                            if (digits.length < 8 || digits != value.replaceAll('+', '')) {
                              return 'Invalid number — digits only, e.g. 22245123456';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text('Showcase website link', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AdminTheme.ink)),
                        const SizedBox(height: 4),
                        const Text(
                          "Optional — if filled in, a \u201cVisit website\u201d button appears on the client side (Help page) and on the seller page.",
                          style: TextStyle(fontSize: 12.5, color: AdminTheme.muted),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _website,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(labelText: 'Website', hintText: 'https://...'),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return null;
                            final uri = Uri.tryParse(value);
                            if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
                              return 'Lien invalide — doit commencer par https://';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
