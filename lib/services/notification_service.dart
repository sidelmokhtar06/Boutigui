import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Notifications — 6 septembre 2026.
///
/// Jusqu'ici, une vendeuse ne savait qu'elle avait vendu que si elle
/// pensait à ouvrir "Ma boutique", et une cliente n'apprenait la
/// confirmation de son paiement qu'en retournant dans "Mes commandes".
///
/// **Ce sont des notifications DANS l'application**, pas des notifications
/// qui s'affichent quand l'app est fermée : celles-là demandent Firebase
/// côté Android et un compte développeur payant côté Apple. C'est la suite
/// naturelle, pas ce tour-ci.
///
/// Les lignes sont écrites par la BASE elle-même (déclencheurs de
/// `supabase/paiement_options_patch.sql`) : personne ne peut donc s'en
/// envoyer de fausses ni en écrire à quelqu'un d'autre, et chacun ne lit
/// que les siennes (RLS).
class NotificationService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AppNotification>> fetch({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((r) => AppNotification.fromMap(r)).toList();
  }

  /// **21 septembre 2026 (audit) : compté par la base, plus par l'app.**
  /// Cette méthode rapatriait TOUTES les lignes non lues pour en prendre
  /// la longueur, et elle tourne toutes les 30 secondes (voir
  /// [NotificationsController]) : le coût grandissait avec l'historique de
  /// chaque compte, pour un nombre affiché sur une pastille. `count()`
  /// laisse PostgreSQL compter et ne transfère que l'entier.
  Future<int> unreadCount() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;
    return _client
        .from('notifications')
        .count(CountOption.exact)
        .eq('user_id', user.id)
        .eq('is_read', false);
  }

  Future<void> markAllRead() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);
  }
}

/// Compteur de non-lues, partagé par la barre du bas et l'écran des
/// notifications.
///
/// Rafraîchi toutes les 30 secondes plutôt que par abonnement temps réel :
/// le temps réel de Supabase suppose que la table soit ajoutée à la
/// publication `supabase_realtime` côté serveur, et si cette étape est
/// oubliée l'abonnement ne remonte RIEN, sans erreur — la pastille
/// resterait muette sans qu'on comprenne pourquoi. Une simple relecture
/// périodique marche à tous les coups, et 30 secondes de délai n'ont
/// aucune importance pour une commande.
class NotificationsController extends ChangeNotifier {
  final NotificationService _service = NotificationService();
  Timer? _timer;
  int _unread = 0;

  int get unread => _unread;

  void start() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final count = await _service.unreadCount();
      if (count != _unread) {
        _unread = count;
        notifyListeners();
      }
    } catch (_) {
      // Pas de réseau, pas de session, table pas encore créée : la
      // pastille n'est pas assez importante pour interrompre quoi que ce
      // soit à l'écran.
    }
  }

  Future<void> markAllRead() async {
    await _service.markAllRead();
    _unread = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
