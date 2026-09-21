import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import 'business_profile_screen.dart';
import '../widgets.dart';

/// Tableau de bord de la vendeuse — l'écran central de la démo fintech
/// (20 septembre 2026).
///
/// Il répond aux quatre questions de la checklist UI du roadmap :
/// qu'est-ce que je regarde, qu'est-ce que je peux faire, pourquoi c'est
/// important, qu'est-ce qui se passe ensuite.
///
/// Aucune dépendance graphique n'a été ajoutée : la courbe est dessinée au
/// [CustomPainter]. `google_fonts` avait déjà coûté une journée en
/// septembre pour cause d'incompatibilité de version, on ne recommence pas
/// à huit jours du hackathon pour une courbe de soixante lignes.
class VendorDashboardScreen extends StatefulWidget {
  final String shopId;
  final String shopName;
  final String vendorFirstName;

  const VendorDashboardScreen({
    super.key,
    required this.shopId,
    required this.shopName,
    this.vendorFirstName = '',
  });

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  final AnalyticsService _analytics = AnalyticsService();
  late Future<VendorAnalytics> _future;
  int _range = 30;

  /// Prénom de la vendeuse, lu dans la session déjà en mémoire — pas de
  /// requête supplémentaire pour afficher « Bonjour Aïcha ».
  String get _firstName {
    if (widget.vendorFirstName.trim().isNotEmpty) return widget.vendorFirstName;
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final full = (meta?['full_name'] as String?)?.trim() ?? '';
    return full.isEmpty ? '' : full.split(' ').first;
  }

  @override
  void initState() {
    super.initState();
    _future = _analytics.fetchForShop(widget.shopId, rangeDays: _range);
  }

  void _reload({int? range}) {
    setState(() {
      if (range != null) _range = range;
      _future = _analytics.fetchForShop(widget.shopId, rangeDays: _range);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Mon activité'),
        backgroundColor: AppTheme.bg,
      ),
      body: FutureBuilder<VendorAnalytics>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _DashboardSkeleton();
          }
          if (snap.hasError) {
            return _DashboardError(onRetry: _reload);
          }
          final a = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Greeting(name: _firstName, shop: widget.shopName),
                const SizedBox(height: 16),
                _RangePicker(value: _range, onChanged: (v) => _reload(range: v)),
                const SizedBox(height: 16),
                if (a.isEmpty)
                  const _NoSalesYet()
                else ...[
                  _KpiGrid(a: a),
                  const SizedBox(height: 24),
                  _Block(
                    title: 'Ventes',
                    subtitle: 'Chiffre d\'affaires jour par jour',
                    child: SalesChart(points: a.salesByDay),
                  ),
                  const SizedBox(height: 16),
                  _Block(
                    title: 'Encaissements',
                    subtitle: 'Répartition par service de paiement',
                    child: _ProviderSplit(a: a),
                  ),
                  const SizedBox(height: 16),
                  _Block(
                    title: 'Produits',
                    subtitle: 'Vos meilleures ventes sur la période',
                    child: _TopProducts(a: a),
                  ),
                  const SizedBox(height: 16),
                  _ReadinessBlock(a: a, shopId: widget.shopId),
                  const SizedBox(height: 16),
                  _InsightsBlock(a: a),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- en-tête

class _Greeting extends StatelessWidget {
  final String name;
  final String shop;
  const _Greeting({required this.name, required this.shop});

  @override
  Widget build(BuildContext context) {
    final hello = name.trim().isEmpty ? 'Bonjour 👋' : 'Bonjour ${name.trim()} 👋';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hello,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.ink)),
        const SizedBox(height: 4),
        Text('Voici l\'activité de $shop.',
            style: const TextStyle(fontSize: 14, color: AppTheme.ink2)),
      ],
    );
  }
}

class _RangePicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _RangePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = {7: '7 jours', 30: '30 jours', 90: '90 jours'};
    return Row(
      children: options.entries.map((e) {
        final selected = e.key == value;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppTheme.ink : AppTheme.panel,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                border: Border.all(color: AppTheme.line),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppTheme.bg : AppTheme.ink2,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// -------------------------------------------------------------- les chiffres

class _KpiGrid extends StatelessWidget {
  final VendorAnalytics a;
  const _KpiGrid({required this.a});

  @override
  Widget build(BuildContext context) {
    final growth = a.revenueGrowthPct;
    return LayoutBuilder(builder: (context, c) {
      // Deux colonnes dès qu'il y a la place, une seule sur les très
      // petits écrans — le tableau de bord se consulte au téléphone.
      final columns = c.maxWidth < 340 ? 1 : 2;
      final width = (c.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
              width: width,
              child: _Kpi(
                  value: Money.format(a.revenue),
                  label: 'Chiffre d\'affaires',
                  emphasis: true)),
          SizedBox(
              width: width,
              child: _Kpi(value: '${a.orderCount}', label: 'Commandes')),
          SizedBox(
              width: width,
              child: _Kpi(value: '${a.customerCount}', label: 'Clientes')),
          SizedBox(
            width: width,
            child: _Kpi(
              // « — » plutôt qu'un faux « +100 % » quand il n'y a pas de
              // période précédente à comparer.
              value: growth == null
                  ? '—'
                  : '${growth >= 0 ? '+' : ''}${growth.round()} %',
              label: growth == null ? 'Évolution (1re période)' : 'Évolution',
            ),
          ),
        ],
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  final String value;
  final String label;
  final bool emphasis;
  const _Kpi({required this.value, required this.label, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Le chiffre est visuellement plus fort que son libellé
          // (checklist « hiérarchie visuelle » du roadmap).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasis ? 24 : 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.ink2)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ courbe

/// Courbe des ventes, dessinée à la main.
///
/// Publique pour pouvoir être réutilisée ailleurs (écran profil financier)
/// sans dupliquer le tracé.
class SalesChart extends StatelessWidget {
  final List<DailyPoint> points;
  const SalesChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: Text('Pas encore assez de jours pour tracer une courbe.',
              style: TextStyle(fontSize: 13, color: AppTheme.muted)),
        ),
      );
    }
    final max = points.map((p) => p.revenue).reduce((x, y) => x > y ? x : y);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          width: double.infinity,
          child: CustomPaint(painter: _SalesPainter(points)),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_shortDate(points.first.day),
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            Text('Pic : ${Money.formatCompact(max)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            Text(_shortDate(points.last.day),
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
          ],
        ),
      ],
    );
  }

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _SalesPainter extends CustomPainter {
  final List<DailyPoint> points;
  _SalesPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final maxRevenue =
        points.map((p) => p.revenue).fold<double>(0, (x, y) => x > y ? x : y);
    // Une boutique peut avoir une journée à zéro : sans ce garde-fou on
    // diviserait par zéro et la courbe disparaîtrait.
    final scale = maxRevenue <= 0 ? 1.0 : maxRevenue;

    final firstDay = points.first.day;
    final span = points.last.day.difference(firstDay).inDays;
    double dx(int i) => span == 0
        ? 0
        : points[i].day.difference(firstDay).inDays / span * size.width;
    double dy(int i) => size.height - (points[i].revenue / scale) * (size.height - 8) - 4;

    final line = Path()..moveTo(dx(0), dy(0));
    for (var i = 1; i < points.length; i++) {
      line.lineTo(dx(i), dy(i));
    }

    // Aplat sous la courbe : la même trajectoire refermée sur la base.
    final fill = Path.from(line)
      ..lineTo(dx(points.length - 1), size.height)
      ..lineTo(dx(0), size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.copper.withValues(alpha: 0.22),
            AppTheme.copper.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = AppTheme.copper
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SalesPainter old) => old.points != points;
}

// ---------------------------------------------------------------- paiements

class _ProviderSplit extends StatelessWidget {
  final VendorAnalytics a;
  const _ProviderSplit({required this.a});

  @override
  Widget build(BuildContext context) {
    if (a.revenueByProvider.isEmpty || a.revenue <= 0) {
      return const Text('Aucun encaissement sur la période.',
          style: TextStyle(fontSize: 13, color: AppTheme.muted));
    }
    final entries = a.revenueByProvider.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return Column(
      children: [
        for (final e in entries) ...[
          _Bar(
            label: e.key,
            trailing: '${(e.value / a.revenue * 100).round()} %',
            fraction: e.value / a.revenue,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        if (a.awaitingVerification > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${a.awaitingVerification} référence'
              '${a.awaitingVerification > 1 ? 's' : ''} en attente de vérification.',
              style: const TextStyle(fontSize: 12, color: AppTheme.stockWarn),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final String trailing;
  final double fraction;
  const _Bar({required this.label, required this.trailing, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink)),
            Text(trailing,
                style: const TextStyle(fontSize: 13, color: AppTheme.ink2)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppTheme.line,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.copper),
          ),
        ),
      ],
    );
  }
}

class _TopProducts extends StatelessWidget {
  final VendorAnalytics a;
  const _TopProducts({required this.a});

  @override
  Widget build(BuildContext context) {
    if (a.topProducts.isEmpty) {
      return const Text('Aucun produit vendu sur la période.',
          style: TextStyle(fontSize: 13, color: AppTheme.muted));
    }
    final best = a.topProducts.first.revenue;
    return Column(
      children: [
        for (final p in a.topProducts) ...[
          _Bar(
            label: p.name,
            trailing: '${p.quantity} · ${Money.formatCompact(p.revenue)}',
            fraction: best <= 0 ? 0 : p.revenue / best,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ------------------------------------------------- préparation financière

class _ReadinessBlock extends StatelessWidget {
  final VendorAnalytics a;
  final String shopId;
  const _ReadinessBlock({required this.a, required this.shopId});

  @override
  Widget build(BuildContext context) {
    final score = a.readinessScore.round();
    return _Block(
      title: 'Préparation financière',
      subtitle: 'Un indicateur d\'activité, pas un score de crédit',
      // `shopId` sert au bouton « dossier » en bas du bloc.
      shopId: shopId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$score',
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              const SizedBox(width: 4),
              const Text('/ 100',
                  style: TextStyle(fontSize: 16, color: AppTheme.ink2)),
            ],
          ),
          const SizedBox(height: 16),
          // La FORMULE est affichée, pas seulement le résultat : chaque
          // volet vaut 25 points et dit sur quoi il se fonde. Un jury
          // fintech demande toujours comment le chiffre est calculé.
          for (final part in a.readinessParts) ...[
            _Bar(
              label: part.label,
              trailing: '${part.score.round()} / 25',
              fraction: part.score / 25,
            ),
            const SizedBox(height: 2),
            Text(part.detail,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: const Text(
              'Cet indicateur résume votre activité sur Boutigui. Il ne constitue '
              'ni une décision de crédit, ni une garantie de financement. Il '
              'peut aider un partenaire financier à mieux comprendre une '
              'activité difficile à évaluer autrement.',
              style: TextStyle(fontSize: 12, color: AppTheme.ink2, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Boutigui Insights

class _InsightsBlock extends StatelessWidget {
  final VendorAnalytics a;
  const _InsightsBlock({required this.a});

  @override
  Widget build(BuildContext context) {
    final insights = BoutiguiInsights.from(a);
    if (insights.isEmpty) return const SizedBox.shrink();
    return _Block(
      title: 'Boutigui Insights',
      subtitle: 'Lecture automatique de vos chiffres',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in insights) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Observation et suggestion se distinguent par l'icône ET
                // par le libellé, jamais par la couleur seule : le
                // roadmap l'impose au titre de l'accessibilité.
                Icon(
                  i.isSuggestion ? Icons.lightbulb_outline : Icons.insights_outlined,
                  size: 16,
                  color: i.isSuggestion ? AppTheme.copper : AppTheme.ink2,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.ink, height: 1.4),
                      children: [
                        TextSpan(
                          text: i.isSuggestion ? 'Suggestion — ' : 'Observation — ',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: AppTheme.ink2),
                        ),
                        TextSpan(text: i.text),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Ces phrases sont calculées à partir de vos commandes. '
            'Aucune donnée n\'est envoyée à un service externe.',
            style: TextStyle(fontSize: 11, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ cadres

class _Block extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  /// Quand il est fourni, un bouton « Générer mon dossier » est ajouté en
  /// bas du bloc — c'est la suite logique de l'indice : le score reste à
  /// l'écran, le dossier peut être envoyé à quelqu'un.
  final String? shopId;

  const _Block({required this.title, this.subtitle, required this.child, this.shopId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppTheme.ink)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          ],
          const SizedBox(height: 16),
          child,
          if (shopId != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BusinessProfileScreen(shopId: shopId!),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.greenDeep,
                  side: const BorderSide(color: AppTheme.line),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Générer mon dossier',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------- états vide / erreur

class _NoSalesYet extends StatelessWidget {
  const _NoSalesYet();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 48),
      child: EmptyState(
        icon: Icons.storefront_outlined,
        title: 'Pas encore de ventes',
        subtitle: 'Partagez votre boutique pour recevoir vos premières '
            'commandes. Vos statistiques apparaîtront ici automatiquement.',
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final VoidCallback onRetry;
  const _DashboardError({required this.onRetry});

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
            const Text('Impossible de charger vos données',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const SizedBox(height: 6),
            const Text('Vérifiez votre connexion et réessayez.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.ink2)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// Squelette de chargement — jamais d'écran blanc, jamais un simple
/// tourniquet au milieu du vide.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double height, {double width = double.infinity}) => Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        box(24, width: 180),
        const SizedBox(height: 8),
        box(14, width: 240),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: box(86)),
          const SizedBox(width: 12),
          Expanded(child: box(86)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: box(86)),
          const SizedBox(width: 12),
          Expanded(child: box(86)),
        ]),
        const SizedBox(height: 24),
        box(200),
        const SizedBox(height: 16),
        box(160),
      ],
    );
  }
}
