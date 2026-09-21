import 'package:intl/intl.dart';
import '../app_config.dart';

/// Formatage des montants en ouguiya (MRU).
class Money {
  Money._();

  static final NumberFormat _formatter = NumberFormat.decimalPattern('fr');

  /// Ex: 12500 -> "12 500 UM"
  static String format(num amount) {
    return '${_formatter.format(amount)} ${AppConfig.currencySymbol}';
  }

  static String formatCompact(num amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M ${AppConfig.currencySymbol}';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}k ${AppConfig.currencySymbol}';
    }
    return format(amount);
  }
}
