class SampleStatus {
  static const String onTransit = 'ON_TRANSIT';
  static const String receivedAtHub = 'RECEIVED_AT_HUB';
  static const String receivedAtReferenceLab = 'RECEIVED_AT_REFERENCE_LAB';
  static const String receivedAtDistrictLab = 'RECEIVED_AT_DISTRICT_LAB';
  static const String receivedAtTbLab = 'RECEIVED_AT_TB_LAB';
  static const String acceptedAtHub = 'ACCEPTED_AT_HUB';
  static const String acceptedAtReferenceLab = 'ACCEPTED_AT_REFERENCE_LAB';
  static const String acceptedAtDistrictLab = 'ACCEPTED_AT_DISTRICT_LAB';
  static const String acceptedAtTbLab = 'ACCEPTED_AT_TB_LAB';
  static const String analysisDone = 'ANALYSIS_DONE';
  static const String nonConform = 'NON_CONFORM';
  static const String analysisFailed = 'ANALYSIS_FAILED';
  static const String resultCollected = 'RESULT_COLLECTED';
  static const String resultOnSite = 'RESULT_ON_SITE';

  static const Map<String, String> _labels = {
    onTransit: 'En cours d’acheminement',
    receivedAtHub: 'Déposé au hub',
    receivedAtReferenceLab: 'Déposé au laboratoire de référence',
    receivedAtDistrictLab: 'Déposé au laboratoire de district',
    receivedAtTbLab: 'Déposé au CAT',
    acceptedAtHub: 'Accepté au hub',
    acceptedAtReferenceLab: 'Accepté au laboratoire de référence',
    acceptedAtDistrictLab: 'Accepté au laboratoire de district',
    acceptedAtTbLab: 'Accepté au CAT',
    analysisDone: 'Résultat prêt',
    nonConform: 'Non conforme',
    analysisFailed: 'Échec de l’analyse',
    resultCollected: 'Résultat récupéré au laboratoire',
    resultOnSite: 'Résultat déposé sur le site',
  };

  /// Libellé affiché d'un code de statut ; le code brut si inconnu.
  static String label(String? code) {
    if (code == null || code.trim().isEmpty) return 'Non renseigné';
    return _labels[code.trim().toUpperCase()] ?? code;
  }
}

class UserRole {
  static const String conveyor = 'CONVOYEUR';
  static const String labTech = 'BIOLOGISTE';
  static const String admin = 'ADMIN';
}

class Sample {
  final int? id;
  final String? externalId;
  final String uuid;
  final int? sampleConveyor;
  final int? referringSampleId;
  final String? fromSiteName;
  final String? fromSiteCode;
  final int? fromSiteId;
  final int? destinationLabId;
  final int? deliveredLabId;
  final String? sampleIdentifier;
  final String? patientIdentifier;
  final String? sampleType;
  final String? sampleNature;
  final int? startMileage;
  final int? endMileage;
  final int? resultStartMileage;
  final int? resultEndMileage;
  final String? collectionDate;
  final String? pickupDate;
  final String? deliveredDate;
  final String? acceptedDate;
  final String? labNumber;
  final String? sampleStatus;
  final String? analysisStartedDate;
  final String? analysisCompletedDate;
  final String? analysisReleasedDate;
  final String? resultCollectionDate;
  final String? resultDeliveredDate;
  final int? resultCollector;
  final int? rejectionTypeId;
  final String? rejectionComment;
  final String? rejectionDate;
  final String? createdAt;
  final String? lastupdatedAt;
  final int dirty;

  Sample({
    this.id,
    this.externalId,
    required this.uuid,
    this.sampleConveyor,
    this.referringSampleId,
    this.fromSiteName,
    this.fromSiteCode,
    this.fromSiteId,
    this.destinationLabId,
    this.deliveredLabId,
    this.sampleIdentifier,
    this.patientIdentifier,
    this.sampleType,
    this.sampleNature,
    this.startMileage,
    this.endMileage,
    this.resultStartMileage,
    this.resultEndMileage,
    this.collectionDate,
    this.pickupDate,
    this.deliveredDate,
    this.acceptedDate,
    this.labNumber,
    this.sampleStatus,
    this.analysisStartedDate,
    this.analysisCompletedDate,
    this.analysisReleasedDate,
    this.resultCollectionDate,
    this.resultDeliveredDate,
    this.resultCollector,
    this.rejectionTypeId,
    this.rejectionComment,
    this.rejectionDate,
    this.createdAt,
    this.lastupdatedAt,
    this.dirty = 1,
  });
  Sample copyWith({
    int? id,
    String? externalId,
    String? uuid,
    int? sampleConveyor,
    int? referringSampleId,
    String? fromSiteName,
    String? fromSiteCode,
    int? fromSiteId,
    int? destinationLabId,
    int? deliveredLabId,
    String? sampleIdentifier,
    String? patientIdentifier,
    String? sampleType,
    String? sampleNature,
    int? startMileage,
    int? endMileage,
    int? resultStartMileage,
    int? resultEndMileage,
    String? collectionDate,
    String? pickupDate,
    String? deliveredDate,
    String? acceptedDate,
    String? labNumber,
    String? sampleStatus,
    String? analysisStartedDate,
    String? analysisCompletedDate,
    String? analysisReleasedDate,
    String? resultCollectionDate,
    String? resultDeliveredDate,
    int? resultCollector,
    int? rejectionTypeId,
    String? rejectionComment,
    String? rejectionDate,
    String? createdAt,
    String? lastupdatedAt,
    int? dirty,
  }) => Sample(
    id: id ?? this.id,
    externalId: externalId ?? this.externalId,
    uuid: uuid ?? this.uuid,
    sampleConveyor: sampleConveyor ?? this.sampleConveyor,
    referringSampleId: referringSampleId ?? this.referringSampleId,
    fromSiteName: fromSiteName ?? this.fromSiteName,
    fromSiteCode: fromSiteCode ?? this.fromSiteCode,
    fromSiteId: fromSiteId ?? this.fromSiteId,
    destinationLabId: destinationLabId ?? this.destinationLabId,
    deliveredLabId: deliveredLabId ?? this.deliveredLabId,
    sampleIdentifier: sampleIdentifier ?? this.sampleIdentifier,
    patientIdentifier: patientIdentifier ?? this.patientIdentifier,
    sampleType: sampleType ?? this.sampleType,
    sampleNature: sampleNature ?? this.sampleNature,
    startMileage: startMileage ?? this.startMileage,
    endMileage: endMileage ?? this.endMileage,
    resultStartMileage: resultStartMileage ?? this.resultStartMileage,
    resultEndMileage: resultEndMileage ?? this.resultEndMileage,
    collectionDate: collectionDate ?? this.collectionDate,
    pickupDate: pickupDate ?? this.pickupDate,
    deliveredDate: deliveredDate ?? this.deliveredDate,
    acceptedDate: acceptedDate ?? this.acceptedDate,
    labNumber: labNumber ?? this.labNumber,
    sampleStatus: sampleStatus ?? this.sampleStatus,
    analysisStartedDate: analysisStartedDate ?? this.analysisStartedDate,
    analysisCompletedDate: analysisCompletedDate ?? this.analysisCompletedDate,
    analysisReleasedDate: analysisReleasedDate ?? this.analysisReleasedDate,
    resultCollectionDate: resultCollectionDate ?? this.resultCollectionDate,
    resultDeliveredDate: resultDeliveredDate ?? this.resultDeliveredDate,
    resultCollector: resultCollector ?? this.resultCollector,
    rejectionTypeId: rejectionTypeId ?? this.rejectionTypeId,
    rejectionComment: rejectionComment ?? this.rejectionComment,
    rejectionDate: rejectionDate ?? this.rejectionDate,
    createdAt: createdAt ?? this.createdAt,
    lastupdatedAt: lastupdatedAt ?? this.lastupdatedAt,
    dirty: dirty ?? this.dirty,
  );
  Map<String, Object?> toMap() {
    //String? _ts(DateTime? d) => d?.toIso8601String();
    return {
      'id': id,
      'external_id': externalId,
      'uuid': uuid,
      'sample_conveyor': sampleConveyor,
      'referring_sample_id': referringSampleId,
      'from_site_name': fromSiteName,
      'from_site_code': fromSiteCode,
      'from_site_id': fromSiteId,
      'destination_lab_id': destinationLabId,
      'delivered_lab_id': deliveredLabId,
      'sample_identifier': sampleIdentifier,
      'patient_identifier': patientIdentifier,
      'sample_type': sampleType,
      'sample_nature': sampleNature,
      'start_mileage': startMileage,
      'end_mileage': endMileage,
      'result_start_mileage': resultStartMileage,
      'result_end_mileage': resultEndMileage,
      'collection_date': collectionDate,
      'pickup_date': (pickupDate),
      'delivered_date': (deliveredDate),
      'accepted_date': (acceptedDate),
      'lab_number': labNumber,
      'sample_status': sampleStatus,
      'analysis_started_date': (analysisStartedDate),
      'analysis_completed_date': (analysisCompletedDate),
      'analysis_released_date': (analysisReleasedDate),
      'result_collection_date': (resultCollectionDate),
      'result_delivered_date': (resultDeliveredDate),
      'result_collector': resultCollector,
      'rejection_type_id': rejectionTypeId,
      'rejection_comment': rejectionComment,
      'rejection_date': rejectionDate,
      'created_at': (createdAt),
      'lastupdated_at': (lastupdatedAt),
      'dirty': dirty,
    };
  }

  static Sample fromMap(Map<String, Object?> map) {
    //DateTime? _td(dynamic v) => v == null ? null : DateTime.parse(v as String);
    int? _num(dynamic v) =>
        v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
    return Sample(
      id: map['id'] as int?,
      externalId: map['external_id'] as String?,
      uuid: map['uuid'] as String,
      sampleConveyor: map['sample_conveyor'] as int?,
      referringSampleId: map['referring_sample_id'] as int?,
      fromSiteName: map['from_site_name'] as String?,
      fromSiteCode: map['from_site_code'] as String?,
      fromSiteId: map['from_site_id'] as int?,
      destinationLabId: map['destination_lab_id'] as int?,
      deliveredLabId: map['delivered_lab_id'] as int?,
      sampleIdentifier: map['sample_identifier'] as String?,
      patientIdentifier: map['patient_identifier'] as String?,
      sampleType: map['sample_type'] as String?,
      sampleNature: map['sample_nature'] as String?,
      startMileage: _num(map['start_mileage']),
      endMileage: _num(map['end_mileage']),
      resultStartMileage: _num(map['result_start_mileage']),
      resultEndMileage: _num(map['result_end_mileage']),
      collectionDate: map['collection_date'] as String?,
      pickupDate: (map['pickup_date'] as String?),
      deliveredDate: (map['delivered_date'] as String?),
      acceptedDate: (map['accepted_date'] as String?),
      labNumber: map['lab_number'] as String?,
      sampleStatus: map['sample_status'] as String?,
      analysisStartedDate: (map['analysis_started_date'] as String?),
      analysisCompletedDate: (map['analysis_completed_date'] as String?),
      analysisReleasedDate: (map['analysis_released_date'] as String?),
      resultCollectionDate: (map['result_collection_date'] as String?),
      resultDeliveredDate: (map['result_delivered_date'] as String?),
      resultCollector: map['result_collector'] as int?,
      rejectionTypeId: map['rejection_type_id'] as int?,
      rejectionComment: map['rejection_comment'] as String?,
      rejectionDate: (map['rejection_date'] as String?),
      createdAt: (map['created_at'] as String?),
      lastupdatedAt: (map['lastupdated_at'] as String?),
      dirty: (map['dirty'] as int?) ?? 1,
    );
  }

  Map<String, Object?> toServerMap() {
    return {
      'uuid': uuid,
      'external_id': externalId,
      'sample_conveyor': sampleConveyor,
      'referring_sample_id': referringSampleId,
      'from_site_name': fromSiteName,
      'from_site_code': fromSiteCode,
      'from_site_id': fromSiteId,
      'destination_lab_id': destinationLabId,
      'delivered_lab_id': deliveredLabId,
      'sample_identifier': sampleIdentifier,
      'patient_identifier': patientIdentifier,
      'sample_type': sampleType,
      'sample_nature': sampleNature,
      'start_mileage': startMileage,
      'end_mileage': endMileage,
      'result_start_mileage': resultStartMileage,
      'result_end_mileage': resultEndMileage,
      'collection_date': collectionDate,
      'pickup_date': pickupDate,
      'delivered_date': deliveredDate,
      'accepted_date': acceptedDate,
      'lab_number': labNumber,
      'sample_status': sampleStatus,
      'analysis_started_date': analysisStartedDate,
      'analysis_completed_date': analysisCompletedDate,
      'analysis_released_date': analysisReleasedDate,
      'result_collection_date': resultCollectionDate,
      'result_delivered_date': resultDeliveredDate,
      'result_collector': resultCollector,
      'rejection_type_id': rejectionTypeId,
      'rejection_comment': rejectionComment,
      'rejection_date': rejectionDate,
      'created_at': createdAt,
    }..removeWhere((k, v) => v == null);
  }
}
