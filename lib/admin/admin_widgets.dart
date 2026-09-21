import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Sous ce seuil, les écrans admin passent d'une mise en page "large"
/// (lignes côte à côte, comme sur un ordinateur) à une mise en page
/// "étroite" empilée verticalement — ajouté le 2 septembre 2026 : le site
/// admin était pensé uniquement pour un écran d'ordinateur et devenait
/// illisible/inutilisable sur téléphone.
bool isNarrowAdmin(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

/// Largeur à donner à un dialogue (`AlertDialog` / `SizedBox` dans
/// `content`) pour qu'il ne déborde jamais d'un écran étroit : la valeur
/// voulue sur ordinateur, plafonnée à la largeur de l'écran moins ses marges.
double adminDialogWidth(BuildContext context, double desired) {
  return (MediaQuery.sizeOf(context).width - 48).clamp(240, desired);
}

/// En-tête de page commun à tous les écrans admin : titre, sous-titre
/// optionnel, bouton d'action à droite (ex. "+ Ajouter") — passe en colonne
/// (action sous le titre, pleine largeur) sur écran étroit.
class AdminPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const AdminPageHeader({super.key, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final narrow = isNarrowAdmin(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AdminTheme.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: const TextStyle(fontSize: 13, color: AdminTheme.muted)),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 28, 20, narrow ? 16 : 28, 16),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            )
          : Row(
              children: [
                Expanded(child: titleBlock),
                if (action != null) action!,
              ],
            ),
    );
  }
}

/// Carte blanche standard pour envelopper une liste ou un formulaire.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AdminCard({super.key, required this.child, this.padding = const EdgeInsets.all(4)});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      padding: padding,
      child: child,
    );
  }
}

class AdminStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const AdminStatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
      ],
    ),
  );
  return result ?? false;
}

/// Affiche une erreur à l'admin — depuis le 4 septembre 2026, on n'affiche
/// plus jamais le message brut de l'exception (ex. `PostgrestException`)
/// à l'écran : il peut contenir des détails internes (nom de table, de
/// colonne, de contrainte SQL...) que personne d'autre que nous n'a besoin
/// de voir, et ce n'est pas professionnel. Le détail complet reste dans la
/// console de débogage (visible seulement en développement).
void showAdminError(BuildContext context, Object error) {
  debugPrint('Erreur admin : $error');
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Something went wrong. Try again, and if it keeps happening, check your internet connection."),
    ),
  );
}
