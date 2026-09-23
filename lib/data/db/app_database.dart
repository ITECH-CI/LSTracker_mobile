import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _dbName = 'sample_tracker.db';
  // v4: ajoute les colonnes de robustesse sync sur la table sample
  //   - has_conflict       : 1 si pull a détecté un conflit avec un dirty local
  //   - last_sync_attempt  : ISO timestamp du dernier essai de push
  //   - last_sync_error    : message d'erreur du dernier essai de push (null si OK)
  //   - server_version     : version optimiste serveur (préparation conflits)
  //
  // v5: index manquants pour la perf des grosses bases (5k–10k samples) :
  //   - idx_sample_created_at        : ORDER BY created_at DESC sur les listes paginées
  //   - idx_sample_lastupdated_at    : ORDER BY lastupdated_at ASC pour les dirty
  //   - idx_sample_external_id       : lookup au pull (upsertFromServer, très fréquent)
  //   - idx_sample_dirty_lastupdated : composite pour les push (dirty=1 + tri temporel)
  static const _dbVersion = 6;

  static final AppDatabase instance = AppDatabase._internal();
  AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  /// **Pour les tests uniquement.** Injecte une [Database] déjà ouverte
  /// (typiquement en mémoire via sqflite_common_ffi) pour que tous les
  /// DAOs qui passent par [AppDatabase.instance.database] tapent sur
  /// cette base au lieu d'essayer d'ouvrir le fichier sur disque (qui
  /// échouerait en `flutter test` faute de `path_provider`).
  ///
  /// À appeler dans `setUp()` après avoir initialisé `databaseFactory`.
  /// Réinitialise via [resetForTests] en `tearDown()`.
  @visibleForTesting
  set databaseForTests(Database db) => _db = db;

  /// Ferme et oublie la DB courante. À appeler en `tearDown()` pour
  /// que le test suivant reparte d'une base propre.
  @visibleForTesting
  Future<void> resetForTests() async {
    final cur = _db;
    _db = null;
    if (cur != null && cur.isOpen) await cur.close();
  }

  /// Crée le schéma complet de la dernière version (`_dbVersion`) sur
  /// la base fournie. Public pour permettre aux helpers de test de
  /// préparer une DB en mémoire identique à la prod.
  @visibleForTesting
  Future<void> createSchemaForTesting(Database db) async {
    await _createSchema(db);
  }

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await _createMetadataTables(db);
        }
        if (oldV < 3) {
          // v3: ajoute la table circuit_site et hydrate depuis site.circuit_id si présent
          await _createCircuitSiteTable(db);
          // Hydratation initiale depuis l'ancien lien 1-N (si existait)
          // (ignore les doublons et les NULL)
          await db.execute('''
INSERT OR IGNORE INTO circuit_site (circuit_id, site_id)
SELECT circuit_id, id FROM site WHERE circuit_id IS NOT NULL;
''');
        }
        if (oldV < 4) {
          // v4: colonnes de robustesse sync sur la table sample.
          await _addSyncRobustnessColumns(db);
        }
        if (oldV < 5) {
          // v5: index de perf manquants pour grosses bases.
          await _addPerformanceIndexes(db);
        }
        if (oldV < 6) {
          // v6: lab.selectable — la table contient tous les labos (affichage
          // des noms), seuls les sélectionnables sont proposés à la saisie.
          await _addLabSelectableColumn(db);
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE metadata_version (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  version INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);
''');
    await db.insert('metadata_version', {
      'id': 1,
      'version': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    await _createMetadataTables(db);

    await db.execute('''
CREATE TABLE sample (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  external_id TEXT,
  uuid TEXT UNIQUE NOT NULL,
  sample_conveyor INTEGER,
  referring_sample_id INTEGER,
  from_site_code TEXT,
  from_site_name TEXT,
  from_site_id INTEGER,
  destination_lab_id INTEGER,
  delivered_lab_id INTEGER,
  sample_identifier TEXT,
  patient_identifier TEXT,
  sample_type TEXT,
  sample_nature TEXT,
  start_mileage REAL,
  end_mileage REAL,
  result_start_mileage REAL,
  result_end_mileage REAL,
  collection_date TEXT,
  pickup_date TEXT,
  delivered_date TEXT,
  accepted_date TEXT,
  lab_number TEXT,
  sample_status TEXT,
  analysis_started_date TEXT,
  analysis_completed_date TEXT,
  analysis_released_date TEXT,
  result_collection_date TEXT,
  result_delivered_date TEXT,
  result_collector INTEGER,
  rejection_type_id INTEGER,
  rejection_comment TEXT,
  rejection_date TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  lastupdated_at TEXT,
  dirty INTEGER DEFAULT 1
);
''');

    await db.execute(
      'CREATE INDEX idx_sample_status ON sample(sample_status);',
    );
    await db.execute('CREATE INDEX idx_sample_type ON sample(sample_type);');
    await db.execute(
      'CREATE INDEX idx_sample_delivered_lab ON sample(delivered_lab_id);',
    );
    await db.execute(
      'CREATE INDEX idx_sample_destination_lab ON sample(destination_lab_id);',
    );
    await db.execute(
      'CREATE INDEX idx_sample_from_site ON sample(from_site_id);',
    );
    await db.execute('CREATE INDEX idx_sample_dirty ON sample(dirty);');

    // v4 columns also created on fresh installs
    await _addSyncRobustnessColumns(db);
    // v5 indexes also created on fresh installs
    await _addPerformanceIndexes(db);
  }

  /// v5: index de perf pour les listes paginées et le pull/push.
  /// Tous en IF NOT EXISTS pour rester sûrs lors d'un upgrade partiel.
  Future<void> _addLabSelectableColumn(Database db) async {
    // Une base montée depuis v1 a déjà la colonne (créée par
    // _createMetadataTables en v2) : ne l'ajouter que si elle manque.
    final cols = await db.rawQuery('PRAGMA table_info(lab)');
    if (cols.any((c) => c['name'] == 'selectable')) return;
    await db.execute(
      'ALTER TABLE lab ADD COLUMN selectable INTEGER NOT NULL DEFAULT 1',
    );
  }

  Future<void> _addPerformanceIndexes(Database db) async {
    // ORDER BY created_at DESC sur les listes paginées (sample_list,
    // results_ready, etc.). Sans cet index, SQLite trie 10k lignes en
    // mémoire à chaque page → loader visible.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_created_at ON sample(created_at);',
    );
    // ORDER BY lastupdated_at ASC dans getDirtySamples().
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_lastupdated_at ON sample(lastupdated_at);',
    );
    // Lookup au pull (upsertFromServer) — appelé pour CHAQUE sample reçu.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_external_id ON sample(external_id);',
    );
    // Composite (dirty, lastupdated_at) pour le push : filtre + tri d'un coup.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_dirty_lastupdated ON sample(dirty, lastupdated_at);',
    );
  }

  /// v4: adds sync-robustness columns to the {@code sample} table.
  /// Safe to call on a fresh DB (uses IF NOT EXISTS via best-effort checks)
  /// or as an upgrade step from v3.
  Future<void> _addSyncRobustnessColumns(Database db) async {
    // SQLite < 3.35 does not support ADD COLUMN IF NOT EXISTS, so we probe
    // the schema and add what is missing.
    final existing = <String>{};
    final rows = await db.rawQuery('PRAGMA table_info(sample)');
    for (final r in rows) {
      final name = r['name'];
      if (name is String) existing.add(name);
    }

    Future<void> addIfMissing(String column, String typeAndDefault) async {
      if (!existing.contains(column)) {
        await db.execute('ALTER TABLE sample ADD COLUMN $column $typeAndDefault');
      }
    }

    await addIfMissing('has_conflict', 'INTEGER NOT NULL DEFAULT 0');
    await addIfMissing('last_sync_attempt', 'TEXT');
    await addIfMissing('last_sync_error', 'TEXT');
    await addIfMissing('server_version', 'INTEGER');

    // Index dédié pour repérer rapidement les conflits.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_has_conflict ON sample(has_conflict);',
    );
  }

  Future<void> _createMetadataTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS lab (
  id INTEGER PRIMARY KEY,
  name TEXT,
  lab_type TEXT,
  selectable INTEGER NOT NULL DEFAULT 1
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS circuit (
  id INTEGER PRIMARY KEY,
  name TEXT
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS site (
  id INTEGER PRIMARY KEY,
  name TEXT,
  dhis_code TEXT,
  circuit_id INTEGER
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS rejection_type (
  id INTEGER PRIMARY KEY,
  name TEXT
);
''');

    await _createCircuitSiteTable(db);

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_site_circuit ON site(circuit_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lab_type ON lab(lab_type);',
    );
  }

  Future<void> _createCircuitSiteTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS circuit_site (
  circuit_id INTEGER NOT NULL,
  site_id INTEGER NOT NULL,
  PRIMARY KEY (circuit_id, site_id)
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_circuit_site_c ON circuit_site(circuit_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_circuit_site_s ON circuit_site(site_id);',
    );
  }
}

Future<void> ensureMetadataSchema() async {
  final db = await AppDatabase.instance.database;
  // idempotent calls already in _createMetadataTables; ensure version row exists
  final cur = await db.query('metadata_version', where: 'id = 1', limit: 1);
  if (cur.isEmpty) {
    await db.insert('metadata_version', {
      'id': 1,
      'version': 0,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
