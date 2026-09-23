import 'package:flutter_test/flutter_test.dart';
import 'package:lstracker/data/db/sample_dao.dart';
import 'package:lstracker/data/models/sample.dart';
import 'package:lstracker/utils/custom_date_utils.dart';

import 'helpers/test_db.dart';

void main() {
  group('CustomDateUtils.checkStepDate', () {
    test('accepte une date passée', () {
      final dt = DateTime.now().subtract(const Duration(hours: 1));
      expect(CustomDateUtils.checkStepDate(dt), isNull);
    });

    test('tolère quelques minutes d\'avance (horloge du téléphone)', () {
      final dt = DateTime.now().add(const Duration(minutes: 2));
      expect(CustomDateUtils.checkStepDate(dt), isNull);
    });

    test('refuse une date dans le futur (ex. 2029)', () {
      expect(
        CustomDateUtils.checkStepDate(DateTime(2029, 1, 1)),
        'Date dans le futur non autorisée.',
      );
    });

    test('refuse une date antérieure à l\'étape précédente', () {
      final err = CustomDateUtils.checkStepDate(
        DateTime(2026, 5, 21, 9),
        notBefore: DateTime(2026, 5, 21, 10),
        notBeforeLabel: 'à la collecte',
      );
      expect(err, 'Date antérieure à la collecte (21/05/2026 à 10:00).');
    });

    test('parseStored lit les formats stockés', () {
      expect(CustomDateUtils.parseStored('2026-05-21 10:30'),
          DateTime(2026, 5, 21, 10, 30));
      expect(CustomDateUtils.parseStored('2026-05-21T10:30'),
          DateTime(2026, 5, 21, 10, 30));
      expect(CustomDateUtils.parseStored(''), isNull);
    });
  });

  group('SampleDao.stepDateError', () {
    late SampleDao dao;

    setUp(() async {
      await setUpTestDb();
      dao = SampleDao();
    });

    tearDown(() async {
      await tearDownTestDb();
    });

    Future<int> insert(String uuid, {String? delivered}) {
      return dao.insertSample(Sample(
        uuid: uuid,
        sampleType: 'CV',
        sampleNature: 'PLASMA',
        sampleStatus: SampleStatus.onTransit,
        collectionDate: '2026-05-21T10:00',
        pickupDate: '2026-05-21 10:30',
        deliveredDate: delivered,
        dirty: 1,
      ));
    }

    test('dépôt après l\'enlèvement : valide', () async {
      final id = await insert('a');
      final err = await dao.stepDateError(DateTime(2026, 5, 21, 12), [id],
          after: ['collection_date', 'pickup_date']);
      expect(err, isNull);
    });

    test('dépôt avant l\'enlèvement : refusé', () async {
      final id = await insert('a');
      final err = await dao.stepDateError(DateTime(2026, 5, 21, 10, 15), [id],
          after: ['collection_date', 'pickup_date']);
      expect(err, contains("l'enlèvement"));
    });

    test('fin d\'analyse non comparée au dépôt (horodatage de saisie)', () async {
      final id = await insert('a', delivered: '2026-05-25T08:00');
      final err = await dao.stepDateError(DateTime(2026, 5, 22, 12), [id],
          after: ['collection_date']);
      expect(err, isNull);
    });

    test('acceptation comparée au dépôt le plus récent du lot', () async {
      final a = await insert('a', delivered: '2026-05-22T08:00');
      final b = await insert('b', delivered: '2026-05-23T08:00');
      final err = await dao.stepDateError(DateTime(2026, 5, 22, 12), [a, b],
          after: ['collection_date', 'delivered_date']);
      expect(err, 'Date antérieure au dépôt au labo (23/05/2026 à 08:00).');
    });
  });
}
