import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'core/settings_controller.dart';
import 'core/theme.dart';
import 'features/not_configured_screen.dart';
import 'features/shell.dart';
import 'services/auth_service.dart';
import 'services/cart_controller.dart';
import 'services/notification_service.dart';
import 'services/role_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **Limite du cache d'images — 9 septembre 2026.**
  //
  // Flutter garde par défaut jusqu'à 100 Mo et 1000 images DÉCODÉES en
  // mémoire. C'est calibré pour un ordinateur. Safari sur iPhone lâche
  // bien avant : quand la mémoire graphique est saturée, il ne plante pas,
  // il dessine du NOIR à la place des photos. C'est exactement ce qu'on
  // observait après une minute de défilement — le temps de remplir le
  // cache.
  //
  // 40 Mo et 100 images, c'est assez pour que le défilement reste fluide
  // (une vignette de 500 px décodée pèse environ 1 Mo), et assez bas pour
  // qu'un iPhone tienne. Les images sorties du cache sont simplement
  // rechargées depuis le disque du navigateur, sans nouvel appel réseau.
  // Abaissé à 24 Mo / 60 images le 10 septembre 2026 : à 40 Mo, Safari sur
  // iPhone dessinait encore du noir. C'est bas, mais une vignette de 500 px
  // pèse moins d'un mégaoctet décodée — il en reste donc largement de quoi
  // remplir plusieurs écrans sans recharger.
  //
  // Remonté à 32 Mo / 90 images le 13 septembre 2026, EN MÊME TEMPS que le
  // `cacheExtent` des listes (voir home_screen.dart) est repassé de 0 à une
  // petite marge — puis le symptôme (photos noires en remontant) est
  // réapparu : 32 Mo semblait large sur le papier (90 photos à ~1 Mo
  // chacune), mais chaque photo pesait en réalité 1,5 à 2 Mo, décodée à la
  // densité d'écran complète (×3 sur iPhone). Le budget se vidait donc
  // après ~17-20 photos à peine — moins qu'un simple écran d'accueil.
  //
  // **14 septembre 2026** : la densité de décodage est maintenant
  // plafonnée à ×2 (voir `AppImage`, widgets.dart), ce qui coupe le poids
  // réel par photo d'environ 45 %. Le budget ci-dessous est recalculé sur
  // ce nouveau poids (~0,8-1 Mo/photo) pour tenir confortablement un écran
  // chargé (bannière + plusieurs rangées) SANS redescendre au niveau de
  // départ (une centaine de Mo) qui causait le bug d'origine — celui-ci
  // venait des photos envoyées à leur pleine résolution (plusieurs milliers
  // de pixels, voir image_compressor.dart), pas du budget lui-même.
  // **15 septembre 2026 — repassé à 32 Mo / 90 images.** Ce fichier disait
  // 80 Mo / 260 images juste avant cette correction : une valeur plus
  // grande que TOUT ce que l'historique ci-dessus décrit, et surtout très
  // proche des ~100 Mo par défaut de Flutter qui causaient le bug
  // D'ORIGINE ("photos noires" sur Safari iPhone, voir la note du 9
  // septembre 2026 tout en haut). Remontée par erreur à un moment non
  // documenté, elle a rouvert exactement le même symptôme (remonté le 15
  // septembre 2026 : photos noires ET artefacts de rendu — texte dupliqué
  // à l'écran pendant le défilement, un symptôme de la même famille :
  // mémoire graphique saturée sur Safari iPhone). 32 Mo / 90 images reste
  // la dernière valeur dont on sait, par expérience directe, qu'elle tient
  // sur iPhone avec la densité de décodage plafonnée à ×2 (note du 14
  // septembre 2026 ci-dessus) : NE PAS remonter ces deux nombres sans
  // avoir revérifié sur un vrai iPhone, pas seulement "en théorie".
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 90;

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  runApp(const MarketplaceApp());
}

class MarketplaceApp extends StatelessWidget {
  const MarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NotConfiguredScreen(),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CartController()),
        // Compteur de notifications non lues — relu périodiquement dès le
        // lancement (6 septembre 2026).
        ChangeNotifierProvider(create: (_) => NotificationsController()..start()),
        // Rôle du compte (cliente ou vendeuse) — pilote ce qu'affiche
        // l'écran Compte (6 septembre 2026).
        ChangeNotifierProvider(create: (_) => RoleController()..refresh()),
      ],
      child: Consumer<SettingsController>(
        builder: (context, settings, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Shop',
            theme: AppTheme.light(),
            themeMode: ThemeMode.light,
            locale: Locale(settings.locale),
            // Revenu en arrière (3 septembre 2026) : Emina ne veut pas que
            // l'appli garde sa largeur "téléphone" sur ordinateur — le
            // contenu doit utiliser toute la largeur disponible, sans
            // limite ni fond noir autour. Retour à l'affichage simple.
            builder: (context, child) => Directionality(
              textDirection: settings.textDirection,
              child: child!,
            ),
            home: Shell(),
          );
        },
      ),
    );
  }
}
