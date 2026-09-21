import 'package:flutter/material.dart';
import 'strings.dart';

/// Langue et sens d'écriture.
///
/// **15 septembre 2026, deuxième correction : l'anglais et le français
/// sont maintenant deux vraies langues sélectionnables** (voir
/// `Strings.t`) — un premier passage avait figé l'app en anglais quoi que
/// la personne choisisse dans le sélecteur, ce qui donnait l'impression
/// que "la traduction vers le français ne marche pas". L'arabe, lui,
/// reste retiré du sélecteur (demande explicite séparée) : ses traductions
/// existent toujours dans `Strings` mais ne sont plus atteignables depuis
/// l'écran Compte.
class SettingsController extends ChangeNotifier {
  String _locale = 'en';

  String get locale => _locale;

  // L'arabe n'étant plus sélectionnable, le sens d'écriture reste toujours
  // LTR — pas besoin de suivre `_locale` ici.
  bool get isRtl => false;

  TextDirection get textDirection => TextDirection.ltr;

  void setLocale(String value) {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
  }

  String t(String key) => Strings.t(key, _locale);
}
