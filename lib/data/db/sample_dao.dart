import 'package:sqflite/sqflite.dart';

import '../models/sample.dart';
import 'app_database.dart';

class SampleDao {
  final Future<Database> _dbFuture = AppDatabase.instance.database;

  Future<int> insertSample(Sample s) async {
    final db = await _dbFuture;
    final data = s.copyWith(createdAt: DateTime.now().toString()).toMap();
    data.remove('id');
    return db.insert(
      'sample',
      data,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> upsertByUuid(Sample s) async {
    final db = await _dbFuture;
    final data = s.copyWith(lastupdatedAt: DateTime.now().toString()).toMap();
    final existing = await db.query(
      'sample',
      where: 'uuid = ?',
      whereArgs: [s.uuid],
      limit: 1,
    );
    if (existing.isEmpty) {
      data.remove('id');
      return db.insert(
        'sample',
        data,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final id = existing.first['id'] as int;
      return db.update('sample', data, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<int> updateSample(Sample s) async {
    if (s.id == null) throw ArgumentError('updateSample requires non-null id');
    final db = await _dbFuture;
    final data = s
        .copyWith(lastupdatedAt: DateTime.now().toString(), dirty: 1)
        .toMap();
    return db.update('sample', data, where: 'id = ?', whereArgs: [s.id]);
  }

  Future<Sample?> getById(int id) async {
    final db = await _dbFuture;
    final rows = await db.query(
      'sample',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Sample.fromMap(rows.first);
  }

  Future<Sample?> getByUuid(String uuid) async {
    final db = await _dbFuture;
    final rows = await db.query(
      'sample',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Sample.fromMap(rows.first);
  }

  Future<List<Sample>> getDirtySamples({int limit = 100}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      'sample',
      where: 'dirty = 1',
      orderBy: 'lastupdated_at ASC',
      limit: limit,
    );
    return rows.map(Sample.fromMap).toList();
  }

  Future<int> markSynced(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _dbFuture;
    final idList = ids.map((e) => e.toString()).join(',');
    return db.rawUpdate('UPDATE sample SET dirty = 0 WHERE id IN ($idList)');
  }

  // --- Convoyeur ---
  Future<int> markCollected({
    required String uuid,
    required int conveyorUserId,
    required int fromSiteId,
    required double startMileage,
    required DateTime collectionDate,
    required DateTime pickupDate,
    required String sampleType,
    required String sampleNature,
    String? patientIdentifier,
    String? sampleIdentifier,
    int? destinationLabId,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now();
    final data = {
      'uuid': uuid,
      'sample_conveyor': conveyorUserId,
      'from_site_id': fromSiteId,
      'start_mileage': startMileage,
      'collection_date': collectionDate.toIso8601String(),
      'pickup_date': pickupDate.toIso8601String(),
      'sample_type': sampleType,
      'sample_nature': sampleNature,
      'patient_identifier': patientIdentifier,
      'sample_identifier': sampleIdentifier,
      'destination_lab_id': destinationLabId,
      'sample_status': SampleStatus.onTransit,
      'lastupdated_at': now.toIso8601String(),
      'dirty': 1,
    };
    final exists = await db.query(
      'sample',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (exists.isEmpty) {
      data['created_at'] = now.toIso8601String();
      return db.insert('sample', data);
    } else {
      final id = exists.first['id'] as int;
      return db.update('sample', data, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<int> markDeliveredToLab({
    required String uuid,
    required int deliveredLabId,
    required double endMileage,
    required DateTime deliveredDate,
  }) async {
    final db = await _dbFuture;

    // Fetch the lab type using deliveredLabId
    final lab = await db.query(
      'lab',
      columns: ['lab_type'],
      where: 'id = ?',
      whereArgs: [deliveredLabId],
      limit: 1,
    );

    if (lab.isEmpty) {
      throw ArgumentError('Lab with id $deliveredLabId does not exist');
    }

    final labType = lab.first['lab_type'] as String;

    // Determine the sample_status based on the lab type
    String sampleStatus;
    switch (labType) {
      case 'PLATEFORME':
        sampleStatus = SampleStatus.receivedAtReferenceLab;
        break;
      case 'CAT':
        sampleStatus = SampleStatus.receivedAtTbLab;
        break;
      case 'DISTRICT':
        sampleStatus = SampleStatus.receivedAtDistrictLab;
        break;
      case 'RELAIS':
        sampleStatus = SampleStatus.receivedAtHub;
        break;
      default:
        sampleStatus = SampleStatus.receivedAtReferenceLab;
    }

    final data = {
      'delivered_lab_id': deliveredLabId,
      'end_mileage': endMileage,
      'delivered_date': deliveredDate.toIso8601String(),
      'sample_status': sampleStatus,
      'lastupdated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    };

    return db.update('sample', data, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<int> collectResultsAtLab({
    required String uuid,
    required int collectorUserId,
    required double resultStartMileage,
    required DateTime resultCollectionDate,
  }) async {
    final db = await _dbFuture;
    final data = {
      'result_collector': collectorUserId,
      'result_start_mileage': resultStartMileage,
      'result_collection_date': resultCollectionDate.toIso8601String(),
      'sample_status': SampleStatus.resultCollected,
      'lastupdated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    };
    return db.update('sample', data, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<int> depositResultsAtSite({
    required String uuid,
    required int siteId,
    required double resultEndMileage,
    required DateTime resultDeliveredDate,
  }) async {
    final db = await _dbFuture;
    final data = {
      'from_site_id': siteId,
      'result_end_mileage': resultEndMileage,
      'result_delivered_date': resultDeliveredDate.toIso8601String(),
      'sample_status': SampleStatus.resultOnSite,
      'lastupdated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    };
    return db.update('sample', data, where: 'uuid = ?', whereArgs: [uuid]);
  }

  // --- Labo ---
  Future<int> acknowledgeReceptionAtLab({
    required String uuid,
    required String labNumber,
    required String patientCode,
    required DateTime acceptedDate,
  }) async {
    final db = await _dbFuture;

    final data = {
      'lab_number': labNumber,
      'patient_identifier': patientCode,
      'accepted_date': acceptedDate.toIso8601String(),
      'sample_status': SampleStatus.acceptedAtReferenceLab,
      'lastupdated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    };
    return db.update('sample', data, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<int> rejectAtLab({
    required String uuid,
    required int rejectionTypeId,
    String? rejectionComment,
    required DateTime rejectionDate,
  }) async {
    final db = await _dbFuture;
    final data = {
      'rejection_type_id': rejectionTypeId,
      'rejection_comment': rejectionComment,
      'rejection_date': rejectionDate.toIso8601String(),
      'sample_status': SampleStatus.nonConform,
      'lastupdated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    };
    return db.update('sample', data, where: 'uuid = ?', whereArgs: [uuid]);
  }

  // --- Dashboard helpers ---
  Future<Map<String, int>> dashboardCounters() async {
    final db = await _dbFuture;
    Future<int> _countWhere(String where, List<Object?> args) async {
      // Correctly handle multiple arguments for a single column using 'IN'
      final inClause = List.filled(args.length, '?').join(', ');
      final r = await db.rawQuery(
        'SELECT COUNT(*) as c FROM sample WHERE ${where.replaceAll('?', inClause)}',
        args,
      );
      return (r.first['c'] as int?) ?? 0;
    }

    // Updated query calls using the IN clause
    final collected = await _countWhere('sample_status = ?', ['ON_TRANSIT']);
    final delivered = await _countWhere('sample_status IN (?)', [
      'RECEIVED_AT_REFERENCE_LAB',
      'RECEIVED_AT_HUB',
      'RECEIVED_AT_TB_LAB',
      'RECEIVED_AT_DISTRICT_LAB',
    ]);
    final received = await _countWhere('sample_status IN (?)', [
      'ACCEPTED_AT_REFERENCE_LAB',
      'ACCEPTED_AT_HUB',
      'ACCEPTED_AT_TB_LAB',
      'ACCEPTED_AT_DISTRICT_LAB',
    ]);
    // ANALYSIS_FAILED EXCLU ici : il a son propre compteur `analysisFailed`
    // ci-dessous. Avant ce fix, l'agrégat `resultReady + analysisFailed`
    // utilisé dans les badges double-comptait les échecs.
    // Cohérent avec le backend (`result_ready` = analysis_released_date NOT NULL,
    // qui ne capture pas les échecs).
    final resultReady = await _countWhere('sample_status = ?', [
      'ANALYSIS_DONE',
    ]);
    final resultCollected = await _countWhere('sample_status = ?', [
      'RESULT_COLLECTED',
    ]);
    final resultDeposited = await _countWhere('sample_status = ?', [
      'RESULT_ON_SITE',
    ]);
    final rejected = await _countWhere('sample_status = ?', ['NON_CONFORM']);
    final analysisFailed = await _countWhere('sample_status = ?', ['ANALYSIS_FAILED']);

    return {
      'collected': collected,
      'delivered': delivered,
      'received': received,
      'resultReady': resultReady,
      'resultCollected': resultCollected,
      'resultDeposited': resultDeposited,
      'rejected': rejected,
      'analysisFailed': analysisFailed,
    };
  }

  Future<List<Map<String, Object?>>> badgeCountsByType(String status) async {
    final db = await _dbFuture;
    return db.rawQuery(
      '''
      SELECT sample_type, COUNT(*) AS cnt
      FROM sample
      WHERE sample_status = ?
      GROUP BY sample_type
      ORDER BY cnt DESC
    ''',
      [status],
    );
  }

  Future<List<Sample>> listByStatus({
    required String status,
    String? type,
    String? search,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _dbFuture;
    final where = <String>[];
    final args = <Object?>[];
    where.add('sample_status = ?');
    args.add(status);
    if (type != null && type.isNotEmpty) {
      where.add('sample_type = ?');
      args.add(type);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add(
        '(sample_identifier LIKE ? OR patient_identifier LIKE ? OR lab_number LIKE ?)',
      );
      final q = '%${search.trim()}%';
      args.addAll([q, q, q]);
    }
    final rows = await db.query(
      'sample',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'lastupdated_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Sample.fromMap).toList();
  }
}

extension SampleDaoLists on SampleDao {
  /// Compte par type d’échantillon pour un statut donné
  /// Renvoie: [{ 'sample_type': 'CV', 'total': 12 }, ...] trié par type
  Future<List<Map<String, Object?>>> countsByType({
    required String status,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery(
      '''
      SELECT COALESCE(sample_type, 'Autre') AS sample_type, COUNT(*) AS total
      FROM sample
      WHERE sample_status = ?
      GROUP BY sample_type
      ORDER BY sample_type ASC
    ''',
      [status],
    );
  }

  /// Liste des échantillons d’un type et statut donné, avec recherche optionnelle
  Future<List<Sample>> listByTypeAndStatus({
    required String type,
    String? status,
    List<String>? statuses,
    String? query,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await AppDatabase.instance.database;
    final where = StringBuffer();
    final args = <Object?>[];

    // Gérer la clause de statut de manière dynamique
    if (statuses != null && statuses.isNotEmpty) {
      final placeholders = List.filled(statuses.length, '?').join(', ');
      where.write('sample_status IN ($placeholders)');
      args.addAll(statuses);
    } else if (status != null) {
      where.write('sample_status = ?');
      args.add(status);
    } else {
      // Si aucun statut n'est fourni, on ne filtre pas sur le statut
      // La clause where peut rester vide pour le moment
    }

    // Ajouter la condition sur le type d'échantillon
    if (where.isNotEmpty) {
      where.write(' AND ');
    }
    where.write('COALESCE(sample_type, \'Autre\') = ?');
    args.add(type);

    // Ajouter la condition de recherche si une requête est fournie
    if (query != null && query.trim().isNotEmpty) {
      where.write(
        ' AND (patient_identifier LIKE ? OR sample_identifier LIKE ?)',
      );
      final q = '%${query.trim()}%';
      args.addAll([q, q]);
    }

    // Construire et exécuter la requête
    final rows = await db.query(
      'sample',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((m) => Sample.fromMap(m)).toList();
  }
}

extension SampleDaoActions on SampleDao {
  /// Récupérer un échantillon par id
  Future<Sample?> findById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'sample',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Sample.fromMap(rows.first);
  }

  /// Supprimer un échantillon par id
  Future<int> deleteById(int id) async {
    final db = await AppDatabase.instance.database;
    return db.delete('sample', where: 'id=?', whereArgs: [id]);
  }

  /// Mettre à jour partiellement un échantillon (map de champs -> valeurs).
  /// N'inclure dans [fields] que les colonnes à modifier (ex: {'from_site_id': 12, 'start_mileage': 1234}).
  Future<int> updateFields(int id, Map<String, Object?> fields) async {
    if (fields.isEmpty) return 0;
    // auto-maj du lastupdated_at et dirty
    fields['lastupdated_at'] = DateTime.now().toIso8601String();
    fields['dirty'] = 1;
    final db = await AppDatabase.instance.database;
    return db.update('sample', fields, where: 'id=?', whereArgs: [id]);
  }
}

extension SampleDaoDeposits on SampleDao {
  /// Dépôt au labo choisi pour plusieurs échantillons.
  /// - sample_status -> DELIVERED
  /// - delivered_lab_id -> [labId]
  /// - delivered_date -> [deliveredDateIso] (ex: DateTime.now().toIso8601String())
  /// - end_mileage -> [endMileage] si fourni
  /// Renvoie le nombre de lignes mises à jour.
  Future<int> depositToLabMany(
    Set<int> ids, {
    required int labId,
    required String deliveredDateIso,
    int? endMileage,
  }) async {
    if (ids.isEmpty) return 0;

    final db = await AppDatabase.instance.database;

    // Fetch the lab type using deliveredLabId

    final lab = await db.query(
      'lab',
      columns: ['lab_type'],
      where: 'id = ?',
      whereArgs: [labId],
      limit: 1,
    );

    if (lab.isEmpty) {
      throw ArgumentError('Lab with id $labId does not exist');
    }

    final labType = lab.first['lab_type'] as String;

    // Determine the sample_status based on the lab type
    String sampleStatus;
    switch (labType) {
      case 'PLATEFORME':
        sampleStatus = SampleStatus.receivedAtReferenceLab;
        break;
      case 'CAT':
        sampleStatus = SampleStatus.receivedAtTbLab;
        break;
      case 'DISTRICT':
        sampleStatus = SampleStatus.receivedAtDistrictLab;
        break;
      case 'RELAIS':
        sampleStatus = SampleStatus.receivedAtHub;
        break;
      default:
        sampleStatus = SampleStatus.receivedAtReferenceLab;
    }

    final placeholders = List.filled(ids.length, '?').join(',');

    // On met end_mileage seulement si fourni, sinon on le laisse tel quel.
    final setEndMileage = endMileage == null ? '' : ', end_mileage = ?';

    final args = <Object?>[
      sampleStatus,
      labId,
      deliveredDateIso,
      ...((endMileage == null) ? const <Object?>[] : <Object?>[endMileage]),
      ...ids,
    ];

    final sql =
        '''
UPDATE sample
SET
  sample_status = ?,
  delivered_lab_id = ?,
  delivered_date = ?$setEndMileage,
  lastupdated_at = CURRENT_TIMESTAMP,
  dirty = 1
WHERE id IN ($placeholders)
''';

    return db.rawUpdate(sql, args);
  }

  /// Variante pour un seul échantillon (pratique côté fiche détaillée).
  Future<int> depositToLabOne(
    int id, {
    required int labId,
    required String deliveredDateIso,
    int? endMileage,
  }) async {
    return depositToLabMany(
      {id},
      labId: labId,
      deliveredDateIso: deliveredDateIso,
      endMileage: endMileage,
    );
  }
}

extension SampleDaoDepositEdit on SampleDao {
  /// Modifier un dépôt (sélection unique — convoyeur)
  /// Les champs non fournis ne sont pas modifiés.
  Future<int> updateDeposit({
    required int id,
    int? labId,
    String? patientCode,
    String? deliveredDateIso,
    int? endMileage,
  }) async {
    final db = await AppDatabase.instance.database;

    String sampleStatus = await _getReceivedSampleStatusByLabId(labId ?? 0);

    final fields = <String, Object?>{
      if (labId != null) 'delivered_lab_id': labId,
      if (labId != null) 'sample_status': sampleStatus,
      if (deliveredDateIso != null) 'delivered_date': deliveredDateIso,
      if (endMileage != null) 'end_mileage': endMileage,
      if (patientCode != null) 'patient_identifier': patientCode,
      'lastupdated_at': DateTime.now().toIso8601String(),
      'dirty': 1,
    };
    if (fields.length <= 2) return 0; // rien à mettre à jour
    return db.update('sample', fields, where: 'id = ?', whereArgs: [id]);
  }
}

extension SampleDaoAccept on SampleDao {
  /// Accepter un échantillon (tech labo)
  /// - sample_status -> RECEIVED
  /// - lab_number -> requis
  /// - accepted_date -> requis
  Future<int> acceptOne({
    required int id,
    required String labNumber,
    required String patientCode,
    required String acceptedDateIso,
  }) async {
    final db = await AppDatabase.instance.database;
    Sample existingSample = (await findById(id))!;
    String sampleStatus = await _getAcceptedSampleStatusByLabId(
      existingSample.deliveredLabId ?? 0,
    );

    return db.update(
      'sample',
      {
        'sample_status': sampleStatus,
        'lab_number': labNumber,
        'patient_identifier': patientCode,
        'accepted_date': acceptedDateIso,
        'lastupdated_at': DateTime.now().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

extension SampleDaoReject on SampleDao {
  /// Rejeter (tech labo) — peut être multiple
  /// - sample_status -> REJECTED
  /// - rejection_type_id, rejection_comment, rejection_date
  Future<int> rejectMany({
    required Set<int> ids,
    required int rejectionTypeId,
    String? comment,
    required String rejectionDateIso,
  }) async {
    if (ids.isEmpty) return 0;
    final db = await AppDatabase.instance.database;

    final placeholders = List.filled(ids.length, '?').join(',');
    final args = <Object?>[
      'NON_CONFORM',
      rejectionTypeId,
      comment,
      rejectionDateIso,
      ...ids,
    ];

    final sql =
        '''
UPDATE sample
SET sample_status = ?,
    rejection_type_id = ?,
    rejection_comment = ?,
    rejection_date = ?,
    lastupdated_at = CURRENT_TIMESTAMP,
    dirty = 1
WHERE id IN ($placeholders)
''';
    return db.rawUpdate(sql, args);
  }
}

extension SampleDaoResults on SampleDao {
  /// Marque plusieurs échantillons comme "résultats collectés"
  /// - sample_status -> RESULT_COLLECTED
  /// - result_collection_date -> date ISO fournie
  /// Renvoie le nombre de lignes mises à jour.
  Future<int> collectResultsMany(
    Set<int> ids, {
    required String collectedDateIso,
  }) async {
    if (ids.isEmpty) return 0;
    final db = await AppDatabase.instance.database;

    final placeholders = List.filled(ids.length, '?').join(',');
    final args = <Object?>['RESULT_COLLECTED', collectedDateIso, ...ids];

    final sql =
        '''
UPDATE sample
SET sample_status = ?,
    result_collection_date = ?,
    lastupdated_at = CURRENT_TIMESTAMP,
    dirty = 1
WHERE id IN ($placeholders)
''';
    return db.rawUpdate(sql, args);
  }
}

extension SampleDaoResultReady on SampleDao {
  /// Comptes par labo des échantillons dont le résultat est prêt.
  /// Renvoie: [{ 'lab_id': 12, 'total': 34 }, ...]
  Future<List<Map<String, Object?>>> countsReadyByLab() async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT destination_lab_id AS lab_id, COUNT(*) AS total
      FROM sample
      WHERE sample_status = 'ANALYSIS_DONE'
        AND destination_lab_id IS NOT NULL
      GROUP BY destination_lab_id
      ORDER BY total DESC
    ''');
  }

  /// Comptes par type pour un labo donné (résultats prêts).
  /// Renvoie: [{ 'sample_type': 'CV', 'total': 10 }, ...]
  Future<List<Map<String, Object?>>> countsReadyByTypeForLab(int labId) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery(
      '''
      SELECT COALESCE(sample_type, 'Autre') AS sample_type, COUNT(*) AS total
      FROM sample
      WHERE sample_status = 'ANALYSIS_DONE'
        AND destination_lab_id = ?
      GROUP BY COALESCE(sample_type, 'Autre')
      ORDER BY sample_type ASC
    ''',
      [labId],
    );
  }

  /// Liste des échantillons RESULT_READY pour un labo + type, recherche optionnelle.
  Future<List<Sample>> listReadyByLabAndType({
    required int labId,
    required String type, // utiliser 'Autre' pour NULL/vides
    String? query,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await AppDatabase.instance.database;
    final args = <Object?>[labId];

    final sb = StringBuffer()
      ..writeln('SELECT * FROM sample')
      ..writeln('WHERE sample_status = \'ANALYSIS_DONE\'')
      ..writeln('  AND destination_lab_id = ?');

    if (type == 'Autre') {
      sb.writeln('  AND (sample_type IS NULL OR TRIM(sample_type) = \'\')');
    } else {
      sb.writeln('  AND COALESCE(sample_type, \'Autre\') = ?');
      args.add(type);
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      sb
        ..writeln(
          '  AND (patient_identifier LIKE ? OR sample_identifier LIKE ?)',
        )
        ..writeln(''); // rien, juste pour lisibilité
      args.addAll([q, q]);
    }

    sb.writeln('ORDER BY created_at DESC LIMIT ? OFFSET ?');
    args.addAll([limit, offset]);

    final rows = await db.rawQuery(sb.toString(), args);
    return rows.map((m) => Sample.fromMap(m)).toList();
  }

  // lib/data/db/sample_dao.dart (ajoute dans la classe SampleDao)

  Future<int> markAnalysisReady({
    required int id,
    String? analysisStartedDate,
    String? analysisCompletedDate,
    required String analysisReleasedDate,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.update(
      'sample',
      {
        'analysis_started_date': analysisStartedDate,
        'analysis_completed_date': analysisCompletedDate,
        'analysis_released_date': analysisReleasedDate,
        'sample_status': SampleStatus.analysisDone, // 'ANALYSIS_DONE'
        'dirty': 1,
        'lastupdated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marque "analyse échouée" pour plusieurs IDs
  Future<int> markAnalysisFailedMany(
    List<int> ids, {
    String? analysisCompletedDate,
  }) async {
    if (ids.isEmpty) return 0;
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.rawUpdate(
      '''
    UPDATE sample
    SET sample_status = ?,
        analysis_completed_date = COALESCE(?, analysis_completed_date),
        dirty = 1,
        lastupdated_at = ?
    WHERE id IN ($placeholders)
    ''',
      [
        SampleStatus.analysisFailed, // 'ANALYSIS_FAILED'
        analysisCompletedDate,
        DateTime.now().toIso8601String(),
        ...ids,
      ],
    );
  }

  /// Marque un lot d'échantillons « résultat prêt » avec les mêmes dates.
  /// La date de validation biologique est obligatoire ; la date de fin
  /// d'analyse est optionnelle (valeur existante conservée si null).
  Future<int> markResultReadyMany(
    List<int> ids, {
    required String analysisReleasedDate,
    String? analysisCompletedDate,
  }) async {
    if (ids.isEmpty) return 0;
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.rawUpdate(
      '''
    UPDATE sample
    SET sample_status = ?,
        analysis_completed_date = COALESCE(?, analysis_completed_date),
        analysis_released_date = ?,
        dirty = 1,
        lastupdated_at = ?
    WHERE id IN ($placeholders)
    ''',
      [
        SampleStatus.analysisDone, // 'ANALYSIS_DONE'
        analysisCompletedDate,
        analysisReleasedDate,
        DateTime.now().toIso8601String(),
        ...ids,
      ],
    );
  }
}

extension SampleDaoUtils on SampleDao {
  Future<int> execRaw(String sql, List<Object?> args) async {
    final db = await AppDatabase.instance.database;
    return db.rawUpdate(sql, args);
  }
}

// ===== Résultats récupérés (avant dépot sur site) =====
extension SampleDaoResultCollectedBySite on SampleDao {
  /// Comptes par site (from_site_id) pour les échantillons RESULT_COLLECTED
  /// Renvoie: [{ site_id, total }]
  Future<List<Map<String, Object?>>> countsCollectedBySite() async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT COALESCE(from_site_name, 'Site Inconnu') AS site_name, COUNT(*) AS total
      FROM sample
      WHERE sample_status = 'RESULT_COLLECTED'
      AND from_site_name IS NOT NULL
      GROUP BY from_site_name
      ORDER BY total DESC
    ''');
  }

  /// Liste des échantillons RESULT_COLLECTED pour un site donné (+ recherche optionnelle)
  Future<List<Sample>> listCollectedBySite({
    int? siteId,
    String? siteName,
    String? query,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await AppDatabase.instance.database;
    final args = <Object?>[siteId, siteName];

    final sb = StringBuffer()
      ..writeln('SELECT * FROM sample')
      ..writeln('WHERE sample_status = \'RESULT_COLLECTED\'')
      ..writeln('  AND (from_site_id = ? OR from_site_name = ?)');

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      sb.writeln(
        '  AND (patient_identifier LIKE ? OR sample_identifier LIKE ?)',
      );
      args.addAll([q, q]);
    }

    sb.writeln('ORDER BY created_at DESC LIMIT ? OFFSET ?');
    args.addAll([limit, offset]);

    final rows = await db.rawQuery(sb.toString(), args);
    return rows.map((m) => Sample.fromMap(m)).toList();
  }

  /// Déposer des résultats (sélection multiple)
  /// - sample_status -> RESULT_DELIVERED
  /// - result_delivered_date -> ISO fourni
  /// - result_end_mileage -> kilométrage fourni (optionnel)
  Future<int> depositResultsMany(
    Set<int> ids, {
    required String deliveredDateIso,
    int? endMileage,
  }) async {
    if (ids.isEmpty) return 0;
    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');

    if (endMileage == null) {
      return db.rawUpdate(
        '''
        UPDATE sample
        SET sample_status = 'RESULT_ON_SITE',
            result_delivered_date = ?,
            lastupdated_at = CURRENT_TIMESTAMP,
            dirty = 1
        WHERE id IN ($placeholders)
      ''',
        [deliveredDateIso, ...ids],
      );
    } else {
      return db.rawUpdate(
        '''
        UPDATE sample
        SET sample_status = 'RESULT_ON_SITE',
            result_delivered_date = ?,
            result_end_mileage = ?,
            lastupdated_at = CURRENT_TIMESTAMP,
            dirty = 1
        WHERE id IN ($placeholders)
      ''',
        [deliveredDateIso, endMileage, ...ids],
      );
    }
  }
}

extension SyncHelpers on SampleDao {
  Future<Database> get _db async => AppDatabase.instance.database;

  /// Retourne tous les éléments non synchronisés (dirty = 1)
  Future<List<Sample>> listDirty() async {
    final db = await _db;
    final rows = await db.query('sample', where: 'dirty = 1');
    return rows.map((m) => Sample.fromMap(m)).toList();
  }

  /// Marque comme synchronisés à partir du mapping uuid -> externalId renvoyé par le serveur.
  /// Remet aussi à zéro les drapeaux d'erreur de sync pour les rows concernées.
  Future<void> markPushed(Map<String, String> uuidToExternalId) async {
    if (uuidToExternalId.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    uuidToExternalId.forEach((uuid, externalId) {
      batch.update(
        'sample',
        {
          'external_id': externalId,
          'dirty': 0,
          'lastupdated_at': DateTime.now().toIso8601String(),
          'last_sync_attempt': DateTime.now().toIso8601String(),
          'last_sync_error': null,
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    });
    await batch.commit(noResult: true);
  }

  /// Marque les rows comme ayant échoué au push (dirty reste à 1, on conserve
  /// le message d'erreur pour diagnostic UI).
  Future<void> markPushFailed(List<String> uuids, String errorMessage) async {
    if (uuids.isEmpty) return;
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final uuid in uuids) {
      batch.update(
        'sample',
        {
          'last_sync_attempt': now,
          'last_sync_error': errorMessage,
        },
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Nombre d'items en attente de synchronisation.
  Future<int> countDirty() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM sample WHERE dirty = 1');
    final v = rows.isEmpty ? null : rows.first['c'];
    return (v is int) ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  }

  /// Nombre de conflits non résolus.
  Future<int> countConflicts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sample WHERE has_conflict = 1',
    );
    final v = rows.isEmpty ? null : rows.first['c'];
    return (v is int) ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
  }

  /// Retourne tous les samples actuellement en conflit, triés du plus ancien
  /// au plus récent (utilisé par l'écran de résolution).
  Future<List<Sample>> listConflicts() async {
    final db = await _db;
    final rows = await db.query(
      'sample',
      where: 'has_conflict = 1',
      orderBy: 'lastupdated_at ASC',
    );
    return rows.map((m) => Sample.fromMap(m)).toList();
  }

  /// Résout un conflit en gardant la version locale : on lève le flag
  /// [has_conflict] mais on conserve [dirty=1] pour que le prochain push
  /// renvoie la version locale au serveur (qui écrasera la version serveur).
  Future<void> resolveConflictKeepLocal(String uuid) async {
    final db = await _db;
    await db.update(
      'sample',
      {
        'has_conflict': 0,
        // dirty reste à 1 — le push le renverra au serveur
        'last_sync_error': null,
        'lastupdated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid = ? AND has_conflict = 1',
      whereArgs: [uuid],
    );
  }

  /// Résout un conflit en acceptant la version serveur : on récupère
  /// les champs serveur (passés en paramètre depuis le DTO) et on les
  /// applique en écrasant les modifs locales. Le row redevient propre
  /// (dirty=0, has_conflict=0).
  ///
  /// `serverData` doit avoir le format du payload pull serveur (mêmes clés
  /// que `_serverToLocalMap`).
  Future<void> resolveConflictAcceptServer(String uuid,
      Map<String, dynamic> serverData) async {
    final db = await _db;
    final m = _serverToLocalMap(serverData);
    await db.update(
      'sample',
      {
        ...m,
        'dirty': 0,
        'has_conflict': 0,
        'last_sync_error': null,
        'server_version': serverData['version'],
        'lastupdated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  /// Variante d'accept-server sans appel réseau : si on n'a pas le payload
  /// serveur sous la main (les champs serveur ne sont pas conservés
  /// séparément), on se contente d'effacer le flag conflit et de marquer
  /// dirty=0 pour que le prochain pull réécrive cette ligne avec les
  /// données serveur.
  Future<void> resolveConflictDiscardLocal(String uuid) async {
    final db = await _db;
    // On force dirty=0 → upsertFromServer pourra réécrire au prochain pull.
    // On supprime le row pour forcer un re-pull complet de cette ligne.
    await db.delete(
      'sample',
      where: 'uuid = ? AND has_conflict = 1',
      whereArgs: [uuid],
    );
  }

  /// Recherche un sample par UUID (utile pour la résolution de conflit).
  Future<Sample?> findByUuid(String uuid) async {
    final db = await _db;
    final rows = await db.query('sample',
        where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (rows.isEmpty) return null;
    return Sample.fromMap(rows.first);
  }

  /// Upsert depuis l'objet serveur (clé: external_id).
  ///
  /// Règle de protection contre la perte de données : si un row local existe
  /// déjà avec [dirty]=1 (= modification locale non encore poussée), on
  /// **n'écrase pas** ses champs. On flague à la place [has_conflict]=1 pour
  /// que l'UI puisse alerter l'utilisateur. Le row dirty sera poussé au
  /// prochain run, ce qui réconciliera côté serveur.
  ///
  /// Retourne true si l'opération a été appliquée, false si elle a été
  /// short-circuitée pour cause de conflit.
  Future<bool> upsertFromServer(Map<String, dynamic> server) async {
    final db = await _db;

    final externalId = (server['external_id'] ?? server['id'])?.toString();
    if (externalId == null || externalId.isEmpty) return false;

    final m = _serverToLocalMap(server);
    final serverVersion = server['version'];

    // Cherche d'abord par external_id, puis par uuid en fallback (un row local
    // créé offline n'a pas encore d'external_id avant son premier push).
    var rows = await db.query(
      'sample',
      where: 'external_id = ?',
      whereArgs: [externalId],
      limit: 1,
    );
    if (rows.isEmpty && m['uuid'] != null) {
      rows = await db.query(
        'sample',
        where: 'uuid = ?',
        whereArgs: [m['uuid']],
        limit: 1,
      );
    }

    if (rows.isEmpty) {
      await db.insert('sample', {
        ...m,
        'external_id': externalId,
        'dirty': 0,
        'has_conflict': 0,
        'server_version': serverVersion,
      });
      return true;
    }

    final existing = rows.first;
    final isDirty = (existing['dirty'] as int? ?? 0) == 1;

    if (isDirty) {
      // Protection : on ne touche pas aux champs métier, on lie juste
      // l'external_id (si manquant) et on flague le conflit.
      await db.update(
        'sample',
        {
          'external_id': externalId,
          'has_conflict': 1,
          'server_version': serverVersion,
        },
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
      return false;
    }

    // Row local clean → on accepte la version serveur.
    await db.update(
      'sample',
      {
        ...m,
        'external_id': externalId,
        'dirty': 0,
        'has_conflict': 0,
        'server_version': serverVersion,
        'lastupdated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [existing['id']],
    );
    return true;
  }

  Map<String, Object?> _serverToLocalMap(Map<String, dynamic> s) {
    // Adapter si les champs serveur diffèrent
    return {
      'uuid': s['uuid'],
      'sample_conveyor': s['sample_conveyor'],
      'referring_sample_id': s['referring_sample_id'],
      'from_site_code': s['from_site_code'],
      'from_site_name': s['from_site_name'],
      'from_site_id': s['from_site_id'],
      'destination_lab_id': s['destination_lab_id'],
      'delivered_lab_id': s['delivered_lab_id'],
      'sample_identifier': s['sample_identifier'],
      'patient_identifier': s['patient_identifier'],
      'sample_type': s['sample_type'],
      'sample_nature': s['sample_nature'],
      'start_mileage': s['start_mileage'],
      'end_mileage': s['end_mileage'],
      'result_start_mileage': s['result_start_mileage'],
      'result_end_mileage': s['result_end_mileage'],
      'collection_date': s['collection_date'],
      'pickup_date': s['pickup_date'],
      'delivered_date': s['delivered_date'],
      'accepted_date': s['accepted_date'],
      'lab_number': s['lab_number'],
      'sample_status': s['sample_status'],
      'analysis_started_date': s['analysis_started_date'],
      'analysis_completed_date': s['analysis_completed_date'],
      'analysis_released_date': s['analysis_released_date'],
      'result_collection_date': s['result_collection_date'],
      'result_delivered_date': s['result_delivered_date'],
      'result_collector': s['result_collector'],
      'rejection_type_id': s['rejection_type_id'],
      'rejection_comment': s['rejection_comment'],
      'rejection_date': s['rejection_date'],
      // created_at: on ne l’écrase pas forcément si local déjà créé.
    }..removeWhere((k, v) => v == null);
  }

  Future<String> _getReceivedSampleStatusByLabId(int labId) async {
    final db = await _dbFuture;

    // Fetch the lab type using labId
    final lab = await db.query(
      'lab',
      columns: ['lab_type'],
      where: 'id = ?',
      whereArgs: [labId],
      limit: 1,
    );

    if (lab.isEmpty) {
      throw ArgumentError('Lab with id $labId does not exist');
    }

    final labType = lab.first['lab_type'] as String;

    // Determine the sample_status based on the lab type
    switch (labType) {
      case 'PLATEFORME':
        return SampleStatus.receivedAtReferenceLab;
      case 'CAT':
        return SampleStatus.receivedAtTbLab;
      case 'DISTRICT':
        return SampleStatus.receivedAtDistrictLab;
      case 'RELAIS':
        return SampleStatus.receivedAtHub;
      default:
        return SampleStatus.receivedAtReferenceLab;
    }
  }

  Future<String> _getAcceptedSampleStatusByLabId(int labId) async {
    final db = await _dbFuture;

    // Fetch the lab type using labId
    final lab = await db.query(
      'lab',
      columns: ['lab_type'],
      where: 'id = ?',
      whereArgs: [labId],
      limit: 1,
    );

    if (lab.isEmpty) {
      throw ArgumentError('Lab with id $labId does not exist');
    }

    final labType = lab.first['lab_type'] as String;

    // Determine the sample_status based on the lab type
    switch (labType) {
      case 'PLATEFORME':
        return SampleStatus.acceptedAtReferenceLab;
      case 'CAT':
        return SampleStatus.acceptedAtTbLab;
      case 'DISTRICT':
        return SampleStatus.acceptedAtDistrictLab;
      case 'RELAIS':
        return SampleStatus.acceptedAtHub;
      default:
        return SampleStatus.acceptedAtReferenceLab;
    }
  }
}
