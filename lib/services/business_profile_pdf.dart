import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/money.dart';
import '../models/models.dart';
import 'analytics_service.dart';

/// Génération du dossier d'activité en PDF (21 septembre 2026).
///
/// Remplace le « copier-coller » de la première version : une entreprise
/// qui sollicite un partenaire financier envoie un DOCUMENT, pas un bloc
/// de texte collé dans une conversation.
///
/// Séparé de l'écran : la mise en page PDF n'a rien à voir avec la mise en
/// page Flutter (deux bibliothèques de widgets distinctes, `pw.` ici), et
/// la garder à part permet de la réutiliser ailleurs — par exemple pour un
/// envoi automatique à un partenaire, si cela se fait un jour.
///
/// Aucune police n'est embarquée : on utilise les polices Helvetica
/// intégrées au format PDF lui-même. C'est ce qui permet d'ajouter cette
/// fonctionnalité sans alourdir l'application d'un seul octet de fonte —
/// au prix de l'arabe, que ces polices ne couvrent pas. Le dossier est
/// donc en français, langue dans laquelle se traitent les dossiers
/// bancaires en Mauritanie.
class BusinessProfilePdf {
  BusinessProfilePdf._();

  static const _disclaimer =
      'Ce dossier résume une activité commerciale enregistrée sur Boutigui. Il ne '
      'constitue ni une décision de crédit, ni une garantie de financement, ni '
      'une évaluation par un établissement financier. Les chiffres sont '
      'calculés automatiquement à partir des commandes réelles de la boutique.';

  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  static String _today() {
    final n = DateTime.now();
    return '${n.day} ${_months[n.month - 1]} ${n.year}';
  }

  static PdfColor get _green => const PdfColor.fromInt(0xFF14532D);
  static PdfColor get _ink => const PdfColor.fromInt(0xFF2B2B2B);
  static PdfColor get _ink2 => const PdfColor.fromInt(0xFF5C5658);
  static PdfColor get _line => const PdfColor.fromInt(0xFFE8E2E3);
  static PdfColor get _tint => const PdfColor.fromInt(0xFFEAF4EA);

  static Future<List<int>> build({
    required Shop? shop,
    required VendorAnalytics a,
  }) async {
    final doc = pw.Document(
      title: 'Dossier d\'activité — ${shop?.name ?? 'Boutigui'}',
      author: 'Boutigui',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
        // Pied de page sur CHAQUE page : un dossier se lit souvent imprimé
        // et désagrafé, chaque feuille doit se rattacher à son émetteur.
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'Boutigui · ${shop?.name ?? ''} · page ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _ink2),
          ),
        ),
        build: (context) => [
          _header(shop),
          pw.SizedBox(height: 22),
          _section('Historique sur la place de marché', [
            ('Commandes honorées', '${a.orderCount}'),
            ('Volume de ventes', Money.format(a.revenue)),
            ('Panier moyen', Money.format(a.averageOrderValue)),
            ('Clientes distinctes', '${a.customerCount}'),
            ('Commandes par cliente', _repeat(a)),
          ]),
          pw.SizedBox(height: 16),
          _payments(a),
          pw.SizedBox(height: 16),
          _readiness(a),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF6F3F4),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(_disclaimer,
                style: pw.TextStyle(fontSize: 8.5, color: _ink2, lineSpacing: 2)),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static String _repeat(VendorAnalytics a) =>
      a.customerCount == 0 ? '—' : (a.orderCount / a.customerCount).toStringAsFixed(1);

  static pw.Widget _header(Shop? shop) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _tint,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('DOSSIER D\'ACTIVITÉ',
                  style: pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontWeight: pw.FontWeight.bold,
                      color: _green)),
              pw.Text('Boutigui',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(shop?.name ?? '',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 16,
            runSpacing: 3,
            children: [
              if (shop?.city != null && shop!.city!.isNotEmpty)
                _meta('Ville', shop.city!),
              if (shop?.createdAt != null)
                _meta('Active depuis', monthYear(shop!.createdAt!)),
              if (shop?.merchantProvider != null && shop!.merchantProvider!.isNotEmpty)
                _meta('Encaissement', shop.merchantProvider!),
              _meta('Édité le', _today()),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _meta(String label, String value) => pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
              text: '$label : ',
              style: pw.TextStyle(fontSize: 9, color: _ink2)),
          pw.TextSpan(
              text: value,
              style: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
        ]),
      );

  static pw.Widget _title(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text(text.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: pw.FontWeight.bold,
                color: _ink)),
      );

  static pw.Widget _section(String title, List<(String, String)> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _title(title),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: 0.5),
            top: pw.BorderSide(color: _line, width: 0.5),
            bottom: pw.BorderSide(color: _line, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2),
          },
          children: [
            for (final row in rows)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 7),
                  child: pw.Text(row.$1,
                      style: pw.TextStyle(fontSize: 10, color: _ink2)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 7),
                  child: pw.Text(row.$2,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                ),
              ]),
          ],
        ),
      ],
    );
  }

  static pw.Widget _payments(VendorAnalytics a) {
    final providers = a.revenueByProvider.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _title('Paiements numériques'),
        // Formulation exacte : la commerçante a RETROUVÉ la référence dans
        // son historique bancaire. Ce n'est pas une vérification
        // automatique, et un document destiné à une banque ne doit surtout
        // pas le laisser croire.
        pw.Text(
          '${a.verifiedCount} paiement${a.verifiedCount > 1 ? 's' : ''} sur '
          '${a.orderCount} retrouvé${a.verifiedCount > 1 ? 's' : ''} en banque '
          'par la commerçante.',
          style: pw.TextStyle(fontSize: 9, color: _ink2),
        ),
        pw.SizedBox(height: 3),
        // Les écarts sont déclarés, y compris quand il n'y en a aucun :
        // un dossier qui tait ce qu'il ne mesure pas n'est pas fiable.
        pw.Text(
          a.mismatchCount == 0
              ? 'Aucun écart entre les montants reçus et les totaux des commandes.'
              : '${a.mismatchCount} commande${a.mismatchCount > 1 ? 's' : ''} '
                  'présente${a.mismatchCount > 1 ? 'nt' : ''} un écart entre le '
                  'montant reçu et le total dû.',
          style: pw.TextStyle(fontSize: 9, color: _ink2),
        ),
        pw.SizedBox(height: 10),
        if (providers.isEmpty)
          pw.Text('Aucun encaissement enregistré.',
              style: pw.TextStyle(fontSize: 10, color: _ink2))
        else
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
              top: pw.BorderSide(color: _line, width: 0.5),
              bottom: pw.BorderSide(color: _line, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
            },
            children: [
              for (final e in providers)
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 7),
                    child: pw.Text(e.key,
                        style: pw.TextStyle(fontSize: 10, color: _ink2)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 7),
                    child: pw.Text(Money.format(e.value),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                  ),
                ]),
            ],
          ),
      ],
    );
  }

  static pw.Widget _readiness(VendorAnalytics a) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _title('Préparation financière'),
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: '${a.readinessScore.round()}',
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold, color: _green)),
                pw.TextSpan(
                    text: ' / 100',
                    style: pw.TextStyle(fontSize: 10, color: _ink2)),
              ]),
            ),
          ],
        ),
        // La FORMULE accompagne le chiffre. Un score transmis sans la
        // façon dont il est obtenu ne vaut rien pour qui le reçoit — et un
        // partenaire financier a le droit de vérifier le calcul.
        for (final p in a.readinessParts)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 9),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(p.label,
                        style: pw.TextStyle(fontSize: 10, color: _ink)),
                    pw.Text('${p.score.round()} / 25',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Stack(children: [
                  pw.Container(height: 4, decoration: pw.BoxDecoration(color: _line)),
                  pw.Container(
                    height: 4,
                    width: (p.score / 25).clamp(0.0, 1.0) * 515,
                    decoration: pw.BoxDecoration(color: _green),
                  ),
                ]),
                pw.SizedBox(height: 2),
                pw.Text(p.detail,
                    style: pw.TextStyle(fontSize: 8, color: _ink2)),
              ],
            ),
          ),
      ],
    );
  }
}
