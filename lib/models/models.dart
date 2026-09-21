/// Modèles — miroir exact du schéma PostgreSQL (supabase/marketplace_schema.sql).
library models;

/// Réglages généraux de l'app (une seule ligne, `app_settings`) — numéro de
/// contact et lien vers un site de présentation, modifiables par l'admin
/// (ajouté le 3 septembre 2026, demande d'Emina).
class AppSettings {
  final String? contactPhone;
  final String? websiteUrl;

  AppSettings({this.contactPhone, this.websiteUrl});

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      contactPhone: map['contact_phone'] as String?,
      websiteUrl: map['website_url'] as String?,
    );
  }
}

class Profile {
  final String id;
  final String? email;
  final String? fullName;
  final String? phone;
  final String? city;
  final String? address;
  final String? avatarUrl;
  final String role; // client | vendor | admin
  final String? gender; // 'female' | 'male' | 'unspecified' — écran "Mon profil" (3 sept. 2026)

  Profile({
    required this.id,
    this.email,
    this.fullName,
    this.phone,
    this.city,
    this.address,
    this.avatarUrl,
    this.role = 'client',
    this.gender,
  });

  bool get isVendor => role == 'vendor';
  bool get isAdmin => role == 'admin';

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        email: map['email'] as String?,
        fullName: map['full_name'] as String?,
        phone: map['phone'] as String?,
        city: map['city'] as String?,
        address: map['address'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        role: (map['role'] as String?) ?? 'client',
        gender: map['gender'] as String?,
      );
}

class Shop {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;
  final String? city;
  final String? whatsappPhone;
  // Code marchand de la banque mobile de la vendeuse (Bankily, Masrvi,
  // Sedad...) et nom du service — ajoutés le 6 septembre 2026. La cliente
  // le voit au moment de payer et s'en sert dans son application bancaire
  // ("paiement commerçant" → code du commerçant → montant). L'argent va
  // donc directement à la vendeuse ; l'app ne touche pas aux fonds.
  final String? merchantCode;
  final String? merchantProvider;
  // Déclaration facultative de la propriétaire (20 septembre 2026) —
  // mesure d'impact uniquement, voir `supabase/inclusion_patch.sql`.
  // `null` = non renseigné. Ne conditionne AUCUNE fonctionnalité et
  // n'entre PAS dans l'indice de préparation financière.
  final bool? womenLed;
  // Point de collecte pour la livraison (15 septembre 2026, espace
  // Livreur) — renseigné une fois par la vendeuse dans "Ma boutique",
  // exactement comme la cliente donne sa position au moment de payer (voir
  // `OrderModel.deliveryLat/Lng`). Sert à calculer la distance affichée aux
  // livreuses avant qu'elles acceptent une course.
  final double? lat;
  final double? lng;
  final bool isVisible;
  // Ajouté le 4 septembre 2026, nuit — pour la ligne façon Oskelly "membre
  // depuis X" sur la page boutique (voir shop_detail_screen.dart). Rendu
  // optionnel (pas `required`) : certains appels historiques du code admin
  // sélectionnent des colonnes précises sans forcément inclure
  // `created_at` — mieux vaut afficher une boutique sans cette ligne que
  // faire planter l'analyse d'une ligne qui ne l'a pas.
  final DateTime? createdAt;

  Shop({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.city,
    this.whatsappPhone,
    this.merchantCode,
    this.merchantProvider,
    this.womenLed,
    this.lat,
    this.lng,
    this.isVisible = false,
    this.createdAt,
  });


  factory Shop.fromMap(Map<String, dynamic> map) => Shop(
        id: map['id'] as String,
        ownerId: map['owner_id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        logoUrl: map['logo_url'] as String?,
        coverUrl: map['cover_url'] as String?,
        city: map['city'] as String?,
        whatsappPhone: map['whatsapp_phone'] as String?,
        merchantCode: map['merchant_code'] as String?,
        merchantProvider: map['merchant_provider'] as String?,
        womenLed: map['women_led'] as bool?,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        isVisible: (map['is_visible'] as bool?) ?? false,
        createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      );
}

/// Catégories à un seul niveau depuis le 29 août 2026 (décision d'Emina —
/// plus de sous-catégories). [parentId] reste dans le modèle uniquement
/// pour rester compatible avec la colonne `parent_id` encore présente en
/// base (catégories créées avant ce changement) ; l'app et l'admin
/// n'en tiennent plus compte et ne créent plus que des catégories
/// racines (`parent_id = null`).
/// Format fixe d'une bande de catégorie. Utilisé à la fois par
/// categories_screen.dart (affichage côté cliente) et
/// categories_admin_screen.dart (cadrage/zoom côté admin), pour que les
/// deux correspondent exactement : ce que l'admin voit dans le cadre de
/// positionnement est exactement ce que la cliente verra.
///
/// **Format confirmé par Emina le 5 septembre 2026, après avoir vu le
/// rendu en 1920x690** (mesuré sur sa capture de référence) : elle
/// préfère finalement des bandes plus courtes — "diminuer la size du
/// catégorie en 1920x480". C'est donc bien 4.0, comme elle l'avait
/// indiqué au départ. Le nom de la catégorie a été réduit en même temps
/// (voir [AppTheme.categoryLabel]) : dans une bande deux fois plus
/// courte, la même lettre paraît plus grosse.
const double kCategoryImageAspectRatio = 1920 / 480;

class Category {
  final String id;
  final String? parentId;
  final String name;
  final String? imageUrl;
  final int sortOrder;
  final bool isVisible;
  // Point de la photo à toujours garder visible, et son zoom — même
  // principe que `Product.imageFocalX`/`imageFocalY`/`imageZoom` (5
  // septembre 2026, voir admin_patch.sql), mais pour la photo de la
  // catégorie elle-même (`image_url`), contrôlé depuis le site admin.
  // 0.5/0.5/1.0 = centre, pas de zoom (comportement d'avant ce champ).
  final double focalX;
  final double focalY;
  final double zoom;
  // Sous quel onglet de l'accueil (Femme / Homme) cette catégorie
  // apparaît — 'women', 'men', ou '*' pour les deux (13 septembre 2026,
  // voir la doc de migration dans marketplace_schema.sql). '*' par défaut :
  // une catégorie créée avant cette date, ou dont personne n'a précisé le
  // genre, reste visible partout plutôt que de disparaître.
  final String gender;

  Category({
    required this.id,
    this.parentId,
    required this.name,
    this.imageUrl,
    this.sortOrder = 0,
    this.isVisible = true,
    this.focalX = 0.5,
    this.focalY = 0.5,
    this.zoom = 1.0,
    this.gender = '*',
  });

  factory Category.fromMap(Map<String, dynamic> map) => Category(
        id: map['id'] as String,
        parentId: map['parent_id'] as String?,
        name: map['name'] as String,
        imageUrl: map['image_url'] as String?,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        isVisible: (map['is_visible'] as bool?) ?? true,
        focalX: (map['focal_x'] as num?)?.toDouble() ?? 0.5,
        focalY: (map['focal_y'] as num?)?.toDouble() ?? 0.5,
        zoom: (map['zoom'] as num?)?.toDouble() ?? 1.0,
        gender: (map['gender'] as String?) ?? '*',
      );
}

class Product {
  final String id;
  final String shopId;
  final String? categoryId;
  final String name;
  final String? description;
  final double price;
  final double? compareAtPrice; // prix barré optionnel — façon Farfetch (3 sept. 2026)
  final int stock;
  final bool isVisible;
  final List<String> imageUrls;
  final String? shopName;
  final String? shopLogoUrl;
  // Ajouté le 5 septembre 2026 — badge "NOUVEAU" sur la fiche produit (capture
  // Aquazzura d'Emina, badge "NEW"). La colonne existait déjà en base
  // (`created_at`), simplement jamais lue côté modèle jusqu'ici.
  final DateTime? createdAt;
  // Marque du produit — ajoutée le 5 septembre 2026 (nuit), retour d'Emina :
  // jusque-là le nom de la boutique servait de "marque" sur les cartes
  // produit (aucun champ dédié). Optionnel : si non renseigné, l'affichage
  // retombe sur le nom de la boutique (voir widgets.dart/product_screen.dart)
  // pour ne rien casser sur les produits déjà créés.
  final String? brand;
  // Options — "regarde la photo 5 [...] pour makeup les couleurs disponibles
  // comme exemple" (5 septembre 2026) : équivalent l'app des tailles/couleurs
  // d'Aquazzura. Pas de champ "taille" ou "couleur" séparé ni de liste figée
  // de catégories : [optionName] est le libellé libre choisi par la
  // vendeuse ("Taille", "Couleur", ...) et [optionValues] la liste des choix
  // qu'elle propose — s'adapte donc à n'importe quelle catégorie (chaussures,
  // maquillage, ou autre) sans rien coder en dur.
  final String? optionName;
  final List<String> optionValues;
  // Ajoutés le 6 septembre 2026 (captures "Concealer Color" / "Lipliner
  // color" envoyées par Emina). [optionType] vaut 'color' ou 'text' :
  //  - 'color' : la cliente voit de vrais carrés de couleur, et
  //    [optionColors] donne la teinte de chaque choix en hexadécimal
  //    (#C0392B), dans le MÊME ordre que [optionValues] ;
  //  - 'text'  : des puces de texte, comme avant (38, 39, 40...).
  // [optionSoldOut] marque les choix épuisés — le trait en diagonale des
  // captures : la teinte reste visible mais ne peut pas être commandée.
  final String optionType;
  final List<String> optionColors;
  final List<bool> optionSoldOut;
  // Point de la photo qui doit TOUJOURS rester visible, quel que soit le
  // format de carte qui l'affiche — grille, liste, galerie de la fiche
  // produit (5 septembre 2026, nuit, 2e retour sur les photos : "le vendeur
  // il peut contrôler la photo, ce que le vendeur il veut apparaître",
  // illustré par un exemple de recadrage/positionnement de photo de profil).
  // Un recadrage figé une fois pour toutes serait correct pour UN SEUL de
  // ces formats et pourrait couper le sujet dans les autres (les cartes de
  // l'app n'ont pas toutes le même format) — à la place, la vendeuse choisit
  // un point de référence (fraction 0 à 1 de la largeur/hauteur de la
  // photo, glissé sur `PhotoPositionScreen`, voir widgets.dart),
  // utilisé comme centre du recadrage automatique partout où la photo
  // apparaît. Parallèle à [imageUrls] (même index = même photo). Pas de
  // type `Alignment` ici pour garder ce fichier sans dépendance Flutter —
  // la conversion se fait à l'affichage (voir `focalXAt`/`focalYAt`).
  final List<double> imageFocalX;
  final List<double> imageFocalY;
  // Zoom par photo (5 septembre 2026 — Emina : "ça reste un problème que je
  // ne peux pas zoomer ni dezoomer, [...] la point la plus importante pour
  // moi") : 1.0 = pas de zoom, jusqu'à 3.0 = zoomé x3. S'applique EN PLUS
  // du recadrage automatique de chaque carte (même principe que
  // `imageFocalX`/`imageFocalY` ci-dessus : un multiplicateur, pas des
  // pixels figés, reste donc cohérent quel que soit le format de la carte).
  final List<double> imageZoom;

  Product({
    required this.id,
    required this.shopId,
    this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.compareAtPrice,
    this.stock = 0,
    this.isVisible = true,
    this.imageUrls = const [],
    this.shopName,
    this.shopLogoUrl,
    this.createdAt,
    this.optionName,
    this.optionValues = const [],
    this.optionType = 'text',
    this.optionColors = const [],
    this.optionSoldOut = const [],
    this.brand,
    this.imageFocalX = const [],
    this.imageFocalY = const [],
    this.imageZoom = const [],
  });

  String? get coverImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  /// Fraction (0 à 1) du point à garder visible sur la photo d'index
  /// [index] — 0.5/0.5 (centre) par défaut si non renseigné.
  double focalXAt(int index) => (index >= 0 && index < imageFocalX.length) ? imageFocalX[index] : 0.5;
  double focalYAt(int index) => (index >= 0 && index < imageFocalY.length) ? imageFocalY[index] : 0.5;
  double zoomAt(int index) => (index >= 0 && index < imageZoom.length) ? imageZoom[index] : 1.0;

  /// Ligne "marque" affichée sur les cartes/fiche produit — la marque si la
  /// vendeuse l'a renseignée, sinon le nom de la boutique (5 septembre 2026).
  String get brandLine => (brand != null && brand!.trim().isNotEmpty) ? brand! : (shopName ?? '');

  /// Vrai si un prix barré est renseigné ET supérieur au prix actuel —
  /// affiche alors le prix barré + la réduction (façon Farfetch).
  bool get isOnSale => compareAtPrice != null && compareAtPrice! > price;

  /// Pourcentage de réduction arrondi, ex: 20 pour "-20%".
  int get discountPercent =>
      isOnSale ? (((compareAtPrice! - price) / compareAtPrice!) * 100).round() : 0;

  /// Ajouté il y a 14 jours ou moins — badge "NOUVEAU" de la fiche produit.
  bool get isNew => createdAt != null && DateTime.now().difference(createdAt!).inDays <= 14;

  /// Vrai si la vendeuse a renseigné des options (taille, couleur, ...) —
  /// la fiche produit exige alors un choix avant l'ajout au panier.
  /// Le produit a-t-il des variantes réellement choisissables ?
  ///
  /// **Durci le 10 septembre 2026** : en mode couleur, il faut aussi que
  /// les teintes soient là. Un produit enregistré avec un nom d'option mais
  /// une liste de choix vide (ce qui arrivait quand la vendeuse ajoutait
  /// une teinte sans la nommer) bloquait l'ajout au panier : l'application
  /// exigeait un choix, mais n'affichait rien à choisir.
  bool get hasOptions {
    final named = optionName != null && optionName!.trim().isNotEmpty;
    if (!named) return false;
    if (optionType == 'color') return optionColors.isNotEmpty;
    return optionValues.isNotEmpty;
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final imagesRaw = map['product_images'] as List<dynamic>?;
    // Triées par `sort_order` avant d'en extraire les URL (5 septembre
    // 2026, nuit) : la colonne existait déjà mais n'était jusqu'ici jamais
    // utilisée pour ordonner l'embedded `product_images` — la "photo de
    // couverture" (imageUrls.first) dépendait donc de l'ordre arbitraire
    // renvoyé par la base, pas d'un choix de la vendeuse. Voir
    // vendor_service.dart (`reorderMyProductImages`) pour comment la
    // vendeuse choisit maintenant cet ordre.
    final sortedImages = (imagesRaw ?? []).map((e) => e as Map<String, dynamic>).toList()
      ..sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0));
    final images = sortedImages.map((e) => e['url'] as String).toList();
    final focalXs = sortedImages.map((e) => (e['focal_x'] as num?)?.toDouble() ?? 0.5).toList();
    final focalYs = sortedImages.map((e) => (e['focal_y'] as num?)?.toDouble() ?? 0.5).toList();
    final zooms = sortedImages.map((e) => (e['zoom'] as num?)?.toDouble() ?? 1.0).toList();
    final shop = map['shops'] as Map<String, dynamic>?;
    final compareAt = map['compare_at_price'];
    final optionValuesRaw = map['option_values'] as List<dynamic>?;
    return Product(
      id: map['id'] as String,
      shopId: map['shop_id'] as String,
      categoryId: map['category_id'] as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      compareAtPrice: compareAt == null ? null : (compareAt as num).toDouble(),
      stock: (map['stock'] as int?) ?? 0,
      isVisible: (map['is_visible'] as bool?) ?? true,
      imageUrls: images,
      imageFocalX: focalXs,
      imageFocalY: focalYs,
      imageZoom: zooms,
      shopName: shop != null ? shop['name'] as String? : null,
      shopLogoUrl: shop != null ? shop['logo_url'] as String? : null,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      optionName: map['option_name'] as String?,
      optionValues: (optionValuesRaw ?? []).map((e) => e as String).toList(),
      optionType: (map['option_type'] as String?) ?? 'text',
      optionColors: ((map['option_colors'] as List<dynamic>?) ?? []).map((e) => e as String).toList(),
      optionSoldOut: ((map['option_sold_out'] as List<dynamic>?) ?? []).map((e) => e == true).toList(),
      brand: map['brand'] as String?,
    );
  }
}

/// Une photo produit avec son identifiant — utilisé uniquement par l'écran
/// de gestion des photos côté vendeuse (my_shop_screen.dart, 5 septembre
/// 2026) : partout ailleurs dans l'app, `Product.imageUrls` (simple liste
/// d'URL) suffit et reste inchangé pour ne rien casser.
class ProductImage {
  final String id;
  final String url;
  final int sortOrder;
  // Voir la doc de `Product.imageFocalX`/`imageFocalY` — même mécanisme,
  // pour la photo individuelle gérée par cet écran (5 septembre 2026, nuit).
  final double focalX;
  final double focalY;
  // Voir la doc de `Product.imageZoom` — même mécanisme (5 septembre 2026).
  final double zoom;

  ProductImage({
    required this.id,
    required this.url,
    this.sortOrder = 0,
    this.focalX = 0.5,
    this.focalY = 0.5,
    this.zoom = 1.0,
  });

  factory ProductImage.fromMap(Map<String, dynamic> map) => ProductImage(
        id: map['id'] as String,
        url: map['url'] as String,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        focalX: (map['focal_x'] as num?)?.toDouble() ?? 0.5,
        focalY: (map['focal_y'] as num?)?.toDouble() ?? 0.5,
        zoom: (map['zoom'] as num?)?.toDouble() ?? 1.0,
      );
}

/// Collection thématique de l'accueil — bannière + produits sélectionnés en
/// dessous, gérée par l'admin (5 septembre 2026, demande explicite d'Emina,
/// capture "Hermès for Less" : une bannière secondaire suivie d'une
/// sélection de produits, à la place de l'ancienne rangée de produits sans
/// titre juste sous la bannière principale). [categoryId] `null` = tous les
/// produits mélangés ; renseigné = seulement ceux de cette catégorie.
/// [productLimit] : nombre de produits que l'admin veut afficher en dessous.
class HomeCollection {
  final String id;
  final String imageUrl;
  final String title;
  final String? subtitle;
  final String? categoryId;
  final String? categoryName; // rempli uniquement côté admin (jointure)
  final int productLimit;
  final int sortOrder;
  final bool isVisible;

  HomeCollection({
    required this.id,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.categoryId,
    this.categoryName,
    this.productLimit = 8,
    this.sortOrder = 0,
    this.isVisible = true,
  });

  factory HomeCollection.fromMap(Map<String, dynamic> map) {
    final category = map['categories'] as Map<String, dynamic>?;
    return HomeCollection(
      id: map['id'] as String,
      imageUrl: map['image_url'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String?,
      categoryId: map['category_id'] as String?,
      categoryName: category != null ? category['name'] as String? : null,
      productLimit: (map['product_limit'] as int?) ?? 8,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isVisible: (map['is_visible'] as bool?) ?? true,
    );
  }
}

class CartLine {
  final Product product;
  int quantity;
  // Option choisie (taille, couleur, ...) — ajouté le 5 septembre 2026, voir
  // [Product.optionName]. `null` pour un produit sans options.
  final String? selectedOption;

  CartLine({required this.product, this.quantity = 1, this.selectedOption});

  double get subtotal => product.price * quantity;

  /// Identifiant unique dans le panier — un même produit avec DEUX options
  /// différentes (ex: taille 38 et taille 40) forme deux lignes séparées.
  String get cartKey => selectedOption == null ? product.id : '${product.id}::$selectedOption';
}

class OrderModel {
  final String id;
  final String shopId;
  final String status;
  final double total;
  final DateTime createdAt;
  final String? shopName;
  // Copiés depuis le profil du client au moment de la commande (le vendeur
  // n'a jamais accès à `profiles`, voir marketplace_schema.sql) — utilisés
  // par les écrans "Commandes" admin et vendeur (4 septembre 2026).
  final String clientFullName;
  final String clientPhone;
  final String? clientCity;
  final String? clientAddress;
  final String? paymentProofUrl;
  // Ajoutés le 6 septembre 2026 — la capture de paiement est remplacée par
  // la RÉFÉRENCE de transaction renvoyée par la banque mobile (unique en
  // base : la même ne peut pas servir deux fois), et la cliente joint la
  // position GPS de sa livraison.
  final String? paymentReference;
  // Couche fintech (20 septembre 2026, voir supabase/fintech_patch.sql).
  // `status` décrit l'avancement de la COMMANDE (préparation, livraison)
  // et l'espace Livreur s'appuie dessus — le paiement a donc ses propres
  // colonnes plutôt qu'une énumération `status` élargie.
  //
  // Il n'y a pas d'état « en attente de paiement » : sans référence,
  // `OrderService.checkout` ne crée aucune commande. Une commande naît
  // donc toujours en `submitted`, et la vendeuse confirme quand elle
  // retrouve la référence dans son application bancaire.
  final String paymentStatus;
  // Recopié depuis la boutique au moment de la commande, comme
  // `clientFullName` : la vendeuse peut changer de banque plus tard, la
  // commande doit garder le service par lequel elle a été payée.
  final String? paymentProvider;
  final DateTime? paymentVerifiedAt;
  // Montant réellement reçu, relevé par la vendeuse dans son application
  // bancaire (21 septembre 2026, voir
  // `supabase/payment_amount_patch.sql`). Sert à signaler un écart entre
  // ce qui a été payé et ce qui était dû — le seul point que la référence
  // unique et le recalcul des totaux ne couvraient pas.
  final double? paymentAmountReceived;
  final double? deliveryLat;
  final double? deliveryLng;
  // Mode de récupération choisi par la cliente au moment de commander
  // (6 septembre 2026) : 'delivery' (la boutique lui livre) ou 'pickup'
  // (elle passe la chercher). La boutique organise elle-même sa livraison,
  // comme depuis le début du projet.
  final String deliveryMode;

  OrderModel({
    required this.id,
    required this.shopId,
    required this.status,
    required this.total,
    required this.createdAt,
    this.shopName,
    this.clientFullName = '',
    this.clientPhone = '',
    this.clientCity,
    this.clientAddress,
    this.paymentProofUrl,
    this.paymentReference,
    this.paymentStatus = 'submitted',
    this.paymentProvider,
    this.paymentVerifiedAt,
    this.paymentAmountReceived,
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryMode = 'pickup',
  });

  bool get isDelivery => deliveryMode == 'delivery';

  bool get isPaymentVerified => paymentStatus == 'verified';

  /// Écart entre le montant reçu et le total dû. `null` tant que la
  /// vendeuse n'a rien relevé.
  double? get paymentGap =>
      paymentAmountReceived == null ? null : paymentAmountReceived! - total;

  /// Un écart d'un ouguiya ou moins est du bruit d'arrondi, pas une
  /// anomalie : on ne va pas alerter une vendeuse pour ça.
  bool get hasPaymentGap {
    final gap = paymentGap;
    return gap != null && gap.abs() > 1;
  }
  bool get isPaymentRejected => paymentStatus == 'rejected';

  /// Libellé honnête : tant que la vendeuse n'a pas retrouvé la référence
  /// dans son historique bancaire, on dit « soumise », pas « vérifiée ».
  /// Le roadmap insiste là-dessus et le jury aussi : ne jamais afficher
  /// « paiement vérifié » quand rien ne l'a vérifié.
  String get paymentLabel => switch (paymentStatus) {
        'verified' => 'Paiement confirmé',
        'rejected' => 'Référence introuvable',
        _ => 'Référence soumise — en attente de vérification',
      };

  /// Lien à ouvrir pour voir la livraison sur une carte. Passe par une URL
  /// Google Maps standard plutôt que par l'API Google Maps : aucune clé,
  /// aucun compte de facturation, et ça marche depuis n'importe quel
  /// téléphone comme depuis un navigateur.
  String? get deliveryMapUrl => deliveryLat == null || deliveryLng == null
      ? null
      : 'https://www.google.com/maps/search/?api=1&query=$deliveryLat,$deliveryLng';

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    final shop = map['shops'] as Map<String, dynamic>?;
    return OrderModel(
      id: map['id'] as String,
      shopId: map['shop_id'] as String,
      status: map['status'] as String,
      total: (map['total'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      shopName: shop != null ? shop['name'] as String? : null,
      clientFullName: (map['client_full_name'] as String?) ?? '',
      clientPhone: (map['client_phone'] as String?) ?? '',
      clientCity: map['client_city'] as String?,
      clientAddress: map['client_address'] as String?,
      paymentProofUrl: map['payment_proof_url'] as String?,
      paymentReference: map['payment_reference'] as String?,
      // Valeur de repli si `fintech_patch.sql` n'a pas encore été joué sur
      // cette base : l'app continue de fonctionner, tout est « soumis ».
      paymentStatus: (map['payment_status'] as String?) ?? 'submitted',
      paymentProvider: map['payment_provider'] as String?,
      paymentAmountReceived: (map['payment_amount_received'] as num?)?.toDouble(),
      paymentVerifiedAt: map['payment_verified_at'] != null
          ? DateTime.tryParse(map['payment_verified_at'] as String)
          : null,
      deliveryLat: (map['delivery_lat'] as num?)?.toDouble(),
      deliveryLng: (map['delivery_lng'] as num?)?.toDouble(),
      deliveryMode: (map['delivery_mode'] as String?) ?? 'pickup',
    );
  }
}

/// Une ligne de commande — nom/prix/quantité recopiés au moment de l'achat
/// (voir `order_items` dans marketplace_schema.sql), pas relus depuis le
/// produit : une commande passée reste juste même si le produit change ou
/// est supprimé ensuite.
class OrderItemModel {
  final String id;
  final String? productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  final double subtotal;

  OrderItemModel({
    required this.id,
    this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
  });

  factory OrderItemModel.fromMap(Map<String, dynamic> map) => OrderItemModel(
        id: map['id'] as String,
        productId: map['product_id'] as String?,
        productName: map['product_name'] as String,
        unitPrice: (map['unit_price'] as num).toDouble(),
        quantity: map['quantity'] as int,
        subtotal: (map['subtotal'] as num).toDouble(),
      );
}

class VendorApplication {
  final String id;
  final String applicantId;
  final String shopName;
  final String? description;
  final String phone;
  final String? city;
  final String status; // pending | approved | rejected
  final DateTime createdAt;
  final String? applicantName;
  final String? applicantEmail;

  VendorApplication({
    required this.id,
    required this.applicantId,
    required this.shopName,
    this.description,
    required this.phone,
    this.city,
    this.status = 'pending',
    required this.createdAt,
    this.applicantName,
    this.applicantEmail,
  });

  factory VendorApplication.fromMap(Map<String, dynamic> map) {
    final applicant = map['profiles'] as Map<String, dynamic>?;
    return VendorApplication(
      id: map['id'] as String,
      applicantId: map['applicant_id'] as String,
      shopName: map['shop_name'] as String,
      description: map['description'] as String?,
      phone: map['phone'] as String,
      city: map['city'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      createdAt: DateTime.parse(map['created_at'] as String),
      applicantName: applicant != null ? applicant['full_name'] as String? : null,
      applicantEmail: applicant != null ? applicant['email'] as String? : null,
    );
  }
}

/// Photo de la bannière — gérée par l'admin depuis le 2 septembre 2026
/// (jusqu'à 5, `sort_order` fixe l'ordre du défilement automatique).
/// [categoryId] ajouté le 4 septembre 2026 (nuit) : `null` = bannière de
/// l'accueil (comme avant) ; renseigné = bannière qui n'apparaît qu'en haut
/// de CETTE catégorie sur l'écran "Tous les produits" (demande d'Emina,
/// captures Aquazzura "pour seulement les chaussures") — chaque emplacement
/// (accueil, ou une catégorie donnée) a son propre plafond de 5 photos.
/// [categoryName] n'est renseigné que côté admin (jointure `categories`,
/// pour afficher le nom plutôt que l'identifiant technique).
class HomeBanner {
  final String id;
  final String imageUrl;
  final int sortOrder;
  final bool isVisible;
  final String? categoryId;
  final String? categoryName;

  HomeBanner({
    required this.id,
    required this.imageUrl,
    this.sortOrder = 0,
    this.isVisible = true,
    this.categoryId,
    this.categoryName,
  });

  bool get isHomeBanner => categoryId == null;

  factory HomeBanner.fromMap(Map<String, dynamic> map) {
    final category = map['categories'] as Map<String, dynamic>?;
    return HomeBanner(
      id: map['id'] as String,
      imageUrl: map['image_url'] as String,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isVisible: (map['is_visible'] as bool?) ?? true,
      categoryId: map['category_id'] as String?,
      categoryName: category != null ? category['name'] as String? : null,
    );
  }
}

class Review {
  final String id;
  final String productId;
  final String clientId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String? authorName;

  Review({
    required this.id,
    required this.productId,
    required this.clientId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.authorName,
  });

  factory Review.fromMap(Map<String, dynamic> map) {
    // `review_authors` depuis le 9 septembre 2026 : une vue qui n'expose
    // que l'identifiant et le nom, lisible par un visiteur non connecté.
    // La table `profiles`, elle, reste fermée. `profiles` est encore lu ici
    // au cas où une requête plus ancienne la joindrait.
    final author = (map['review_authors'] ?? map['profiles']) as Map<String, dynamic>?;
    return Review(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      clientId: map['client_id'] as String,
      rating: map['rating'] as int,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      authorName: author != null ? author['full_name'] as String? : null,
    );
  }
}

/// Une notification — écrite par la BASE elle-même (déclencheurs de
/// `supabase/paiement_options_patch.sql`), jamais par l'application :
/// personne ne peut donc s'en envoyer de fausses, ni en écrire à
/// quelqu'un d'autre. Chacun ne lit que les siennes.
///
/// Ajouté le 6 septembre 2026 : jusque-là, une vendeuse ne savait qu'elle
/// avait vendu que si elle pensait à ouvrir "Ma boutique".
class AppNotification {
  final String id;
  final String kind;
  final String title;
  final String? body;
  final String? orderId;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.orderId,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        kind: (map['kind'] as String?) ?? '',
        title: (map['title'] as String?) ?? '',
        body: map['body'] as String?,
        orderId: map['order_id'] as String?,
        isRead: (map['is_read'] as bool?) ?? false,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

/// Profil "livreur" (espace Livreur, 15 septembre 2026) — l'existence d'une
/// ligne dans `driver_profiles` suffit à dire "ce compte livre aussi",
/// exactement comme une ligne dans `shops` dit "ce compte vend aussi" (voir
/// `RoleController`). `isAvailable` pilote si le compte apparaît comme
/// destinataire des nouvelles courses.
class DriverProfile {
  final String id;
  final String? vehicleType;
  final bool isAvailable;
  // 'pending' | 'approved' | 'rejected' — ajouté le 15 septembre 2026
  // (demande explicite : un livreur ne reçoit des courses qu'une fois
  // approuvé par l'administrateur). Par défaut 'pending' côté base tant
  // que ce patch n'a pas été exécuté sur un projet existant, une ligne
  // sans cette colonne serait lue comme "pending" — jamais "approved" par
  // erreur.
  final String status;

  DriverProfile({required this.id, this.vehicleType, this.isAvailable = false, this.status = 'pending'});

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  factory DriverProfile.fromMap(Map<String, dynamic> map) => DriverProfile(
        id: map['id'] as String,
        vehicleType: map['vehicle_type'] as String?,
        isAvailable: (map['is_available'] as bool?) ?? false,
        status: (map['status'] as String?) ?? 'pending',
      );
}

/// Une course à livrer (espace Livreur, 15 septembre 2026) — voir
/// `supabase/livreur_patch.sql` pour le schéma complet et les raisons de
/// sécurité derrière chaque choix. Volontairement dépourvu de toute
/// information personnelle sur la cliente (nom, téléphone, adresse
/// précise) : tant qu'une course est seulement proposée, seuls le point de
/// collecte (la boutique), un point sur la carte pour la livraison et la
/// distance sont connus. Le nom/téléphone/adresse ne sont obtenus qu'après
/// acceptation, via `DeliveryService.fetchContact` (RPC dédiée).
class DeliveryRequest {
  final String id;
  final String orderId;
  final String shopId;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final double? distanceKm;
  final String status; // pending | accepted | delivered | cancelled
  final String? driverId;
  final DateTime createdAt;
  // Renseignés côté app par une jointure (`shops(name, city)`), pas par la
  // base elle-même — voir `DeliveryService.fetchOpenBoard`.
  final String? shopName;
  final String? shopCity;
  final double? orderTotal;

  DeliveryRequest({
    required this.id,
    required this.orderId,
    required this.shopId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.distanceKm,
    this.status = 'pending',
    this.driverId,
    required this.createdAt,
    this.shopName,
    this.shopCity,
    this.orderTotal,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDelivered => status == 'delivered';

  factory DeliveryRequest.fromMap(Map<String, dynamic> map) => DeliveryRequest(
        id: map['id'] as String,
        orderId: map['order_id'] as String,
        shopId: map['shop_id'] as String,
        pickupLat: (map['pickup_lat'] as num?)?.toDouble(),
        pickupLng: (map['pickup_lng'] as num?)?.toDouble(),
        dropoffLat: (map['dropoff_lat'] as num?)?.toDouble(),
        dropoffLng: (map['dropoff_lng'] as num?)?.toDouble(),
        distanceKm: (map['distance_km'] as num?)?.toDouble(),
        status: (map['status'] as String?) ?? 'pending',
        driverId: map['driver_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        shopName: (map['shops'] is Map) ? (map['shops']['name'] as String?) : null,
        shopCity: (map['shops'] is Map) ? (map['shops']['city'] as String?) : null,
        orderTotal: (map['orders'] is Map) ? ((map['orders']['total'] as num?)?.toDouble()) : null,
      );
}

/// Contact de la cliente, révélé uniquement après acceptation d'une course
/// (voir `DeliveryService.fetchContact`, appelle la RPC
/// `get_delivery_contact`).
class DeliveryContact {
  final String fullName;
  final String phone;
  final String? address;
  final String? city;

  DeliveryContact({required this.fullName, required this.phone, this.address, this.city});

  factory DeliveryContact.fromMap(Map<String, dynamic> map) => DeliveryContact(
        fullName: (map['client_full_name'] as String?) ?? '',
        phone: (map['client_phone'] as String?) ?? '',
        address: map['client_address'] as String?,
        city: map['client_city'] as String?,
      );
}
