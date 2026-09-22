import 'package:supabase_flutter/supabase_flutter.dart';

/// Statistiques d'activité d'une boutique — couche « Comprendre » de Boutigui
/// (20 septembre 2026).
///
/// Tout est DÉRIVÉ de `orders` / `order_items`. Aucune table de
/// statistiques, aucun chiffre stocké : une valeur enregistrée quelque
/// part finit toujours par diverger de la commande qu'elle résume, et il
/// faudrait la recalculer à chaque changement de statut. Sur le volume
/// d'une boutique de quartier, une agrégation à la lecture coûte moins
/// cher que la désynchronisation qu'on éviterait.
///
/// Une commande annulée ou dont le paiement a été rejeté ne compte jamais
/// dans le chiffre d'affaires.
/// Un point de la courbe des ventes.
class DailyPoint {
  final DateTime day;
  final double revenue;
  final int orders;
  const DailyPoint({required this.day, required this.revenue, required this.orders});
}
/// Performance d'un produit sur la période.
class ProductPerf {
  final String name;
  final int quantity;
  final double revenue;
  const ProductPerf({required this.name, required this.quantity, required this.revenue});
}
/// Un des quatre volets de l'indice de préparation financière.
///
/// [detail] est la PHRASE qui explique d'où vient la note. L'indice est
/// affiché avec sa formule : un jury fintech demande toujours comment un
/// score est calculé, et « c'est notre algorithme » est une mauvaise
/// réponse. Voir aussi `FINTECH_PLAN.md`, étape 6.
class ReadinessPart {
  final String label;
  final double score; // 0..25
  final String detail;
  const ReadinessPart({required this.label, required this.score, required this.detail});
}
class VendorAnalytics {
  final int rangeDays;
  final double revenue;
  final int orderCount;
  final int customerCount;
  final double averageOrderValue;
  /// Évolution du chiffre d'affaires par rapport à la période
  /// précédente de même durée. `null` si cette période précédente est
  /// vide : on n'affiche pas « +100 % » pour une première vente.
  final double? revenueGrowthPct;
  final List<DailyPoint> salesByDay;
  final Map<String, double> revenueByProvider;
  final List<ProductPerf> topProducts;
  final List<ProductPerf> slowProducts;
  /// 1 = lundi … 7 = dimanche (convention `DateTime.weekday`).
  final Map<int, int> ordersByWeekday;
  final int awaitingVerification;
  final int verifiedCount;
  /// Commandes vérifiées dont le montant reçu s'écarte du total dû
  /// (21 septembre 2026). Zéro est une information, pas une absence
  /// d'information : c'est ce qu'un partenaire financier veut voir.
  final int mismatchCount;
  final List<ReadinessPart> readinessParts;
  const VendorAnalytics({
    required this.rangeDays,
    required this.revenue,
    required this.orderCount,
    required this.customerCount,
    required this.averageOrderValue,
    required this.revenueGrowthPct,
    required this.salesByDay,
    required this.revenueByProvider,
    required this.topProducts,
    required this.slowProducts,
    required this.ordersByWeekday,
    required this.awaitingVerification,
    required this.verifiedCount,
    required this.mismatchCount,
    required this.readinessParts,
  });
  bool get isEmpty => orderCount == 0;
  double get readinessScore =>
      readinessParts.fold<double>(0, (sum, p) => sum + p.score);
  /// Le jour de la semaine le plus actif, ou `null` si aucune commande
  /// ne se détache (égalité parfaite, ou pas assez de données pour que
  /// l'observation veuille dire quelque chose).
  int? get busiestWeekday {
    if (orderCount < 5 || ordersByWeekday.isEmpty) return null;
    final sorted = ordersByWeekday.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.length > 1 && sorted[0].value == sorted[1].value) return null;
    return sorted.first.key;
  }
}
class AnalyticsService {
  final SupabaseClient _client = Supabase.instance.client;
  /// Charge tout ce dont le tableau de bord a besoin, en une requête.
  ///
  /// On lit une période DOUBLE puis on la coupe en deux : la période
  /// affichée et celle d'avant, qui sert uniquement au calcul de
  /// l'évolution. Deux fois plus de lignes lues, mais un seul aller-retour.
  Future<VendorAnalytics> fetchForShop(String shopId, {int rangeDays = 30}) async {
    final now = DateTime.now();
    final periodStart = now.subtract(Duration(days: rangeDays));
    final previousStart = now.subtract(Duration(days: rangeDays * 2));
    final rows = await _client
        .from('orders')
        .select('*, order_items(product_name, quantity, subtotal)')
        .eq('shop_id', shopId)
        .gte('created_at', previousStart.toIso8601String())
        .order('created_at', ascending: false);
    final shopRow = await _client
        .from('shops')
        .select('name, description, logo_url, city, whatsapp_phone, merchant_code, merchant_provider, lat, created_at')
        .eq('id', shopId)
        .maybeSingle();
    return _build(
      rows: List<Map<String, dynamic>>.from(rows),
      shop: shopRow,
      now: now,
      periodStart: periodStart,
      rangeDays: rangeDays,
    );
  }
  // ---------------------------------------------------------------- calcul
  //
  // Séparé de la requête pour rester testable sans base : on peut lui
  // passer des lignes fabriquées à la main.
  VendorAnalytics _build({
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic>? shop,
    required DateTime now,
    required DateTime periodStart,
    required int rangeDays,
  }) {
    double revenue = 0;
    double previousRevenue = 0;
    int orderCount = 0;
    int awaiting = 0;
    int verified = 0;
    int mismatch = 0;
    final customers = <String>{};
    final byDay = <DateTime, DailyPoint>{};
    final byProvider = <String, double>{};
    final byWeekday = <int, int>{};
    final byProduct = <String, ProductPerf>{};
    final activeWeeks = <int>{};
    for (final row in rows) {
      final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (createdAt == null) continue;
      final status = row['status'] as String? ?? 'pending';
      final paymentStatus = row['payment_status'] as String? ?? 'submitted';
      // Ni une commande annulée ni un paiement rejeté ne sont du chiffre
      // d'affaires. Les compter gonflerait les statistiques exactement là
      // où la crédibilité du produit se joue.
      final counts = status != 'cancelled' && paymentStatus != 'rejected';
      final total = (row['total'] as num?)?.toDouble() ?? 0;
      if (createdAt.isBefore(periodStart)) {
        if (counts) previousRevenue += total;
        continue;
      }
      if (!counts) continue;
      orderCount++;
      revenue += total;
      if (paymentStatus == 'verified') {
        verified++;
        final received = (row['payment_amount_received'] as num?)?.toDouble();
        if (received != null && (received - total).abs() > 1) mismatch++;
      } else if (paymentStatus == 'submitted') {
        awaiting++;
      }
      final clientId = row['client_id'] as String?;
      if (clientId != null) customers.add(clientId);
      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final existing = byDay[day];
      byDay[day] = DailyPoint(
        day: day,
        revenue: (existing?.revenue ?? 0) + total,
        orders: (existing?.orders ?? 0) + 1,
      );
      byWeekday[createdAt.weekday] = (byWeekday[createdAt.weekday] ?? 0) + 1;
      activeWeeks.add(now.difference(day).inDays ~/ 7);
      final provider = (row['payment_provider'] as String?)?.trim();
      final providerKey = provider == null || provider.isEmpty ? 'Autre' : provider;
      byProvider[providerKey] = (byProvider[providerKey] ?? 0) + total;
      for (final item in (row['order_items'] as List? ?? const [])) {
        final map = item as Map<String, dynamic>;
        // Le nom recopié à l'achat porte l'option choisie (« Robe — 38 »).
        // On regroupe sur le produit, pas sur la variante, sinon le
        // « meilleure vente » se disperse sur les tailles.
        final name = (map['product_name'] as String? ?? '').split(' — ').first.trim();
        if (name.isEmpty) continue;
        final qty = (map['quantity'] as num?)?.toInt() ?? 0;
        final sub = (map['subtotal'] as num?)?.toDouble() ?? 0;
        final prev = byProduct[name];
        byProduct[name] = ProductPerf(
          name: name,
          quantity: (prev?.quantity ?? 0) + qty,
          revenue: (prev?.revenue ?? 0) + sub,
        );
      }
    }
    final points = byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
    final products = byProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return VendorAnalytics(
      rangeDays: rangeDays,
      revenue: revenue,
      orderCount: orderCount,
      customerCount: customers.length,
      averageOrderValue: orderCount == 0 ? 0 : revenue / orderCount,
      // Pas de période précédente = pas d'évolution affichable.
      revenueGrowthPct: previousRevenue <= 0
          ? null
          : ((revenue - previousRevenue) / previousRevenue) * 100,
      salesByDay: points,
      revenueByProvider: byProvider,
      topProducts: products.take(5).toList(),
      // Les deux listes ne doivent JAMAIS se recouper (21 septembre 2026,
      // audit) : `products.reversed.take(3)` prenait les trois derniers
      // d'une liste qui en compte souvent moins de huit, si bien qu'une
      // boutique de trois produits voyait les mêmes articles affichés à la
      // fois en « meilleures ventes » et en « ventes lentes ». En dessous
      // Les ventes lentes sont donc ce qui RESTE une fois les cinq
      // meilleures prises, trois au plus. Cinq produits ou moins : la
      // liste est vide, et l'écran n'affiche pas la section — il n'y a
      // rien à comparer, mieux vaut ne rien dire qu'inventer un classement.
      slowProducts: products.reversed.take((products.length - 5).clamp(0, 3)).toList(),
      ordersByWeekday: byWeekday,
      awaitingVerification: awaiting,
      verifiedCount: verified,
      mismatchCount: mismatch,
      readinessParts: _readiness(
        shop: shop,
        orderCount: orderCount,
        verified: verified,
        activeWeeks: activeWeeks.length,
        rangeDays: rangeDays,
      ),
    );
  }
  // ----------------------------------------------- préparation financière
  //
  // Quatre volets de 25 points, chacun rattaché à un fait COMPTABLE que la
  // vendeuse peut vérifier elle-même. Rien de personnel n'entre dans ce
  // calcul : ni âge, ni genre, ni quartier, ni aucune donnée protégée —
  // uniquement l'activité commerciale de la boutique.
  //
  // Ce n'est PAS un score de crédit et l'écran doit le dire. C'est un
  // indicateur interne de complétude : est-ce que cette boutique a assez
  // d'activité numérique pour qu'un dossier ait du sens ?
  List<ReadinessPart> _readiness({
    required Map<String, dynamic>? shop,
    required int orderCount,
    required int verified,
    required int activeWeeks,
    required int rangeDays,
  }) {
    final weeksInRange = (rangeDays / 7).ceil();
    final consistency = weeksInRange == 0 ? 0.0 : (activeWeeks / weeksInRange).clamp(0.0, 1.0);
    // 40 commandes sur la période = volume « établi ». Le palier est
    // arbitraire et assumé : il est écrit ici, pas caché.
    const volumeTarget = 40;
    final volume = (orderCount / volumeTarget).clamp(0.0, 1.0);
    final digital = orderCount == 0 ? 0.0 : (verified / orderCount).clamp(0.0, 1.0);
    const fields = [
      'name', 'description', 'logo_url', 'city',
      'whatsapp_phone', 'merchant_code', 'merchant_provider', 'lat',
    ];
    final filled = shop == null
        ? 0
        : fields.where((f) {
            final v = shop[f];
            return v != null && v.toString().trim().isNotEmpty;
          }).length;
    final completeness = filled / fields.length;
    return [
      ReadinessPart(
        label: 'Régularité de l\'activité',
        score: consistency * 25,
        detail: '$activeWeeks semaine${activeWeeks > 1 ? 's' : ''} avec au moins '
            'une vente sur $weeksInRange',
      ),
      ReadinessPart(
        label: 'Volume de commandes',
        score: volume * 25,
        detail: '$orderCount commande${orderCount > 1 ? 's' : ''} sur la période '
            '(palier de référence : $volumeTarget)',
      ),
      ReadinessPart(
        label: 'Paiements numériques confirmés',
        score: digital * 25,
        detail: '$verified paiement${verified > 1 ? 's' : ''} retrouvé'
            '${verified > 1 ? 's' : ''} en banque sur $orderCount',
      ),
      ReadinessPart(
        label: 'Profil de la boutique',
        score: completeness * 25,
        detail: '$filled information${filled > 1 ? 's' : ''} renseignée'
            '${filled > 1 ? 's' : ''} sur ${fields.length}',
      ),
    ];
  }
}
/// Phrases de « Boutigui Insights » (20 septembre 2026).
///
/// Générées EN DART à partir des statistiques déjà calculées, pas par un
/// modèle appelé depuis le téléphone. L'application est aussi déployée sur
/// le web (`netlify.toml`) : une clé d'API dans le bundle serait lisible
/// par n'importe qui, ce qui contredirait exactement le discours sécurité
/// de la présentation. Si un modèle est branché plus tard, ce sera depuis
/// une Edge Function Supabase qui garde la clé côté serveur.
///
/// Chaque phrase est étiquetée : une OBSERVATION est lue dans les données,
/// une SUGGESTION est une recommandation. Ne jamais présenter la seconde
/// comme la première.
class Insight {
  final String text;
  final bool isSuggestion;
  const Insight(this.text, {this.isSuggestion = false});
}
class BoutiguiInsights {
  static const _weekdays = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  static List<Insight> from(VendorAnalytics a) {
    if (a.isEmpty) return const [];
    final out = <Insight>[];
    final growth = a.revenueGrowthPct;
    if (growth != null && growth.abs() >= 5) {
      out.add(Insight(growth > 0
          ? 'Vos ventes ont augmenté de ${growth.abs().round()} % par rapport '
              'aux ${a.rangeDays} jours précédents.'
          : 'Vos ventes ont baissé de ${growth.abs().round()} % par rapport '
              'aux ${a.rangeDays} jours précédents.'));
    }
    final busiest = a.busiestWeekday;
    if (busiest != null) {
      out.add(Insight('Votre jour le plus actif est le ${_weekdays[busiest - 1]}.'));
      out.add(Insight(
        'Pensez à renforcer votre stock avant le ${_weekdays[busiest - 1]}.',
        isSuggestion: true,
      ));
    }
    if (a.topProducts.isNotEmpty) {
      out.add(Insight('Votre meilleure vente est « ${a.topProducts.first.name} ».'));
    }
    if (a.revenueByProvider.isNotEmpty && a.revenue > 0) {
      final top = a.revenueByProvider.entries.reduce((x, y) => x.value >= y.value ? x : y);
      final share = (top.value / a.revenue * 100).round();
      out.add(Insight('$share % de vos encaissements passent par ${top.key}.'));
    }
    if (a.awaitingVerification > 0) {
      out.add(Insight(
        '${a.awaitingVerification} référence${a.awaitingVerification > 1 ? 's' : ''} '
        'de paiement ${a.awaitingVerification > 1 ? 'restent' : 'reste'} à vérifier '
        'dans votre application bancaire.',
        isSuggestion: true,
      ));
    }
    if (a.customerCount > 0 && a.orderCount > a.customerCount) {
      final repeat = a.orderCount / a.customerCount;
      if (repeat >= 1.3) {
        out.add(Insight(
          'Vos clientes commandent en moyenne ${repeat.toStringAsFixed(1)} fois : '
          'votre activité repose déjà sur des clientes qui reviennent.',
        ));
      }
    }
    return out;
  }
}
