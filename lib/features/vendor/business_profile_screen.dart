import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/analytics_service.dart';
import '../../services/business_profile_pdf.dart';
import '../../services/vendor_service.dart';

/// Dossier d'activité — « Générer mon dossier » (21 septembre 2026).
///
/// C'est la pièce qui manquait entre l'indice de préparation financière et
/// la promesse de mise en relation avec un partenaire financier. Un score
/// affiché dans une application ne se transmet pas ; une banque ne reçoit
/// pas un écran. Cet écran produit un DOCUMENT : identité de l'entreprise,
/// historique sur la place de marché, part des paiements numériques,
/// détail de l'indice — le genre de page qu'un chargé de clientèle peut
/// réellement lire.
///
/// **Le bouton « Copier » plutôt qu'un export PDF.** Trois raisons :
///
///  1. Aucune dépendance de plus, à sept jours de l'échéance — et le web
///     bloque de toute façon les téléchargements lancés par la page.
///  2. En Mauritanie, un dossier se transmet sur WhatsApp. Un texte se
///     colle ; un PDF se cherche dans les fichiers.
///  3. Le texte copié est exactement ce qui est affiché : rien ne se perd
///     ni ne s'ajoute entre l'écran et ce que reçoit le destinataire.
///
/// Toutes les valeurs sont CALCULÉES à partir des commandes réelles, sur
/// toute l'histoire de la boutique. Rien n'est saisi à la main, donc rien
/// ne peut être embelli.
class BusinessProfileScreen extends StatefulWidget {
  final String shopId;
  const BusinessProfileScreen({super.key, required this.shopId});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _analytics = AnalyticsService();
  final _vendor = VendorService();
  late Future<(Shop?, VendorAnalytics)> _future;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Shop?, VendorAnalytics)> _load() async {
    // Fenêtre volontairement longue : un dossier décrit une HISTOIRE, pas
    // les trente derniers jours. 365 jours couvre toute la vie des
    // boutiques actuelles.
    final analytics = await _analytics.fetchForShop(widget.shopId, rangeDays: 365);
    final shop = await _vendor.fetchMyShop();
    return (shop, analytics);
  }

  /// Produit le PDF et ouvre la feuille de partage du système —
  /// WhatsApp, e-mail, enregistrement dans les fichiers. Sur le web, le
  /// navigateur propose le téléchargement.
  ///
  /// C'est le geste attendu : une entreprise envoie un DOCUMENT à sa
  /// banque. La première version copiait un texte dans le presse-papier,
  /// ce qui obligeait à le recoller quelque part et ne ressemblait à rien
  /// de ce qu'attend un chargé de clientèle.
  Future<void> _share(Shop? shop, VendorAnalytics a) async {
    setState(() => _sharing = true);
    try {
      final bytes = await BusinessProfilePdf.build(shop: shop, a: a);
      final name = (shop?.name ?? 'boutique')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'dossier-activite-$name.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Le dossier n\'a pas pu être généré. $e')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static const _disclaimer =
      'Ce dossier résume une activité commerciale enregistrée sur Boutigui. '
      'Il ne constitue ni une décision de crédit, ni une garantie de '
      'financement, ni une évaluation par un établissement financier. Les '
      'chiffres sont calculés à partir des commandes réelles de la '
      'boutique.';

  static String _monthYear(DateTime d) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  static String _repeatRate(VendorAnalytics a) =>
      a.customerCount == 0 ? '—' : (a.orderCount / a.customerCount).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: AppTheme.bg,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        title: const Text('Mon dossier', style: TextStyle(color: AppTheme.ink)),
      ),
      body: FutureBuilder<(Shop?, VendorAnalytics)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Error(onRetry: () => setState(() => _future = _load()));
          }
          final (shop, a) = snap.data!;

          if (a.isEmpty) {
            return const _NothingYet();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Header(shop: shop, analytics: a),
              const SizedBox(height: 16),
              _Section(
                title: 'Historique sur la place de marché',
                rows: [
                  ('Commandes honorées', '${a.orderCount}'),
                  ('Volume de ventes', Money.format(a.revenue)),
                  ('Panier moyen', Money.format(a.averageOrderValue)),
                  ('Clientes distinctes', '${a.customerCount}'),
                  ('Commandes par cliente', _repeatRate(a)),
                ],
              ),
              const SizedBox(height: 12),
              _PaymentsSection(analytics: a),
              const SizedBox(height: 12),
              _ReadinessSection(analytics: a),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.panel,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: const Text(
                  _disclaimer,
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: AppTheme.ink2),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.greenDeep,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                  ),
                  onPressed: _sharing ? null : () => _share(shop, a),
                  icon: _sharing
                      ? const SizedBox(
                          height: 17,
                          width: 17,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(_sharing ? 'Génération…' : 'Télécharger mon dossier (PDF)',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Vous décidez à qui vous l\'envoyez. Boutigui ne transmet votre '
                'dossier à personne.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, height: 1.35, color: AppTheme.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Shop? shop;
  final VendorAnalytics analytics;
  const _Header({required this.shop, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final s = shop;
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DOSSIER D\'ACTIVITÉ',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppTheme.green)),
          const SizedBox(height: 8),
          Text(s?.name ?? '',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (s?.city != null && s!.city!.isNotEmpty)
                _Meta(icon: Icons.place_outlined, text: s.city!),
              if (s?.createdAt != null)
                _Meta(
                    icon: Icons.calendar_today_outlined,
                    text: 'Active depuis ${_BusinessProfileScreenState._monthYear(s!.createdAt!)}'),
              if (s?.merchantProvider != null && s!.merchantProvider!.isNotEmpty)
                _Meta(icon: Icons.account_balance_outlined, text: s.merchantProvider!),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.ink2),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.ink2)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.ink)),
          const SizedBox(height: 14),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(row.$1,
                        style: const TextStyle(fontSize: 13, color: AppTheme.ink2)),
                  ),
                  const SizedBox(width: 12),
                  Text(row.$2,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  final VendorAnalytics analytics;
  const _PaymentsSection({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final providers = a.revenueByProvider.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PAIEMENTS NUMÉRIQUES',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.ink)),
          const SizedBox(height: 4),
          // Formulation exacte : la vendeuse a RETROUVÉ la référence dans
          // son historique bancaire. Ce n'est pas une vérification
          // automatique, et le dossier ne doit pas le laisser croire.
          Text(
            '${a.verifiedCount} paiement${a.verifiedCount > 1 ? 's' : ''} sur '
            '${a.orderCount} retrouvé${a.verifiedCount > 1 ? 's' : ''} en banque '
            'par la commerçante',
            style: const TextStyle(fontSize: 11.5, height: 1.3, color: AppTheme.muted),
          ),
          const SizedBox(height: 14),
          if (providers.isEmpty)
            const Text('Aucun encaissement enregistré.',
                style: TextStyle(fontSize: 13, color: AppTheme.muted))
          else
            for (final e in providers)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontSize: 13, color: AppTheme.ink2)),
                    ),
                    Text(Money.format(e.value),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ReadinessSection extends StatelessWidget {
  final VendorAnalytics analytics;
  const _ReadinessSection({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text('PRÉPARATION FINANCIÈRE',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppTheme.ink)),
              ),
              Text('${a.readinessScore.round()}',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.green)),
              const Text(' / 100',
                  style: TextStyle(fontSize: 13, color: AppTheme.ink2)),
            ],
          ),
          const SizedBox(height: 14),
          // La formule est dans le dossier, pas seulement à l'écran : un
          // partenaire financier qui reçoit un chiffre doit pouvoir voir
          // comment il est obtenu, sinon le chiffre ne vaut rien.
          for (final p in a.readinessParts) ...[
            Row(
              children: [
                Expanded(
                  child: Text(p.label,
                      style: const TextStyle(fontSize: 13, color: AppTheme.ink)),
                ),
                Text('${p.score.round()} / 25',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (p.score / 25).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppTheme.line,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.green),
              ),
            ),
            const SizedBox(height: 3),
            Text(p.detail,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 40, color: AppTheme.muted),
            SizedBox(height: 12),
            Text('Pas encore de dossier',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            SizedBox(height: 6),
            Text(
              'Votre dossier se construit tout seul à partir de vos ventes. '
              'Il apparaîtra dès votre première commande.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: AppTheme.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final VoidCallback onRetry;
  const _Error({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: AppTheme.muted),
            const SizedBox(height: 12),
            const Text('Impossible de charger votre dossier',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
