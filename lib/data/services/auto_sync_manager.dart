import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:lstracker/data/services/dio_client.dart';
import 'package:lstracker/data/services/log_service.dart';
import 'package:lstracker/data/services/sync_service.dart';

/// Gère le push/pull automatique tant que l'app est ouverte.
///
/// Stratégie :
/// - timer périodique (15 min par défaut)
/// - déclenchement sur reprise d'app (resumed)
/// - déclenchement à la reconnexion réseau
/// - **back-off exponentiel** sur erreur (60s → 2min → 5min → 15min, plafond)
///   pour éviter le hammering du serveur en panne
/// - throttle 60s pour éviter les déclenchements multiples rapprochés
class AutoSyncManager with WidgetsBindingObserver {
  AutoSyncManager._();
  static final AutoSyncManager instance = AutoSyncManager._();

  static const _tag = 'AutoSync';

  // Back-off : on multiplie l'intervalle minimum après chaque échec consécutif.
  // 0 échec → 60s. 1 → 2min. 2 → 5min. 3+ → 15min (plafond).
  static const _backoffSteps = <Duration>[
    Duration(seconds: 60),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  final _sync = SyncService(dio: DioClient.instance.dio);
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _running = false;
  DateTime? _lastRun;
  int _consecutiveFailures = 0;

  /// Démarre le mécanisme auto-sync.
  void start({Duration interval = const Duration(minutes: 15)}) {
    if (_timer != null || _connSub != null) return;

    WidgetsBinding.instance.addObserver(this);

    _timer = Timer.periodic(interval, (_) => _runIfNeeded(reason: 'timer'));

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        LogService.instance.debug(_tag, 'réseau retrouvé');
        _runIfNeeded(reason: 'network');
      }
    });

    Future.delayed(
      const Duration(seconds: 5),
      () => _runIfNeeded(reason: 'initial'),
    );
    LogService.instance.info(_tag, 'auto-sync démarré (intervalle: ${interval.inMinutes}min)');
  }

  /// Arrête le mécanisme auto-sync (à appeler au logout).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _connSub?.cancel();
    _connSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _consecutiveFailures = 0;
    _lastRun = null;
    LogService.instance.info(_tag, 'auto-sync arrêté');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runIfNeeded(reason: 'resume');
    }
  }

  /// Délai minimum à respecter avant le prochain run, en fonction du
  /// nombre d'échecs consécutifs.
  Duration get _currentMinInterval {
    final idx = _consecutiveFailures.clamp(0, _backoffSteps.length - 1);
    return _backoffSteps[idx];
  }

  /// Déclenche un push+pull si pas déjà en cours et si la dernière exécution
  /// est plus vieille que le délai courant (avec back-off exponentiel).
  Future<void> _runIfNeeded({required String reason}) async {
    if (_running) {
      LogService.instance.debug(_tag, 'skip ($reason): déjà en cours');
      return;
    }
    if (_lastRun != null) {
      final elapsed = DateTime.now().difference(_lastRun!);
      final minInterval = _currentMinInterval;
      if (elapsed < minInterval) {
        LogService.instance.debug(
          _tag,
          'skip ($reason): ${elapsed.inSeconds}s écoulés, min ${minInterval.inSeconds}s (échecs consécutifs: $_consecutiveFailures)',
        );
        return;
      }
    }

    _running = true;
    try {
      LogService.instance.info(_tag, 'run déclenché (raison: $reason)');
      final result = await _sync.run();
      _lastRun = DateTime.now();
      if (result.hasError) {
        _consecutiveFailures = (_consecutiveFailures + 1).clamp(0, _backoffSteps.length - 1);
        LogService.instance.warn(
          _tag,
          'run terminé avec erreur(s) (back-off: ${_currentMinInterval.inSeconds}s)',
        );
      } else {
        if (_consecutiveFailures > 0) {
          LogService.instance.info(_tag, 'reprise après $_consecutiveFailures échec(s)');
        }
        _consecutiveFailures = 0;
      }
    } catch (e, st) {
      _lastRun = DateTime.now();
      _consecutiveFailures = (_consecutiveFailures + 1).clamp(0, _backoffSteps.length - 1);
      LogService.instance.error(_tag, 'run a planté', error: e, stackTrace: st);
    } finally {
      _running = false;
    }
  }

  /// À appeler juste après une nouvelle soumission locale (collecte, dépôt, etc.).
  /// Pousse uniquement (rapide), le pull viendra via le périodique.
  void pushNow() {
    unawaited(_safePush());
  }

  Future<void> _safePush() async {
    if (_running) return;
    _running = true;
    try {
      LogService.instance.info(_tag, 'pushNow déclenché');
      final pushed = await _sync.pushDirty();
      _lastRun = DateTime.now();
      _consecutiveFailures = 0;
      LogService.instance.info(_tag, 'pushNow: $pushed élément(s) envoyé(s)');
    } catch (e, st) {
      _consecutiveFailures = (_consecutiveFailures + 1).clamp(0, _backoffSteps.length - 1);
      LogService.instance.error(_tag, 'pushNow a échoué', error: e, stackTrace: st);
    } finally {
      _running = false;
    }
  }
}
