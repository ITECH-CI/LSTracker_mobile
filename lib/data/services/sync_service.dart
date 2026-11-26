// lib/services/sync_service.dart
import 'package:dio/dio.dart';
import 'package:lstracker/app_config/app_config.dart';
import 'package:lstracker/data/db/sample_dao.dart';
import 'package:lstracker/data/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dio_client.dart';

class SyncResult {
  final int pushed;
  final int pulled;
  final int conflicts;
  final bool pushOk;
  final bool pullOk;
  final DateTime endedAt;
  final List<String> messages;

  SyncResult({
    required this.pushed,
    required this.pulled,
    required this.conflicts,
    required this.pushOk,
    required this.pullOk,
    required this.endedAt,
    required this.messages,
  });

  bool get hasError => !pushOk || !pullOk;
}

class SyncService {
  SyncService({Dio? dio, SampleDao? sampleDao})
    : _dio = dio ?? DioClient.instance.dio,
      dao = sampleDao ?? SampleDao();

  final Dio _dio;
  final SampleDao dao;

  static const _kLastPullKey = 'sync.last_pull_at'; // ISO-8601
  static const _tag = 'Sync';

  Future<DateTime?> getLastPull() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kLastPullKey);
    if (v == null || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  Future<void> _setLastPull(DateTime t) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastPullKey, t.toIso8601String());
  }

  /// Push des dirty samples. Retourne le nombre d'éléments envoyés.
  /// En cas d'erreur, marque les rows concernées avec [last_sync_error]
  /// et relance une exception pour que [run] puisse aborter le pull.
  Future<int> pushDirty() async {
    final dirty = await dao.listDirty();
    if (dirty.isEmpty) return 0;

    LogService.instance.info(_tag, 'push: ${dirty.length} dirty sample(s) en attente');

    final payload = {'samples': dirty.map((s) => s.toServerMap()).toList()};
    final uuids = dirty.map((s) => s.uuid).whereType<String>().toList();

    try {
      final res = await _dio.post(
        AppConfig.samplesPushPath,
        data: payload,
        options: Options(contentType: 'application/json'),
      );

      final data = (res.data is Map) ? res.data as Map : {};
      final List mapped = (data['mapped'] as List?) ?? const [];

      final Map<String, String> uuidToExternalId = {};
      for (final m in mapped) {
        final mm = m as Map;
        final uuid = (mm['uuid'] ?? '').toString();
        final ext = (mm['external_id'] ?? '').toString();
        if (uuid.isNotEmpty && ext.isNotEmpty) {
          uuidToExternalId[uuid] = ext;
        }
      }

      await dao.markPushed(uuidToExternalId);
      final acked = uuidToExternalId.length;
      LogService.instance.info(
        _tag,
        'push: $acked/${dirty.length} échantillon(s) confirmés par le serveur',
      );

      // Les rows envoyées mais non acquittées restent dirty et reçoivent
      // un message d'erreur explicite pour l'UI.
      final unacked = uuids.where((u) => !uuidToExternalId.containsKey(u)).toList();
      if (unacked.isNotEmpty) {
        await dao.markPushFailed(
          unacked,
          'Non acquitté par le serveur lors du dernier push',
        );
        LogService.instance.warn(
          _tag,
          'push: ${unacked.length} échantillon(s) non acquittés, dirty conservé',
        );
      }
      return acked;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final msg = 'pushDirty: HTTP $code (${body ?? e.message})';
      LogService.instance.error(_tag, msg, error: e, stackTrace: e.stackTrace);
      await dao.markPushFailed(uuids, 'HTTP ${code ?? "?"}');
      throw msg;
    } catch (e, st) {
      LogService.instance.error(_tag, 'pushDirty: erreur inattendue', error: e, stackTrace: st);
      await dao.markPushFailed(uuids, e.toString());
      rethrow;
    }
  }

  /// Pull incrémental depuis le serveur. Retourne le nombre d'items reçus.
  /// Met à jour [_kLastPullKey] uniquement si tout s'est bien passé.
  Future<int> pull({DateTime? since}) async {
    final last = since ?? await getLastPull();
    LogService.instance.info(
      _tag,
      'pull: depuis ${last?.toIso8601String() ?? "(complet)"}',
    );

    try {
      final res = await _dio.get(
        AppConfig.samplesPullPath,
        queryParameters: last != null
            ? {'since': last.toUtc().toIso8601String()}
            : null,
      );

      final data = (res.data is Map) ? res.data as Map : {};
      final List remote = (data['samples'] as List?) ?? const [];

      int applied = 0;
      int skipped = 0;
      for (final item in remote) {
        final ok = await dao.upsertFromServer(
          Map<String, dynamic>.from(item as Map),
        );
        if (ok) {
          applied++;
        } else {
          skipped++;
        }
      }

      await _setLastPull(DateTime.now().toUtc());
      LogService.instance.info(
        _tag,
        'pull: ${remote.length} reçu(s) ($applied appliqué(s), $skipped conflit(s)/préservé(s))',
      );
      return remote.length;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final msg = 'pull: HTTP $code (${body ?? e.message})';
      LogService.instance.error(_tag, msg, error: e, stackTrace: e.stackTrace);
      throw msg;
    } catch (e, st) {
      LogService.instance.error(_tag, 'pull: erreur inattendue', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Orchestrateur push → pull. **Ordre strict** :
  /// si le push échoue, le pull est aborté pour éviter d'écraser les
  /// modifications locales non encore poussées par une version serveur
  /// obsolète (la protection [dao.upsertFromServer] préserve déjà les
  /// dirty=1, mais on évite quand même le travail inutile).
  Future<SyncResult> run() async {
    final messages = <String>[];
    int pushed = 0;
    int pulled = 0;
    bool pushOk = true;
    bool pullOk = true;

    final startedAt = DateTime.now();
    LogService.instance.info(_tag, 'run: démarrage');

    try {
      pushed = await pushDirty();
      messages.add('PUSH: $pushed élément(s) envoyé(s).');
    } catch (e) {
      pushOk = false;
      messages.add('PUSH: erreur ($e)');
    }

    if (!pushOk) {
      // ABORT : on ne tire pas du serveur tant qu'on n'a pas confirmé
      // l'envoi des changements locaux. L'utilisateur retentera plus tard.
      messages.add('PULL: ignoré (push en échec).');
      LogService.instance.warn(_tag, 'run: pull annulé car push a échoué');
      pullOk = false;
    } else {
      try {
        pulled = await pull();
        messages.add('PULL: $pulled élément(s) reçu(s).');
      } catch (e) {
        pullOk = false;
        messages.add('PULL: erreur ($e)');
      }
    }

    final conflicts = await dao.countConflicts();
    if (conflicts > 0) {
      messages.add('CONFLITS: $conflicts élément(s) à résoudre.');
    }

    final duration = DateTime.now().difference(startedAt).inMilliseconds;
    LogService.instance.info(
      _tag,
      'run: terminé en ${duration}ms (pushOk=$pushOk pullOk=$pullOk conflits=$conflicts)',
    );

    return SyncResult(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      pushOk: pushOk,
      pullOk: pullOk,
      endedAt: DateTime.now(),
      messages: messages,
    );
  }
}
