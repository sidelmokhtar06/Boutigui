import 'package:flutter/material.dart';

/// Palette et thème "l'app" — thème CLAIR (3 septembre 2026, demande
/// d'Emina : elle a trouvé le thème blanc plus moderne, en s'inspirant de
/// l'app "Level"). Remplace le thème sombre utilisé jusqu'ici pour
/// l'application cliente.
///
/// Le site admin (lib/admin/**, admin_main.dart) reste inchangé, en sombre
/// — il utilise désormais [AdminTheme] (copie exacte de l'ancien [AppTheme]
/// sombre) plutôt que cette classe, pour ne pas être affecté par ce
/// changement.
///
/// Couleurs, typographies et rayons sont exposés comme des constantes
/// nommées ([AppTheme.pink], [AppTheme.bg], [AppTheme.radiusCard], ...) pour
/// être réutilisés directement dans les écrans sans repasser par le thème
/// Material — utile pour coller précisément aux maquettes.
class AppTheme {
  AppTheme._();

  // Couleurs de marque — thème clair.
  static const Color bg = Color(0xFFFFFFFF); // fond des écrans (blanc, comme Level)
  static const Color panel = Color(0xFFF6F3F4); // panneaux/bandes légèrement teintés
  static const Color card = Color(0xFFFFFFFF); // cartes (même ton que le fond, séparées par une bordure)
  static const Color line = Color(0xFFE8E2E3); // bordures / séparateurs
  // Fond de l'écran d'ouverture — 22 septembre 2026. Le nouveau logo « b »
  // est blanc et gris : posé sur le blanc des écrans, il disparaîtrait.
  // Cette valeur reprend le fond sur lequel la marque a été dessinée, pour
  // que le splash montre le logo tel qu'il a été conçu ; le voile fond
  // ensuite vers le blanc de l'application (voir splash_screen.dart).
  static const Color splashDark = Color(0xFF1A1A1A);
  static const Color hair = Color(0xFFE8E2E3); // alias conservé pour compat (ancien nom "hemy")
  // Rose retiré entièrement de l'application le 15 septembre 2026 (demande
  // explicite : "regardez la couleur rose ... supprimez-la complètement").
  // Les deux constantes restent définies (pour ne rien casser dans le code
  // qui les référence encore) mais ne pointent plus vers du rose : elles
  // reprennent maintenant `ink`/`panel`, donc tout ce qui utilisait `pink`
  // comme accent (segments sélectionnés, chips) devient neutre noir/gris.
  static const Color pink = Color(0xFF2B2B2B); // ex-rose — neutre (= ink)
  static const Color pinkDeep = Color(0xFFFFFFFF); // ex-texte sur rose — neutre (= blanc, lisible sur ink)
  static const Color mauve = Color(0xFFC9A2B0); // inchangé
  static const Color copper = Color(0xFFD2793F); // inchangé
  // "ink" est repris de l'ancien fond sombre (var(--black), 0xFF2B2B2B) :
  // c'est déjà le "noir" de la marque l'app, réutilisé comme texte principal
  // et comme couleur des boutons pleins une fois le thème inversé.
  static const Color ink = Color(0xFF2B2B2B); // texte principal (sombre)
  static const Color ink2 = Color(0xFF5C5658); // texte secondaire
  static const Color muted = Color(0xFF8C8386); // texte discret / icônes inactives — inchangé, gris neutre
  static const Color mutedDark = Color(0xFFB6AFB0); // icônes d'onglet inactif (plus clair pour rester lisible sur fond clair)
  // Champ de recherche de l'accueil (.search dans la maquette de référence) —
  // fond et séparateur légèrement différents du reste des champs de l'app.
  static const Color searchFill = Color(0xFFF2EEEF);
  static const Color searchSep = Color(0xFFE7E2E3);
  static const Color searchPlaceholder = Color(0xFF9C9496);
  // Puces de pagination des photos produit (.pager dans la maquette de référence).
  static const Color pagerOff = Color(0xFFE3DEDF);
  static const Color pagerOn = Color(0xFFC4682F);
  static const Color whatsapp = Color(0xFF25D366);
  static const Color amber = Color(0xFFF5A623);
  static const Color stockWarn = Color(0xFFE0A34D);
  static const Color verifiedBlue = Color(0xFF6FB4F0);
  static const Color imageBg = Color(0xFFFFFFFF); // les photos produit restent sur fond blanc, comme sur la maquette
  static const Color red = Color(0xFFE0473E);
  static const Color redPress = Color(0xFFC53D35);
  static const Color redTint = Color(0xFFFBEAE8); // teinte claire (icône rouge sur fond clair, plus le maroon foncé d'avant)

  // ---------------------------------------------------------------- Catégories
  //
  // Valeurs relevées AU PIXEL sur la capture de référence renvoyée par
  // Emina le 5 septembre 2026 ("les catégories doivent être de cette
  // manière, le même font de l'écriture le même size") — mesurées sur
  // l'image elle-même, pas estimées à l'oeil :
  //  - fond de la bande : #EAEAEA (mesuré exactement)
  //  - barre de séparation entre deux bandes : ~17 pt de haut, noire sur
  //    la capture — mais Emina a demandé le 5 septembre 2026 de la passer
  //    en BLANC et de la raccourcir ("diminue un peu la longueur du partie
  //    noir [...] et changer la couleur noir vers blanc"). Sur le fond
  //    blanc de l'app, elle devient donc un simple espace entre deux
  //    bandes.
  //  - texte : ~#232323, donc [ink] convient tel quel
  static const Color categoryBand = Color(0xFFEAEAEA);
  // Emina, 6 septembre 2026 : "les lignes blanches dans la zone des
  // catégories, remplace-les par la couleur du champ de texte". Donc le
  // même gris que le champ de recherche de cet écran, plutôt que le fond
  // de page — sur des photos de catégorie à fond blanc, une séparation
  // blanche ne se voyait pas.
  // Corrigé le 15 septembre 2026 (troisième passage) : mesure précise sur
  // la vraie capture de référence — 36 px à l'écran, soit 12 pt en
  // logique Flutter — ce n'est PAS une ligne colorée du tout, juste un
  // espace blanc (la couleur de fond des écrans, `bg`) entre les bandes.
  static const Color categorySeparator = bg;
  // Mesuré précisément sur la capture de référence — 15 septembre 2026 :
  // 36 px à l'écran = 12 pt en logique Flutter (voir `categorySeparator`
  // ci-dessus, maintenant blanc plutôt que coloré).
  static const double categorySeparatorHeight = 12;

  // En-tête de l'onglet Catégories — valeurs mesurées sur la capture de
  // référence envoyée par Emina le 5 septembre 2026 ("exactement la photo
  // 2, même couleur"), sur un écran de 1178 px de large (= 393 pt) :
  //  - champ de recherche : fond #F6F6F4 (gris NEUTRE, alors que le champ
  //    de l'accueil est légèrement rosé — c'était la différence de
  //    couleur), hauteur 44 pt, coins arrondis d'environ 12
  //  - loupe et texte gris : ~#A8A6A7
  //  - titre et texte du champ : corps 17 (hauteur des capitales mesurée
  //    à 37 px, soit 12,3 pt), titre en demi-gras — exactement la barre de
  //    titre standard d'iOS, ce qui explique une taille bien plus petite
  //    que les 26 utilisés jusqu'ici
  static const Color searchFillNeutral = Color(0xFFF6F6F4);
  static const Color searchGrey = Color(0xFFA8A6A7);
  // Fond de page et couleur du titre de la capture, relevés au pixel
  // (Emina, 5 septembre 2026 : "photo 1 doit être copié collé, le même
  // couleur à 100 %") : blanc très légèrement chaud #FFFFFB, titre
  // presque noir #0E0E0C — donc PAS le [ink] gris foncé du reste de
  // l'app. Le séparateur entre deux bandes reprend le fond de page, pour
  // qu'il reste invisible.
  static const Color shopPageBg = Color(0xFFFFFFFB);
  static const Color shopTitle = Color(0xFF0E0E0C);

  // ---------------------------------------------------------------- Vert
  //
  // Palette verte de marque — 20 septembre 2026, d'après la maquette
  // fournie. Ajoutée À CÔTÉ des tons neutres existants, pas à leur place :
  // le reste de l'application (fiche produit, panier, espace vendeuse)
  // continue de s'appuyer sur `ink` / `panel` / `copper` et n'est pas
  // touché. Le vert habille l'accueil et les actions principales.
  //
  // `greenDeep` sert de fond aux surfaces pleines (boutons, carte promo
  // sombre) ; `green` aux textes et icônes d'accent sur fond clair — les
  // deux sont assez foncés pour rester lisibles sur blanc.
  static const Color green = Color(0xFF15803D);
  static const Color greenDeep = Color(0xFF14532D);
  static const Color greenTint = Color(0xFFEAF4EA);
  static const Color sage = Color(0xFFE8F0D9);
  static const Color promoPink = Color(0xFFF7CBDD);
  static const Color promoPinkInk = Color(0xFFBE185D);

  static const double radiusCard = 20;
  static const double radiusSmall = 12;
  static const double radiusPill = 20;

  /// Style de texte "mot-symbole" — utilisé pour un nom de marque affiché
  /// en grand (voir widgets.dart).
  static TextStyle brand({double size = 22, Color color = ink}) {
    return TextStyle(fontWeight: FontWeight.w600, fontSize: size, color: color, letterSpacing: 1.5);
  }

  /// Pile de polices "système Apple" — Helvetica Neue puis SF Pro Display
  /// en repli, exactement comme demandé le 15 septembre 2026 pour la fiche
  /// produit ("Givenchy → Helvetica Neue / SF Pro Display..."). Choix
  /// volontairement différent de la police par défaut de l'app (Figtree,
  /// chargée en Google Font pour tout le reste) : ni Helvetica Neue ni SF
  /// Pro Display ne sont des Google Fonts téléchargeables — ce sont des
  /// polices SYSTÈME, déjà installées sur macOS/iOS et que Safari utilise
  /// nativement, d'où le repli explicite vers `-apple-system` (le nom
  /// spécial que Safari/Chrome reconnaissent pour "la police système du
  /// moment", SF Pro sur un Mac/iPhone récent) puis Arial ailleurs.
  static TextStyle system({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = ink,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Helvetica Neue',
      fontFamilyFallback: const ['-apple-system', 'SF Pro Display', 'Arial', 'sans-serif'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }


  /// Emina, 5 septembre 2026 : "le même font de l'écriture le même size
  /// (pour mon application n'est pas le même font ni le même size est plus
  /// grand de ce qui est dans la photo)". Deux corrections, mesurées sur sa
  /// capture plutôt que devinées :
  ///
  ///  - LA POLICE. Le reste de l'app est en Inter ; les lettres de la
  ///    capture sont nettement plus géométriques (O presque rond, G à
  ///    barre horizontale sans éperon). Comparaison faite entre Inter,
  ///    Montserrat et Poppins sur le mot "CLOTHING" de la capture :
  ///    Montserrat est la plus proche, y compris en largeur totale du mot
  ///    (rapport largeur/hauteur des capitales mesuré 7.35 sur la capture,
  ///    7.47 en Montserrat, 6.93 en Inter).
  ///  - LA TAILLE. Hauteur des capitales sur la capture : 22,5 px pour une
  ///    largeur d'écran de 728 px, soit 3,09 % de la largeur de l'écran →
  ///    environ 12 pt sur un téléphone de 393 pt de large → corps 17
  ///    (Montserrat : capitales = 0,70 em). L'app était à 18 en Inter, dans
  ///    une bande deux fois plus courte que celle de la capture, ce qui la
  ///    faisait paraître bien plus grosse encore — d'où la remarque.
  ///
  /// Ramené de 17 à 15,5 puis à 14 le 5 septembre 2026, à sa demande
  /// ("diminue le size du nom des catégories vers 14 ou 13") : la bande
  /// est revenue au format 1920x480, donc deux fois plus courte que celle
  /// de la capture — le nom y paraît plus gros à hauteur de lettre égale.
  ///
  /// **Graisse corrigée en w800 (ExtraBold)** le même jour, après une
  /// nouvelle capture en PNG (donc nette, sans les artefacts du JPEG) :
  /// l'épaisseur des jambages y est de 9 px pour des capitales de 32 px.
  /// Montserrat w700 donne 7,1 px à la même hauteur, w800 donne 8,9 px —
  /// c'était ça, la différence de police qu'Emina voyait, pas la famille
  /// elle-même. La largeur totale du mot confirme Montserrat : rapport
  /// largeur/hauteur mesuré 7,66 sur la capture, 7,47 en Montserrat,
  /// contre 6,93 en Inter et ~7,07 en Poppins.
  ///
  /// **Remplacé le 15 septembre 2026** — tout ce qui précède essayait de
  /// deviner un poids de police système qui imite Montserrat/Hanken
  /// Grotesk. Inutile désormais : `web/index.html` charge la vraie police
  /// Hanken Grotesk via Google Fonts (CSS, pas le paquet Dart
  /// `google_fonts` — voir la note dans index.html), donc `fontFamily`
  /// pointe dessus directement. Spec fournie le 15 septembre 2026 :
  /// Hanken Grotesk, 15px, Bold (700).
  static TextStyle categoryLabel() {
    return const TextStyle(fontFamily: 'Hanken Grotesk', fontSize: 15, fontWeight: FontWeight.w700, color: ink);
  }

  /// Nom de la marque sur une carte produit ("JIMMY CHOO") — spec du 15
  /// septembre 2026 : Figtree SemiBold (600), 13px, hauteur de ligne 16px
  /// (donc `height: 16/13`), espacement 0,02em (= 0,02 × 13 = 0,26px en
  /// px absolus, ce que `letterSpacing` attend), toujours en majuscules
  /// (voir `.toUpperCase()` à l'appel).
  static const TextStyle productBrand = TextStyle(
    fontFamily: 'Figtree',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 16 / 13,
    letterSpacing: 0.26,
    color: ink,
  );

  /// Nom du produit sur une carte produit ("Faiz 100 pumps") — même spec
  /// du 15 septembre 2026 : Figtree Regular (400), 13px, hauteur de ligne
  /// 16px, pas d'espacement de lettres.
  static const TextStyle productName = TextStyle(
    fontFamily: 'Figtree',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 16 / 13,
    color: ink,
  );


  static ThemeData light() {
    final base = ThemeData.light().textTheme;
    return ThemeData(
      useMaterial3: true,
      // Police par défaut de toute l'app cliente — 15 septembre 2026,
      // demande explicite ("change le font pour qu'il soit plus
      // professionnel"). Jusqu'ici, seuls quelques textes précis (marque,
      // nom produit, libellé de catégorie) utilisaient une police chargée
      // exprès (Figtree / Hanken Grotesk, voir web/index.html) ; tout le
      // reste (des écrans entiers, dont le Panier/Bag) retombait sur la
      // police système par défaut du navigateur, plus terne. `fontFamily`
      // au niveau du thème s'applique à TOUT texte qui ne fixe pas la
      // sienne explicitement — Figtree convient mieux qu'Hanken Grotesk
      // comme police générale : elle est chargée aux graisses 400/600/700
      // (Hanken Grotesk ne l'est qu'en 600/700, donc un texte normal en
      // 400 y retomberait quand même sur la police système).
      fontFamily: 'Figtree',
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.light(
        primary: ink,
        onPrimary: Colors.white,
        secondary: pink,
        onSecondary: pinkDeep,
        // Fixés explicitement en neutre (15 septembre 2026) : sans ça,
        // Material 3 retombe sur un mauve/rose pâle par défaut pour ces
        // deux rôles (visible par ex. sur le segment sélectionné d'un
        // SegmentedButton) — exactement le rose qu'il fallait supprimer.
        secondaryContainer: panel,
        onSecondaryContainer: ink,
        surface: panel,
        onSurface: ink,
        error: red,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: ink2,
          selectedBackgroundColor: ink,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: line),
        ),
      ),
      textTheme: base.apply(bodyColor: ink, displayColor: ink),
      
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: bg,
        titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard), side: const BorderSide(color: line)),
        clipBehavior: Clip.antiAlias,
      ),
      // Bouton plein — inversé par rapport à l'ancien thème sombre (qui
      // était blanc/texte noir) : maintenant sombre (ink) / texte blanc,
      // pour garder le même contraste fort sur fond clair.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: Color(0xFFD8D2D3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: ink, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      // "selectedColor" utilise le rose de la marque plutôt que "ink" —
      // avec "ink" maintenant sombre, un texte "ink" sur fond "ink" aurait
      // été invisible ; le rose reste toujours clair, donc toujours lisible
      // avec un texte sombre par-dessus.
      // `selectedColor` volontairement CLAIR (pas `ink`) : `labelStyle`
      // ci-dessous reste toujours `ink` (texte sombre), qu'une puce soit
      // sélectionnée ou non — un fond sombre associé à un texte sombre
      // rendrait le libellé illisible dès qu'une puce est sélectionnée.
      // C'est exactement le bug remonté le 15 septembre 2026 (puce
      // "Vehicle" de l'espace Livreur devenue tout noir, texte invisible),
      // qui existait depuis le retrait du rose (`selectedColor` pointait
      // vers `pink`, devenu `ink` au retrait du rose — voir plus haut dans
      // ce fichier) : corrigé ici pour de bon, plutôt qu'au cas par cas
      // dans chaque écran qui utilise une puce Material standard.
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: line,
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: ink),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusPill)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
    );
  }
}

/// Thème du site ADMIN — copie exacte de l'ancien [AppTheme] sombre
/// (avant le passage au clair du 3 septembre 2026). Emina n'a demandé le
/// thème clair que pour l'application cliente ; le site admin garde son
/// apparence sombre habituelle, inchangée au pixel près.
class AdminTheme {
  AdminTheme._();

  static const Color bg = Color(0xFF2B2B2B);
  static const Color panel = Color(0xFF252525);
  static const Color card = Color(0xFF2B2B2B);
  static const Color line = Color(0xFF3D3D3D);
  static const Color hair = Color(0xFF3D3D3D);
  static const Color pink = Color(0xFFF8C8DC);
  static const Color pinkDeep = Color(0xFF6E2444);
  static const Color mauve = Color(0xFFC9A2B0);
  static const Color copper = Color(0xFFD2793F);
  static const Color ink = Color(0xFFFFFFFF);
  static const Color ink2 = Color(0xFFDCD5D6);
  static const Color muted = Color(0xFF8C8386);
  static const Color mutedDark = Color(0xFF7E7477);
  static const Color searchFill = Color(0xFF383838);
  static const Color searchSep = Color(0xFF3A3335);
  static const Color searchPlaceholder = Color(0xFFA39C9E);
  static const Color pagerOff = Color(0xFFD6D0D1);
  static const Color pagerOn = Color(0xFFC4682F);
  static const Color whatsapp = Color(0xFF25D366);
  static const Color amber = Color(0xFFF5A623);
  static const Color stockWarn = Color(0xFFE0A34D);
  static const Color verifiedBlue = Color(0xFF6FB4F0);
  static const Color imageBg = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFE0473E);
  static const Color redPress = Color(0xFFC53D35);
  static const Color redTint = Color(0xFF3A2523);

  static const double radiusCard = 20;
  static const double radiusSmall = 12;
  static const double radiusPill = 20;

  static TextStyle brand({double size = 22, Color color = ink}) {
    return TextStyle(fontWeight: FontWeight.w600, fontSize: size, color: color, letterSpacing: 1.5);
  }

  static ThemeData dark() {
    final base = ThemeData.dark().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: ink,
        onPrimary: Colors.black,
        secondary: pink,
        onSecondary: pinkDeep,
        surface: panel,
        onSurface: ink,
        error: red,
      ),
      textTheme: base.apply(bodyColor: ink, displayColor: ink),
      
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: bg,
        titleTextStyle: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard), side: const BorderSide(color: line)),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: Color(0xFF4A4A4A)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: ink, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: line,
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: ink),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusPill)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: ink),
    );
  }
}
