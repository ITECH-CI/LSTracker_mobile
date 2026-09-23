import 'package:lstracker/data/stores/auth_store.dart';

/// Utilitaires d'authentification (rôle, etc.)
///
/// Les valeurs (rôle, userId) sont mises en cache après le premier accès :
/// elles ne changent pas pendant une session, donc on évite les appels
/// répétés au secure storage à chaque rebuild de widget. Le cache est
/// vidé via [clearCache] à la déconnexion (cf. AuthService.logout()).
class AuthUtils {
  // Cache au scope process. Volontairement statique : aucun écran ne doit
  // détenir cet état localement, car il est partagé partout.
  static String? _cachedRole;
  static int? _cachedUserId;
  static bool _roleLoaded = false;
  static bool _userIdLoaded = false;

  /// Récupère le rôle de l'utilisateur courant.
  /// Exemple de valeurs : 'ADMIN', 'CONVOYEUR', 'BIOLOGISTE'.
  ///
  /// Le premier appel touche le secure storage ; les suivants sont
  /// instantanés (cache local). Pour rafraîchir après login, appelle
  /// [prime] ou [clearCache].
  static Future<String?> getUserRole() async {
    if (_roleLoaded) return _cachedRole;
    final store = AuthStore();
    _cachedRole = await store.role;
    _roleLoaded = true;
    return _cachedRole;
  }

  /// Variante synchrone : utilisable dans les `build()` sans
  /// FutureBuilder, à condition que [prime] ait été appelée au boot
  /// (ce qui est le cas dans `main.dart` après le login).
  ///
  /// Retourne `null` si le cache n'est pas encore chaud.
  static String? roleOrNull() => _roleLoaded ? _cachedRole : null;

  static Future<int> getUserId() async {
    if (_userIdLoaded) return _cachedUserId ?? 0;
    final store = AuthStore();
    _cachedUserId = await store.userId ?? 0;
    _userIdLoaded = true;
    return _cachedUserId ?? 0;
  }

  /// Précharge le rôle + userId dans le cache. À appeler au boot dans
  /// `main.dart` après que le token a été chargé, pour que les écrans
  /// puissent lire la valeur en synchrone via [roleOrNull].
  static Future<void> prime() async {
    await getUserRole();
    await getUserId();
  }

  /// Vide le cache. À appeler au logout pour que la prochaine session
  /// ne ré-utilise pas le rôle de l'utilisateur précédent.
  static void clearCache() {
    _cachedRole = null;
    _cachedUserId = null;
    _roleLoaded = false;
    _userIdLoaded = false;
  }

  /// Vérifie rapidement un rôle.
  static Future<bool> isAdmin() async =>
      (await getUserRole())?.toUpperCase() == 'ADMIN';

  static Future<bool> isConvoyeur() async =>
      (await getUserRole())?.toUpperCase() == 'CONVOYEUR';

  static Future<bool> isBiologiste() async =>
      (await getUserRole())?.toUpperCase() == 'BIOLOGISTE';

  /// Tâches de terrain : déposer au labo, modifier/supprimer une collecte,
  /// modifier un dépôt, collecter et déposer les résultats. Elles incombent
  /// au convoyeur (et à l'admin) ; le biologiste ne fait que suivre ces
  /// étapes, en consultation.
  static bool canDoConveyorTasks(String? role) {
    final r = role?.toUpperCase();
    return r == 'CONVOYEUR' || r == 'ADMIN';
  }
}
