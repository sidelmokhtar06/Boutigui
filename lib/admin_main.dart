import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';
import 'core/theme.dart';
import 'features/not_configured_screen.dart';
import 'services/auth_service.dart';
import 'admin/admin_shell.dart';
import 'admin/admin_login_screen.dart';

/// Point d'entrée du site ADMIN — projet Flutter séparé du client mobile,
/// mais dans la même base de code (mêmes modèles, mêmes services Supabase).
/// Se lance avec :
///   flutter run -d web-server --web-port=8081 -t lib/admin_main.dart \
///     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const MaterialApp(debugShowCheckedModeBanner: false, home: NotConfiguredScreen());
    }
    return ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Admin',
        theme: AdminTheme.dark(),
        home: const _AdminGate(),
      ),
    );
  }
}

class _AdminGate extends StatelessWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isLoggedIn) {
      return const AdminLoginScreen();
    }
    if (auth.profile == null || !auth.profile!.isAdmin) {
      return Scaffold(
        backgroundColor: AdminTheme.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 56, color: AdminTheme.red),
                const SizedBox(height: 16),
                const Text(
                  "Ce compte n'a pas les droits administrateur.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.read<AuthService>().signOut(),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const AdminShell();
  }
}
