import 'package:flutter_test/flutter_test.dart';
import 'package:lstracker/data/models/sample.dart';

void main() {
  group('SampleStatus.label', () {
    test('affiche « En cours d’acheminement » pour ON_TRANSIT', () {
      expect(SampleStatus.label('ON_TRANSIT'), 'En cours d’acheminement');
      expect(SampleStatus.label('on_transit'), 'En cours d’acheminement');
    });

    test('affiche le résultat récupéré au laboratoire', () {
      expect(
        SampleStatus.label(SampleStatus.resultCollected),
        'Résultat récupéré au laboratoire',
      );
    });

    test('aucun libellé ne contient « transit » ni de tiret long', () {
      const codes = [
        SampleStatus.onTransit,
        SampleStatus.receivedAtHub,
        SampleStatus.receivedAtReferenceLab,
        SampleStatus.receivedAtDistrictLab,
        SampleStatus.receivedAtTbLab,
        SampleStatus.acceptedAtHub,
        SampleStatus.acceptedAtReferenceLab,
        SampleStatus.acceptedAtDistrictLab,
        SampleStatus.acceptedAtTbLab,
        SampleStatus.analysisDone,
        SampleStatus.nonConform,
        SampleStatus.analysisFailed,
        SampleStatus.resultCollected,
        SampleStatus.resultOnSite,
      ];
      for (final c in codes) {
        final l = SampleStatus.label(c);
        expect(l, isNot(c), reason: 'code sans libellé : $c');
        expect(l.toLowerCase(), isNot(contains('transit')));
        expect(l, isNot(matches(RegExp('[—–]'))));
      }
    });

    test('code vide ou inconnu', () {
      expect(SampleStatus.label(null), 'Non renseigné');
      expect(SampleStatus.label(''), 'Non renseigné');
      expect(SampleStatus.label('AUTRE'), 'AUTRE');
    });
  });
}
