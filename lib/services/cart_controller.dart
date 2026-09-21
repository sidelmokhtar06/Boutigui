import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Panier local — n'existe jamais en base tant que la commande n'est pas
/// validée : rien à écrire côté serveur à chaque ajout, et une commande =
/// une boutique, donc le panier est découpé PAR boutique dès l'ajout.
class CartController extends ChangeNotifier {
  // Clé = CartLine.cartKey (produit seul, ou "produit::option" — 5 septembre
  // 2026, voir models.dart) : un même produit choisi deux fois avec une
  // option DIFFÉRENTE (ex: taille 38 puis taille 40) forme deux lignes.
  final Map<String, CartLine> _lines = {};

  List<CartLine> get lines => _lines.values.toList();

  int get itemCount => _lines.values.fold(0, (sum, l) => sum + l.quantity);

  double get total => _lines.values.fold(0, (sum, l) => sum + l.subtotal);

  bool get isEmpty => _lines.isEmpty;

  /// Regroupe les lignes par boutique — une commande sera créée par groupe.
  Map<String, List<CartLine>> get linesByShop {
    final map = <String, List<CartLine>>{};
    for (final line in _lines.values) {
      map.putIfAbsent(line.product.shopId, () => []).add(line);
    }
    return map;
  }

  double totalForShop(String shopId) =>
      linesByShop[shopId]?.fold<double>(0, (sum, l) => sum + l.subtotal) ?? 0;

  /// Ajoute au panier — plafonné au stock disponible depuis le 15
  /// septembre 2026 (demande explicite : "le client ne peut pas commander
  /// deux rouges à lèvres si le vendeur n'en a qu'un seul"). Retourne
  /// `true` si la quantité demandée a dû être réduite (ou totalement
  /// refusée) pour respecter le stock, pour que l'écran appelant puisse
  /// prévenir la cliente.
  bool add(Product product, {int quantity = 1, String? selectedOption}) {
    final key = selectedOption == null ? product.id : '${product.id}::$selectedOption';
    final existing = _lines[key];
    final currentQty = existing?.quantity ?? 0;
    final room = product.stock - currentQty;
    final addable = quantity < room ? quantity : (room > 0 ? room : 0);
    final wasCapped = addable < quantity;
    if (addable <= 0) return true;
    if (existing != null) {
      existing.quantity += addable;
    } else {
      _lines[key] = CartLine(product: product, quantity: addable, selectedOption: selectedOption);
    }
    notifyListeners();
    return wasCapped;
  }

  /// Plafonnée au stock au même titre que [add] — la personne ne doit pas
  /// pouvoir contourner la limite en appuyant sur "+" dans le panier.
  void updateQuantity(String cartKey, int quantity) {
    if (quantity <= 0) {
      _lines.remove(cartKey);
    } else {
      final line = _lines[cartKey];
      if (line != null) line.quantity = quantity > line.product.stock ? line.product.stock : quantity;
    }
    notifyListeners();
  }

  void remove(String cartKey) {
    _lines.remove(cartKey);
    notifyListeners();
  }

  void clearShop(String shopId) {
    _lines.removeWhere((_, line) => line.product.shopId == shopId);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
