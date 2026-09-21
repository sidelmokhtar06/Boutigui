import 'package:flutter/material.dart';
import '../core/strings.dart';

/// Affiché tant que lib/app_config.dart contient encore les valeurs
/// d'exemple — évite de se demander pourquoi rien ne charge.
class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 64, color: Colors.orange),
                const SizedBox(height: 20),
                Text(
                  Strings.t('not_configured_title', 'fr'),
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  Strings.t('not_configured_body', 'fr'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
