import 'package:dio/dio.dart';
import 'package:lstracker/app_config/app_config.dart';
import 'package:lstracker/data/services/dio_client.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class MetadataDao {
  final Future<Database> _dbFuture = AppDatabase.instance.database;

  Future<void> replaceAllFromServerPayload(Map<String, dynamic> payload) async {
    final db = await _dbFuture;

    final labs = (payload['labs'] as List?) ?? const [];
    // Absent sur un serveur antérieur : tous les labos reçus restent alors
    // sélectionnables (comportement historique).
    final allLabs = (payload['allLabs'] as List?) ?? const [];
    final circuits = (payload['circuits'] as List?) ?? const [];
    final sites = (payload['sites'] as List?) ?? const [];
    final rejectionTypes = (payload['rejectionTypes'] as List?) ?? const [];
    final circuitSites = (payload['circuitSites'] as List?) ?? const [];

    await db.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      await txn.delete('circuit_site');
      await txn.delete('site');
      await txn.delete('circuit');
      await txn.delete('lab');
      await txn.delete('rejection_type');

      final batch = txn.batch();

      // Circuits
      for (final e in circuits) {
        if (e is Map) {
          batch.insert('circuit', {
            'id': (e['id'] as num?)?.toInt(),
            'name': (e['name'] ?? '').toString(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // Labs : référentiel complet (noms/types pour l'affichage), puis ceux
      // que l'utilisateur peut choisir, qui écrasent avec selectable = 1.
      for (final e in allLabs) {
        if (e is Map) {
          batch.insert('lab', {
            'id': (e['id'] as num?)?.toInt(),
            'name': (e['name'] ?? '').toString(),
            'lab_type': (e['labType'] ?? '').toString(),
            'selectable': 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final e in labs) {
        if (e is Map) {
          batch.insert('lab', {
            'id': (e['id'] as num?)?.toInt(),
            'name': (e['name'] ?? '').toString(),
            'lab_type': (e['labType'] ?? '').toString(),
            'selectable': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // Rejection types
      for (final e in rejectionTypes) {
        if (e is Map) {
          batch.insert('rejection_type', {
            'id': (e['id'] as num?)?.toInt(),
            'name': (e['name'] ?? '').toString(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // Sites (référence circuitId)
      final seen = <int>{};
      for (final e in sites) {
        if (e is Map) {
          final id = (e['id'] as num?)?.toInt();
          if (id == null || seen.contains(id)) continue;
          seen.add(id);
          batch.insert('site', {
            'id': id,
            'name': (e['name'] ?? '').toString(),
            'dhis_code': (e['dhisCode'] ?? '').toString(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // Mappings circuit_site
      for (final e in circuitSites) {
        if (e is Map) {
          batch.insert('circuit_site', {
            'circuit_id': (e['circuitId'] as num?)?.toInt(),
            'site_id': (e['siteId'] as num?)?.toInt(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await batch.commit(noResult: true);
      await txn.execute('PRAGMA foreign_keys = ON');

      final version = payload['version'] is int
          ? payload['version'] as int
          : int.tryParse('${payload['version'] ?? 0}') ?? 0;
      await txn.update(
        'metadata_version',
        {'version': version, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: const [1],
      );
    });
  }

  Future<int> currentVersion() async {
    final db = await _dbFuture;
    final r = await db.query('metadata_version', where: 'id = 1', limit: 1);
    if (r.isEmpty) return 0;
    return (r.first['version'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> listCircuits() async {
    final db = await _dbFuture;
    return db.query('circuit', orderBy: 'name ASC');
  }

  Future<List<Map<String, Object?>>> listSitesByCircuit(int circuitId) async {
    final db = await _dbFuture;
    return db.query(
      'site',
      where: 'circuit_id = ?',
      whereArgs: [circuitId],
      orderBy: 'name ASC',
    );
  }

  Future<List<Map<String, Object?>>> listLabs() async {
    final db = await _dbFuture;
    return db.query('lab', orderBy: 'name ASC');
  }

  Future<List<Map<String, Object?>>> listRejectionTypes() async {
    final db = await _dbFuture;
    return db.query('rejection_type', orderBy: 'name ASC');
  }

  Future<int> refreshFromServer({Dio? dio}) async {
    final client = dio ?? DioClient.instance.dio; // <- même client que partout
    try {
      final res = await client.get(
        AppConfig.metaFullPath, // '/api/meta/full'
        options: Options(headers: {'Accept': 'application/json'}),
      );

      final data = (res.data is Map) ? res.data as Map : {};
      final labs = (data['labs'] as List? ?? const []);
      final circuits = (data['circuits'] as List? ?? const []);
      final sites = (data['sites'] as List? ?? const []);
      final rejections = (data['rejectionTypes'] as List? ?? const []);
      final version = (data['version'] as int?) ?? 0;

      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        // vide puis réinsère
        await txn.delete('lab');
        await txn.delete('circuit');
        await txn.delete('site');
        await txn.delete('rejection_type');

        // insert labs
        for (final r in labs) {
          final m = Map<String, dynamic>.from(r as Map);
          await txn.insert('lab', {
            'id': (m['id'] as num).toInt(),
            'name': (m['name'] ?? '').toString(),
            'lab_type': (m['labType'] ?? '').toString(),
          });
        }

        for (final r in circuits) {
          final m = Map<String, dynamic>.from(r as Map);
          await txn.insert('circuit', {
            'id': (m['id'] as num).toInt(),
            'name': (m['name'] ?? '').toString(),
          });
        }

        for (final r in sites) {
          final m = Map<String, dynamic>.from(r as Map);
          await txn.insert('site', {
            'id': (m['id'] as num).toInt(),
            'name': (m['name'] ?? '').toString(),
            'dhis_code': (m['dhisCode'] ?? '').toString(),
            // si tu utilises circuit_site (N-N), enlève ‘circuit_id’ ici.
            'circuit_id': (m['circuitId'] as num?)?.toInt(),
          });
        }

        for (final r in rejections) {
          final m = Map<String, dynamic>.from(r as Map);
          await txn.insert('rejection_type', {
            'id': (m['id'] as num).toInt(),
            'name': (m['name'] ?? '').toString(),
          });
        }

        // version métadonnées
        await txn.insert('metadata_version', {
          'id': 1,
          'version': version,
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

      // total “objets” ramenés, juste pour le feedback
      return labs.length + circuits.length + sites.length + rejections.length;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final bodyText = body is String ? body : (body?.toString() ?? '');
      throw 'HTTP $code — ${e.message ?? ""} ${bodyText.isNotEmpty ? " | $bodyText" : ""}';
    }
  }
}
