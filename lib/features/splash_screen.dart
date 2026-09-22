import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../core/theme.dart';
import 'shell.dart';

/// Écran d'ouverture animé — nouveau logo « b », 22 septembre 2026.
///
/// **Ce que raconte l'animation.** Le « b » ne se contente pas
/// d'apparaître : il SE CONSTRUIT, dans l'ordre où on le dessinerait à la
/// main. La hampe descend, la panse s'enroule autour d'elle, l'épaisseur
/// vient se glisser derrière, et les trois points montent un par un le
/// long de leur diagonale. Le mot « boutigui » se pose enfin dessous :
/// la marque se dessine, PUIS elle se nomme. Un fondu aurait pu habiller
/// n'importe quel logo ; cette séquence-là ne va qu'avec celui-ci.
///
/// **Pourquoi un fond sombre.** La marque est blanche et grise. Sur le
/// blanc des écrans elle disparaîtrait — on ouvre donc sur
/// [AppTheme.splashDark], le fond sur lequel elle a été dessinée, et le
/// voile fond ensuite vers l'application blanche.
///
/// **Pourquoi une superposition et pas un écran séparé.** [Shell] est
/// construit TOUT DE SUITE, sous le voile : ses premières requêtes
/// (catalogue, bannières, rôle du compte) partent pendant l'animation, pas
/// après. L'ouverture occupe un délai qui existait déjà.
///
/// **Les calques.** `b_stem`, `b_bowl` et `b_dot1..3` sont découpés de
/// `b_logo.jpg` sur la MÊME toile : empilés sans décalage, ils redonnent
/// la marque. C'est ce qui permet d'animer chaque partie séparément. Le
/// découpage est fait par `extract_b.py`, pas à la main — le fichier
/// fourni est un JPEG dont le damier de transparence est CUIT dans les
/// pixels, il a donc fallu retrouver la marque par seuil de luminance
/// (voir l'en-tête du script pour les mesures).
///
/// L'ÉPAISSEUR n'est pas extraite mais redessinée — voir [_BCurtain._depth].
///
/// **Repli.** Tant que ces calques ne sont pas dans le dépôt, on rejoue
/// l'ancienne ouverture (le chariot qui entre par la gauche, sur fond
/// blanc) — voir [_CartCurtain]. L'application n'est donc jamais cassée
/// par un asset manquant.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2300);
  static const _cartDuration = Duration(milliseconds: 1750);
  static const _reducedDuration = Duration(milliseconds: 700);

  late final AnimationController _c;
  bool _started = false;
  bool _reduced = false;

  /// `null` tant qu'on ne sait pas encore si les calques du « b » sont
  /// présents. La réponse arrive en un tour de boucle (simple lecture du
  /// bundle), donc personne ne voit cet état.
  bool? _hasB;

  /// Une fois le voile levé, la superposition sort complètement de l'arbre :
  /// elle ne doit plus ni peindre, ni intercepter le moindre geste.
  bool _lifted = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _duration);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _lifted = true);
    });
    _detectLayers();
  }

  /// Un seul calque suffit à trancher : le script les écrit tous ou aucun.
  Future<void> _detectLayers() async {
    bool found;
    try {
      await rootBundle.load(_BCurtain.stem);
      found = true;
    } catch (_) {
      found = false;
    }
    if (!mounted) return;
    setState(() {
      _hasB = found;
      if (!found) _c.duration = _reduced ? _reducedDuration : _cartDuration;
    });
    _maybeStart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // « Réduire les animations » du système (iOS, Android, et
    // `prefers-reduced-motion` sur le web). Pour certaines personnes un
    // mouvement qui traverse l'écran provoque un vrai malaise : on garde
    // alors le logo, on retire le déplacement, et on raccourcit.
    _reduced = MediaQuery.of(context).disableAnimations;
    _maybeStart();
  }

  /// L'animation ne démarre qu'une fois les deux inconnues levées : quel
  /// logo afficher, et à quelle vitesse. Démarrer avant ferait jouer les
  /// premières images à la mauvaise durée.
  void _maybeStart() {
    if (_started || _hasB == null || !mounted) return;
    _started = true;
    _c.duration = _reduced
        ? _reducedDuration
        : (_hasB! ? _duration : _cartDuration);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Construit immédiatement : il charge pendant que le voile est là.
        Shell(),
        if (!_lifted)
          // Rien ne doit passer au travers tant que le voile est visible.
          AbsorbPointer(
            child: _hasB == null
                // Le fond seul, le temps de savoir quel logo afficher.
                ? const ColoredBox(color: AppTheme.splashDark, child: SizedBox.expand())
                : (_hasB!
                    ? _BCurtain(controller: _c, reduced: _reduced)
                    : _CartCurtain(controller: _c, reduced: _reduced)),
          ),
      ],
    );
  }
}

/// Découpe une fraction de la toile — sert au balayage de la hampe.
class _FractionClipper extends CustomClipper<Rect> {
  final double bottom;

  const _FractionClipper(this.bottom);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, size.height * bottom);

  @override
  bool shouldReclip(_FractionClipper old) => old.bottom != bottom;
}

/// Secteur angulaire croissant autour d'un centre — sert à « enrouler » la
/// panse comme un trait qu'on trace, plutôt qu'à la faire apparaître.
class _SweepClipper extends CustomClipper<Path> {
  final Offset centre; // en fractions de la toile
  final double turns; // 0 → rien, 1 → tour complet
  final double startAngle;

  const _SweepClipper({required this.centre, required this.turns, required this.startAngle});

  @override
  Path getClip(Size size) {
    final c = Offset(centre.dx * size.width, centre.dy * size.height);
    // Rayon volontairement large : le secteur doit déborder de la panse
    // pour la découvrir entièrement, y compris son épaisseur de trait.
    final r = size.longestSide * 1.5;
    if (turns <= 0) return Path();
    return Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), startAngle, 6.283185 * turns.clamp(0.0, 1.0), false)
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper old) => old.turns != turns;
}

/// L'ouverture « le b s'assemble ».
class _BCurtain extends StatelessWidget {
  final AnimationController controller;
  final bool reduced;

  const _BCurtain({required this.controller, required this.reduced});

  static const _dir = 'assets/images/';
  static const stem = '${_dir}b_stem.png';
  static const _bowl = '${_dir}b_bowl.png';
  static const _dots = ['${_dir}b_dot1.png', '${_dir}b_dot2.png', '${_dir}b_dot3.png'];
  static const _word = '${_dir}b_word.png';

  // ---------------------------------------------------------------------
  // GÉOMÉTRIE DE LA TOILE — produite par `extract_b.py`, pas à la main.
  //
  // Ces fractions disent OÙ se trouve chaque partie dans les calques. Le
  // balayage de la hampe et l'enroulement de la panse s'en servent pour
  // savoir quoi découvrir et autour de quel point tourner. Le script les
  // imprime (« géométrie relative ») ; les recopier après tout changement
  // de logo, sinon le balayage découvre le vide.
  // ---------------------------------------------------------------------
  static const _canvasRatio = 0.6586; // largeur / hauteur de la toile
  static const _stemTop = 0.0522;
  static const _stemBottom = 0.9459;
  static const _bowlCentre = Offset(0.564, 0.671);
  // Mot « boutigui » : rapport largeur/hauteur du fichier recadré, et
  // largeur relative à celle du « b ». Le mot est repris de
  // `splash_word.png` (l'ancienne ouverture), recadré au plus juste et
  // encré en blanc pour le fond sombre — voir `assets/images/b_word.png`.
  static const _wordRatio = 2.2165;
  static const _wordScale = 1.55;

  /// L'ÉPAISSEUR du logo, redessinée plutôt qu'extraite.
  ///
  /// Dans le fichier fourni, ces couches grises sont semi-transparentes
  /// au-dessus du damier de transparence : impossible d'en récupérer un
  /// alpha propre (mesuré — elles plafonnent à 208 quand la marque est à
  /// 255, et le plus petit point culmine à 202, donc aucun seuil ne
  /// sépare les trois familles d'un coup).
  ///
  /// On les redessine donc : ce sont les MÊMES calques, décalés et
  /// translucides. Sur le fond sombre, du blanc à faible opacité donne
  /// exactement le gris voulu — pas besoin d'une couleur en dur. Et
  /// comme elles sont calculées, elles peuvent s'animer : elles sortent
  /// de derrière la marque au lieu d'être déjà là.
  ///
  /// Décalages en fraction de la largeur affichée, pour que le relief
  /// soit le même sur tous les écrans.
  static const _depth = [
    (dx: 0.040, opacity: 0.28),
    (dx: 0.026, opacity: 0.45),
    (dx: 0.012, opacity: 0.65),
  ];

  @override
  Widget build(BuildContext context) {
    // Largeur d'affichage du « b » : confortable sur un téléphone, jamais
    // démesurée sur un écran d'ordinateur.
    final width = (MediaQuery.sizeOf(context).width * 0.34).clamp(110.0, 180.0);
    final height = width / _canvasRatio;
    // Le mot est plus large que la marque — proportion reprise du logo
    // complet, où « boutigui » déborde nettement du chariot.
    final wordWidth = width * _wordScale;
    final gap = height * 0.10;
    // Décodage à la taille réellement affichée — le budget d'images est
    // serré à 32 Mo (voir la longue note de `main.dart`).
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final decodeWidth = (width * dpr).round();
    final wordDecodeWidth = (wordWidth * dpr).round();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final fadeOut = const Interval(0.88, 1.0, curve: Curves.easeIn).transform(t);
        final settle = reduced
            ? 1.0
            : const Interval(0.68, 0.88, curve: Curves.easeOutCubic).transform(t);

        return Opacity(
          opacity: 1 - fadeOut,
          child: ColoredBox(
            color: AppTheme.splashDark,
            child: Center(
              // Le tassement final porte sur l'ENSEMBLE marque + mot, pour
              // qu'ils se posent d'un seul geste et non chacun de son côté.
              child: Transform.scale(
                scale: 1.04 - 0.04 * settle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: width,
                      height: height,
                      child: reduced
                          ? _still(decodeWidth, t, width)
                          : _assembling(decodeWidth, t, width),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      width: wordWidth,
                      height: wordWidth / _wordRatio,
                      child: _wordMark(wordDecodeWidth, t),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Le mot « boutigui », posé sous la marque.
  ///
  /// Il arrive APRÈS les trois points, donc une fois le « b » entièrement
  /// construit : la marque se dessine, puis elle se nomme. Il monte de
  /// quelques pixels en apparaissant — sans ce léger déplacement, un
  /// simple fondu le ferait « clignoter » plutôt qu'arriver.
  ///
  /// En mode « animations réduites », il suit le même fondu que le reste,
  /// sans le déplacement.
  Widget _wordMark(int decodeWidth, double t) {
    final p = reduced
        ? const Interval(0.0, 0.45, curve: Curves.easeOut).transform(t)
        : const Interval(0.66, 0.84, curve: Curves.easeOutCubic).transform(t);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, reduced ? 0 : 10 * (1 - p)),
        child: _layer(_word, decodeWidth),
      ),
    );
  }

  /// « Réduire les animations » : le logo complet, sans rien qui bouge.
  Widget _still(int decodeWidth, double t, double width) {
    final appear = const Interval(0.0, 0.45, curve: Curves.easeOut).transform(t);
    return Opacity(
      opacity: appear,
      child: Stack(fit: StackFit.expand, children: [
        for (final d in _depth)
          Opacity(
            opacity: d.opacity,
            child: Transform.translate(
              offset: Offset(-d.dx * width, d.dx * width * 0.6),
              child: _markSilhouette(decodeWidth),
            ),
          ),
        _layer(stem, decodeWidth),
        _layer(_bowl, decodeWidth),
        for (final d in _dots) _layer(d, decodeWidth),
      ]),
    );
  }

  Widget _assembling(int decodeWidth, double t, double width) {
    // La hampe descend.
    final stemT = const Interval(0.00, 0.20, curve: Curves.easeOutCubic).transform(t);
    // La panse s'enroule autour d'elle.
    final bowlT = const Interval(0.16, 0.42, curve: Curves.easeOutCubic).transform(t);
    // L'épaisseur sort de derrière la marque.
    final depthT = const Interval(0.38, 0.60, curve: Curves.easeOutCubic).transform(t);

    return Stack(
      fit: StackFit.expand,
      children: [
        // L'épaisseur d'abord : elle est DERRIÈRE la marque.
        for (var i = 0; i < _depth.length; i++)
          _depthLayer(i, decodeWidth, width, depthT, stemT, bowlT),
        // La hampe, découverte du haut vers le bas.
        ClipRect(
          clipper: _FractionClipper(_stemTop + (_stemBottom - _stemTop) * stemT),
          child: _layer(stem, decodeWidth),
        ),
        // La panse, enroulée. Départ à 9 h (π) : c'est le point où elle
        // rejoint la hampe, donc le trait part de la hampe et en fait le
        // tour, au lieu de naître dans le vide.
        ClipPath(
          clipper: _SweepClipper(centre: _bowlCentre, turns: bowlT, startAngle: 3.141592),
          child: _layer(_bowl, decodeWidth),
        ),
        // Les points, un par un, en remontant la diagonale.
        for (var i = 0; i < _dots.length; i++) _dot(i, decodeWidth, t),
      ],
    );
  }

  /// Une couche d'épaisseur. Elle reprend la silhouette de la marque
  /// DÉJÀ DESSINÉE (mêmes découpes que la hampe et la panse) : sans cela,
  /// l'ombre d'un trait pas encore tracé apparaîtrait avant lui.
  Widget _depthLayer(int i, int decodeWidth, double width, double depthT, double stemT, double bowlT) {
    final d = _depth[i];
    // Décalage progressif, échelonné : la couche la plus lointaine part
    // légèrement après les autres.
    final stagger = (depthT - i * 0.12).clamp(0.0, 1.0);
    return Opacity(
      opacity: d.opacity * stagger,
      child: Transform.translate(
        offset: Offset(-d.dx * width * stagger, d.dx * width * 0.6 * stagger),
        child: Stack(fit: StackFit.expand, children: [
          ClipRect(
            clipper: _FractionClipper(_stemTop + (_stemBottom - _stemTop) * stemT),
            child: _layer(stem, decodeWidth),
          ),
          ClipPath(
            clipper: _SweepClipper(centre: _bowlCentre, turns: bowlT, startAngle: 3.141592),
            child: _layer(_bowl, decodeWidth),
          ),
        ]),
      ),
    );
  }

  /// Silhouette complète — utilisée seulement en mode « animations
  /// réduites », où rien n'est découpé.
  Widget _markSilhouette(int decodeWidth) => Stack(
        fit: StackFit.expand,
        children: [_layer(stem, decodeWidth), _layer(_bowl, decodeWidth)],
      );

  /// Chaque point apparaît en grossissant légèrement au-delà de sa taille
  /// finale avant de se poser — c'est ce petit dépassement qui les fait
  /// lire comme « posés » plutôt que « allumés ».
  Widget _dot(int i, int decodeWidth, double t) {
    // Échelonnés pour se terminer AVANT l'arrivée du mot (0,66) : la
    // marque doit être finie quand elle se nomme.
    final start = 0.42 + i * 0.06;
    final p = Interval(start, (start + 0.12).clamp(0.0, 1.0), curve: Curves.easeOutBack).transform(t);
    return Opacity(
      opacity: p.clamp(0.0, 1.0),
      child: Transform.scale(scale: p.clamp(0.0, 1.2), child: _layer(_dots[i], decodeWidth)),
    );
  }

  Widget _layer(String asset, int decodeWidth) => Image(
        image: ResizeImage(AssetImage(asset), width: decodeWidth),
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
}

/// L'ancienne ouverture — le chariot entre par la gauche, le nom se pose
/// dessus. Conservée comme repli tant que les calques du « b » ne sont pas
/// dans le dépôt : un asset manquant ne doit pas casser le démarrage.
class _CartCurtain extends StatelessWidget {
  final AnimationController controller;
  final bool reduced;

  const _CartCurtain({required this.controller, required this.reduced});

  @override
  Widget build(BuildContext context) {
    final cart = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.00, 0.34, curve: Curves.easeOutCubic),
    );
    final word = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.22, 0.52, curve: Curves.easeOut),
    );
    final fadeOut = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.80, 1.00, curve: Curves.easeIn),
    );

    final width = (MediaQuery.sizeOf(context).width * 0.58).clamp(180.0, 300.0);
    final decodeWidth = (width * MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0)).round();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Opacity(
          opacity: 1 - fadeOut.value,
          child: ColoredBox(
            color: AppTheme.bg,
            child: Center(
              child: SizedBox(
                width: width,
                // 1,53 = rapport largeur/hauteur de la toile commune.
                height: width / 1.53,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      offset: Offset(reduced ? 0 : -width * 1.15 * (1 - cart.value), 0),
                      child: Opacity(
                        opacity: reduced ? controller.value.clamp(0.0, 1.0) : 1,
                        child: Image(
                          image: ResizeImage(
                            const AssetImage('assets/images/splash_cart.png'),
                            width: decodeWidth,
                          ),
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: word.value,
                      child: Image(
                        image: ResizeImage(
                          const AssetImage('assets/images/splash_word.png'),
                          width: decodeWidth,
                        ),
                        fit: BoxFit.contain,
                        semanticLabel: 'Boutigui',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
