import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/settings_controller.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/catalog_service.dart';

/// Aide et support — depuis le 3 septembre 2026, le numéro WhatsApp et le
/// lien du site de présentation ne sont plus codés en dur : ils viennent de
/// `app_settings`, modifiable par l'admin (écran "Réglages"). Tant que
/// l'admin n'a rien renseigné, les boutons correspondants restent cachés
/// plutôt que d'ouvrir un lien invalide.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _catalog = CatalogService();
  late Future<AppSettings> _future;

  @override
  void initState() {
    super.initState();
    _future = _catalog.fetchAppSettings();
  }

  Future<void> _openWhatsapp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWebsite(String url) async {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsController>().t;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: AppTheme.bg,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        title: Text(t('help_support'), style: const TextStyle(color: AppTheme.ink)),
      ),
      body: SafeArea(
        child: FutureBuilder<AppSettings>(
          future: _future,
          builder: (context, snapshot) {
            final settings = snapshot.data ?? AppSettings();
            final hasPhone = settings.contactPhone != null && settings.contactPhone!.isNotEmpty;
            final hasWebsite = settings.websiteUrl != null && settings.websiteUrl!.isNotEmpty;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Carte d'en-tête, même langage que l'accueil et l'écran
                // Compte depuis le 20 septembre 2026.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.greenTint, AppTheme.sage],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: AppTheme.card,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.support_agent, size: 28, color: AppTheme.green),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        t('help_support'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink),
                      ),
                      const SizedBox(height: 8),
                      // Cette phrase était à moitié en français, à moitié
                      // en anglais (« ... ou une boutique ? Contact us
                      // directly, we reply fast. ») — corrigé le
                      // 20 septembre 2026.
                      const Text(
                        'Une question sur une commande, un paiement ou une '
                        'boutique ? Écrivez-nous, nous répondons vite.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (hasPhone)
                  _ContactCard(
                    icon: Icons.chat_bubble_outline,
                    tint: AppTheme.greenTint,
                    title: t('contact_whatsapp'),
                    subtitle: settings.contactPhone!,
                    onTap: () => _openWhatsapp(settings.contactPhone!),
                  ),
                if (hasWebsite)
                  _ContactCard(
                    icon: Icons.public,
                    tint: AppTheme.searchFill,
                    title: 'Notre site',
                    subtitle: settings.websiteUrl!,
                    onTap: () => _openWebsite(settings.websiteUrl!),
                  ),
                if (!hasPhone && !hasWebsite)
                  // L'admin n'a encore renseigné aucun moyen de contact.
                  // Mieux vaut le dire que laisser une page vide.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.panel,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    ),
                    child: const Text(
                      "Aucun moyen de contact n'est encore renseigné. "
                      'Revenez bientôt.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppTheme.ink2),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Une façon de nous joindre, présentée comme les lignes de l'écran
/// Compte : pastille colorée, intitulé, détail, chevron.
class _ContactCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(icon, size: 19, color: AppTheme.ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.ink2)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}
