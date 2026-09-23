import 'package:flutter/material.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/utils/custom_date_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';
import 'sample_deposit_screen.dart';

class SampleDetailScreen extends StatefulWidget {
  static const route = '/samples/detail';
  const SampleDetailScreen({super.key});

  @override
  State<SampleDetailScreen> createState() => _SampleDetailScreenState();
}

class _SampleDetailScreenState extends State<SampleDetailScreen> {
  final dao = SampleDao();
  Sample? _sample;
  bool _loading = true;
  String? _error;

  // Cache labos: id -> name
  Map<int, String> _labNames = const {};
    // Cache labos: id -> name
  Map<int, String> _rejectionTypes = const {};
  // Cache sites: id -> name
  Map<int, String> _siteNames = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final id = (args?['id'] as int?) ?? (args?['sampleId'] as int?);
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'Identifiant échantillon manquant';
      });
      return;
    }
    _load(id);
  }

  Future<void> _load(int id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await dao.findById(id);

      final db = await AppDatabase.instance.database;
      final labs = await db.query('lab', orderBy: 'name ASC');
      final sites = await db.query('site', orderBy: 'name ASC');
      final rejectionTypes = await db.query('rejection_type', orderBy: 'name ASC');

      final labMap = <int, String>{};
      for (final row in labs) {
        final lid = (row['id'] as int?) ?? (row['id'] as num?)?.toInt();
        if (lid != null) labMap[lid] = (row['name'] ?? '').toString();
      }

      final siteMap = <int, String>{};
      for (final row in sites) {
        final sid = (row['id'] as int?) ?? (row['id'] as num?)?.toInt();
        if (sid != null) siteMap[sid] = (row['name'] ?? '').toString();
      }


      final rejectionTypesMap = <int, String>{};
      for (final row in rejectionTypes) {
        final rid = (row['id'] as int?) ?? (row['id'] as num?)?.toInt();
        if (rid != null) rejectionTypesMap[rid] = (row['name'] ?? '').toString();
      }

      if (!mounted) return;
      setState(() {
        _sample = s;
        _labNames = labMap;
        _siteNames = siteMap;
        _rejectionTypes = rejectionTypesMap;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur de chargement: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _labName(int? id, {bool includeIdFallback = true}) {
    if (id == null) return null;
    final name = _labNames[id];
    if (name != null && name.trim().isNotEmpty) return name;
    return includeIdFallback ? 'Labo #$id' : null;
  }

  String? _siteName(int? id, {bool includeIdFallback = true}) {
    if (id == null) return null;
    final name = _siteNames[id];
    if (name != null && name.trim().isNotEmpty) return name;
    return includeIdFallback ? 'Site #$id' : null;
  }

    String? _rejectionType(int? id, {bool includeIdFallback = true}) {
    if (id == null) return null;
    final name = _rejectionTypes[id];
    if (name != null && name.trim().isNotEmpty) return name;
    return includeIdFallback ? 'Rejection #$id' : null;
  }

  Widget _syncIcon() {
    final isDirty = (_sample?.dirty ?? 0) == 1;
    return Tooltip(
      message: isDirty ? 'Non synchronisé' : 'Synchronisé avec le serveur',
      child: Icon(
        isDirty ? Icons.cloud_upload : Icons.cloud_done,
        color: isDirty ? Colors.orange : Colors.green,
      ),
    );
  }

  Widget _kv(String label, String? value, {IconData? icon}) {
    final v = (value == null || value.isEmpty) ? '—' : value;
    return ListTile(
      dense: true,
      leading: icon != null ? Icon(icon) : null,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(v, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Détails échantillon';
    final isCollected =
        (_sample?.sampleStatus ?? '').toUpperCase() == 'ON_TRANSIT';

    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(
            title: Text(title),
          ),
          floatingActionButton: isCollected &&
                  _sample?.id != null &&
                  AuthUtils.canDoConveyorTasks(userRole)
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.biotech_outlined),
                  label: const Text('Déposer au labo'),
                  onPressed: () async {
                    final ok = await Navigator.of(context).pushNamed(
                      SampleDepositScreen.route,
                      arguments: {
                        'ids': [_sample!.id],
                      },
                    );
                    if (ok == true) {
                      await _load(_sample!.id!);
                    }
                  },
                )
              : null,
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : (_sample == null
                    ? const Center(child: Text('Introuvable'))
                    : RefreshIndicator(
                        onRefresh: () => _load(_sample!.id!),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          children: [
                            // Carte d’entête avec icône sync
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.biotech_outlined),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _sample!
                                                        .sampleIdentifier
                                                        ?.isNotEmpty ==
                                                    true
                                                ? _sample!.sampleIdentifier!
                                                : (_sample!.uuid),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              Chip(
                                                avatar: const Icon(
                                                  Icons.category,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  _sample!.sampleType ??
                                                      'Type: —',
                                                ),
                                              ),
                                              Chip(
                                                avatar: const Icon(
                                                  Icons.local_hospital_outlined,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  'Statut: ${_sample!.sampleStatus ?? '—'}',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _syncIcon(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Identifiants
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _kv(
                                    'Code patient',
                                    _sample!.patientIdentifier,
                                    icon: Icons.badge_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Identifiant échantillon',
                                    _sample!.sampleIdentifier,
                                    icon: Icons.qr_code_2,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'UUID',
                                    _sample!.uuid,
                                    icon: Icons.fingerprint,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Provenance / Destination
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _kv(
                                    'Site source',
                                    _siteName(_sample!.fromSiteId)??_sample!.fromSiteName,
                                    icon: Icons.place_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Labo destination',
                                    _labName(_sample!.destinationLabId),
                                    icon: Icons.local_hospital_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Labo de livraison',
                                    _labName(_sample!.deliveredLabId),
                                    icon: Icons.biotech_outlined,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Kilométrage
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _kv(
                                    'Km départ (collecte)',
                                    _sample!.startMileage?.toString(),
                                    icon: Icons.speed_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Km fin (collecte)',
                                    _sample!.endMileage?.toString(),
                                    icon: Icons.speed_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Km départ (résultat)',
                                    _sample!.resultStartMileage?.toString(),
                                    icon: Icons.straighten_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Km fin (résultat)',
                                    _sample!.resultEndMileage?.toString(),
                                    icon: Icons.straighten_outlined,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Dates
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _kv(
                                    'Prélèvement',
                                    CustomDateUtils.toHumanReadable(_sample!.collectionDate),
                                    icon: Icons.calendar_month_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Collecte',
                                    CustomDateUtils.toHumanReadable(_sample!.pickupDate),
                                    icon: Icons.event_available_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Déposé (labo)',
                                    CustomDateUtils.toHumanReadable(_sample!.deliveredDate),
                                    icon: Icons.biotech_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Accepté (labo)',
                                    CustomDateUtils.toHumanReadable(_sample!.acceptedDate),
                                    icon: Icons.verified_outlined,
                                  ),
                                  _kv(
                                    'Numéro labo',
                                    _sample!.labNumber,
                                    icon: Icons.pin_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Analyse démarrée',
                                    CustomDateUtils.toHumanReadable(_sample!.analysisStartedDate),
                                    icon: Icons.play_circle_outline,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Analyse terminée',
                                    CustomDateUtils.toHumanReadable(_sample!.analysisCompletedDate),
                                    icon: Icons.stop_circle_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Résultat prêt',
                                    CustomDateUtils.toHumanReadable(_sample!.analysisReleasedDate),
                                    icon: Icons.assignment_turned_in_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Résultat collecté',
                                    CustomDateUtils.toHumanReadable(_sample!.resultCollectionDate),
                                    icon: Icons.assignment_return_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Résultat livré',
                                    CustomDateUtils.toHumanReadable(_sample!.resultDeliveredDate),
                                    icon: Icons.assignment_turned_in_outlined,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Rejet (si applicable)
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  _kv(
                                    'Type de rejet',
                                    _rejectionType(_sample!.rejectionTypeId),
                                    icon: Icons.block,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Commentaire rejet',
                                    _sample!.rejectionComment,
                                    icon: Icons.comment_outlined,
                                  ),
                                  const Divider(height: 1),
                                  _kv(
                                    'Date rejet',
                                    CustomDateUtils.toHumanReadable(_sample!.rejectionDate),
                                    icon: Icons.event_busy_outlined,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
    );
  }
}
