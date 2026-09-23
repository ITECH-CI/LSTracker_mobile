import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lstracker/data/services/auto_sync_manager.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/utils/custom_date_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';

class SampleEditScreen extends StatefulWidget {
  static const route = '/samples/edit';
  const SampleEditScreen({super.key});

  @override
  State<SampleEditScreen> createState() => _SampleEditScreenState();
}

class _SampleEditScreenState extends State<SampleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _kmCtl = TextEditingController();
  final _patientCtl = TextEditingController();
  final _sampleIdCtl = TextEditingController();
  final _collectionDateCtl = TextEditingController();
  final _pickupDateCtl = TextEditingController();

  final dao = SampleDao();
  Sample? _sample;

  // Garde-fou: empêcher _init d’être relancé après la 1re fois
  bool _bootstrapped = false;

  // Meta
  List<Map<String, Object?>> _circuits = const [];
  List<Map<String, Object?>> _labs = const [];

  // Sites dépendants du circuit sélectionné
  List<Map<String, Object?>> _sites = const [];
  bool _sitesLoading = false;

  // Champs modifiables
  int? _circuitId;
  int? _siteId;
  int? _destLabId;
  String? _type;
  String? _nature;

  bool _loading = true;
  bool _saving = false;

  @override
  void dispose() {
    _kmCtl.dispose();
    _patientCtl.dispose();
    _sampleIdCtl.dispose();
    _collectionDateCtl.dispose();
    _pickupDateCtl.dispose();
    super.dispose();
  }

  /// Picker borné à [année-1, aujourd'hui] pour éviter les saisies aberrantes.
  Future<void> _pickDate(TextEditingController ctl) async {
    final minD = CustomDateUtils.minCollectionDate;
    final maxD = CustomDateUtils.maxCollectionDate;
    var init = CustomDateUtils.parseStored(ctl.text) ?? DateTime.now();
    // Une valeur enregistrée hors bornes (ex. 2029, ou antérieure à l'an
    // dernier) ferait lever une assertion à showDatePicker : on la ramène
    // dans l'intervalle.
    if (init.isAfter(maxD)) init = maxD;
    if (init.isBefore(minD)) init = minD;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: CustomDateUtils.minCollectionDate,
      lastDate: CustomDateUtils.maxCollectionDate,
    );
    if (picked != null) {
      ctl.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ne booter qu’une seule fois
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final id = (args?['id'] as int?) ?? (args?['sampleId'] as int?);
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    _init(id);
  }

  Future<void> _init(int id) async {
    setState(() => _loading = true);
    try {
      final s = await dao.findById(id);
      if (s == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échantillon introuvable')),
        );
        Navigator.of(context).pop();
        return;
      }
      final db = await AppDatabase.instance.database;
      final circuits = await db.query('circuit', orderBy: 'name ASC');
      // Labos sélectionnables + le labo actuel de l'échantillon, pour que la
      // valeur pré-remplie figure toujours dans la liste déroulante.
      final labs = await db.query(
        'lab',
        where: 'selectable = 1 OR id = ?',
        whereArgs: [s.destinationLabId ?? -1],
        orderBy: 'name ASC',
      );

      // Pré-remplir depuis la BD UNE SEULE FOIS
      _sample = s;
      _kmCtl.text = (s.startMileage?.toString() ?? '');
      _patientCtl.text = (s.patientIdentifier ?? '');
      _sampleIdCtl.text = (s.sampleIdentifier ?? '');
      _collectionDateCtl.text = (s.collectionDate ?? '');
      _pickupDateCtl.text = (s.pickupDate ?? '');
      _type = s.sampleType;
      _nature = s.sampleNature;
      _destLabId = s.destinationLabId;
      _siteId = s.fromSiteId;

      // Essayer de déduire un circuit pour le site (si présent dans circuit_site)
      int? circuitId;
      if (_siteId != null) {
        final rs = await db.rawQuery(
          'SELECT circuit_id FROM circuit_site WHERE site_id = ? LIMIT 1',
          [_siteId],
        );
        if (rs.isNotEmpty) {
          circuitId =
              (rs.first['circuit_id'] as int?) ??
              (rs.first['circuit_id'] as num?)?.toInt();
        }
      }
      _circuitId = circuitId;

      if (!mounted) return;
      setState(() {
        _circuits = circuits;
        _labs = labs;
      });

      // Charger la liste des sites pour le circuit pré-rempli
      await _loadSitesForCircuit(_circuitId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSitesForCircuit(int? circuitId) async {
    setState(() {
      _sitesLoading = true;
    });
    try {
      final db = await AppDatabase.instance.database;
      List<Map<String, Object?>> rows;
      if (circuitId == null) {
        rows = await db.query('site', orderBy: 'name ASC');
      } else {
        rows = await db.rawQuery(
          '''
          SELECT s.*
          FROM site s
          INNER JOIN circuit_site cs ON cs.site_id = s.id
          WHERE cs.circuit_id = ?
          ORDER BY s.name ASC
        ''',
          [circuitId],
        );
      }

      // Si le site sélectionné n'est plus valide -> reset
      if (_siteId != null &&
          rows.indexWhere(
                (e) =>
                    ((e['id'] as int?) ?? (e['id'] as num?)?.toInt()) ==
                    _siteId,
              ) <
              0) {
        _siteId = null;
      }

      if (!mounted) return;
      setState(() {
        _sites = rows;
      });
    } finally {
      if (mounted) setState(() => _sitesLoading = false);
    }
  }

  Future<void> _onCircuitChanged(int? v) async {
    setState(() {
      _circuitId = v;
      _siteId = null; // reset site
    });
    await _loadSitesForCircuit(v);
  }

  Future<void> _save() async {
    if (_sample == null) return;
    if (!_formKey.currentState!.validate()) return;

    // Chronologie : prélèvement et enlèvement pas dans le futur, enlèvement
    // pas avant le prélèvement (même règle qu'à la collecte).
    final collectedAt = CustomDateUtils.parseStored(_collectionDateCtl.text);
    final pickedUpAt = CustomDateUtils.parseStored(_pickupDateCtl.text);
    final dateError =
        (collectedAt == null
            ? null
            : CustomDateUtils.checkStepDate(collectedAt)) ??
        (pickedUpAt == null
            ? null
            : CustomDateUtils.checkStepDate(
                pickedUpAt,
                notBefore: collectedAt,
                notBeforeLabel: 'au prélèvement',
              ));
    if (dateError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }

    final id = _sample!.id!;
    final kmValue = int.tryParse(_kmCtl.text.trim());

    final fields = <String, Object?>{
      'from_site_id': _siteId,
      'start_mileage': kmValue,
      'sample_type': _type,
      'sample_nature': _nature,
      'patient_identifier': _patientCtl.text.trim(),
      'sample_identifier': _sampleIdCtl.text.trim().isEmpty
          ? null
          : _sampleIdCtl.text.trim(),
      'collection_date': _collectionDateCtl.text.trim().isEmpty
          ? null
          : _collectionDateCtl.text.trim(),
      'pickup_date': _pickupDateCtl.text.trim().isEmpty
          ? null
          : _pickupDateCtl.text.trim(),
      'destination_lab_id': _destLabId,
    };

    setState(() => _saving = true);
    try {
      await dao.updateFields(id, fields);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifications enregistrées ')),
      );
      AutoSyncManager.instance.pushNow();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _sample == null
        ? 'Modifier'
        : 'Modifier — ${_sample!.sampleIdentifier ?? _sample!.uuid}';

    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: Text(title)),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _sample == null
              ? const Center(child: Text('Introuvable'))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Circuit (Axe)
                      DropdownButtonFormField<int>(
                        value: _circuitId,
                        items: _circuits
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value:
                                    (e['id'] as int?) ??
                                    (e['id'] as num?)?.toInt(),
                                child: Text(
                                  (e['name'] ?? '').toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Axe / Circuit (collecte)',
                          helperText: 'Détermine les sites de collecte proposés',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => _onCircuitChanged(v),
                        validator: (v) =>
                            v == null ? 'Choisissez un axe / circuit' : null,
                      ),
                      const SizedBox(height: 12),

                      // Site (filtré par circuit)
                      DropdownButtonFormField<int>(
                        value: _siteId,
                        isExpanded: true,
                        items: _sites
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value:
                                    (e['id'] as int?) ??
                                    (e['id'] as num?)?.toInt(),
                                child: Text(
                                  (e['name'] ?? '').toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        decoration: InputDecoration(
                          labelText: _sitesLoading
                              ? 'Site (chargement...)'
                              : 'Site de collecte',
                          border: const OutlineInputBorder(),
                          suffixIcon: _sitesLoading
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 12.0),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        onChanged: _sitesLoading
                            ? null
                            : (v) => setState(() => _siteId = v),
                        validator: (v) =>
                            v == null ? 'Choisissez un site' : null,
                      ),
                      const SizedBox(height: 12),

                      // Km
                      TextFormField(
                        controller: _kmCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Kilométrage (arrivée site)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Saisissez le kilométrage';
                          }
                          if (int.tryParse(v.trim()) == null) {
                            return 'Kilométrage invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Type
                      DropdownButtonFormField<String>(
                        value: _type,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'BI', child: Text('BI')),
                          DropdownMenuItem(value: 'BS', child: Text('BS')),
                          DropdownMenuItem(value: 'CV', child: Text('CV')),
                          DropdownMenuItem(value: 'EID', child: Text('EID')),
                          DropdownMenuItem(value: 'PrEP', child: Text('PrEP')),
                          DropdownMenuItem(value: 'IVSA', child: Text('IVSA')),
                          DropdownMenuItem(value: 'TB', child: Text('TB')),
                          DropdownMenuItem(value: 'HPV', child: Text('HPV')),
                          DropdownMenuItem(
                            value: 'Autre',
                            child: Text('Autre'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Nature du bilan démandé',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _type = v),
                        validator: (v) =>
                            v == null ? 'Sélectionnez un type' : null,
                      ),
                      const SizedBox(height: 12),

                      // Nature
                      DropdownButtonFormField<String>(
                        value: _nature,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'DBS', child: Text('DBS')),
                          DropdownMenuItem(
                            value: 'SANG TOTAL',
                            child: Text('SANG TOTAL'),
                          ),
                          DropdownMenuItem(
                            value: 'PLASMA',
                            child: Text('PLASMA'),
                          ),
                          DropdownMenuItem(value: 'PSC', child: Text('PSC')),
                          DropdownMenuItem(
                            value: 'CRACHAT',
                            child: Text('CRACHAT'),
                          ),
                          DropdownMenuItem(value: 'LCR', child: Text('LCR')),
                          DropdownMenuItem(
                            value: 'SELLES',
                            child: Text('SELLES'),
                          ),
                          DropdownMenuItem(value: 'PV', child: Text('PV')),
                          DropdownMenuItem(
                            value: 'Autre',
                            child: Text('Autre'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Nature du prélèvement',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _nature = v),
                        validator: (v) =>
                            v == null ? 'Sélectionnez la nature' : null,
                      ),
                      const SizedBox(height: 12),

                      // Identifiants
                      TextFormField(
                        controller: _patientCtl,
                        decoration: const InputDecoration(
                          labelText: 'Code patient',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Code patient requis'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _sampleIdCtl,
                        decoration: const InputDecoration(
                          labelText: 'Identifiant échantillon (si dispo)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Dates : champs en lecture seule + picker borné
                      // [année-1, aujourd'hui] + validation centralisée pour
                      // empêcher la saisie de dates aberrantes (ex. année 204).
                      TextFormField(
                        controller: _collectionDateCtl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Date de prélèvement',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Sélectionner une date',
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: () => _pickDate(_collectionDateCtl),
                          ),
                        ),
                        validator: (v) =>
                            CustomDateUtils.validateCollectionDate(v, required: false),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pickupDateCtl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Date de collecte',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Sélectionner une date',
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: () => _pickDate(_pickupDateCtl),
                          ),
                        ),
                        validator: (v) =>
                            CustomDateUtils.validateCollectionDate(v, required: false),
                      ),
                      const SizedBox(height: 12),

                      // Labo destination
                      DropdownButtonFormField<int>(
                        value: _destLabId,
                        isExpanded: true,
                        items: _labs
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value:
                                    (e['id'] as int?) ??
                                    (e['id'] as num?)?.toInt(),
                                child: Text(
                                  (e['name'] ?? '').toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'Laboratoire de destination',
                          helperText: 'Indépendant du circuit de collecte',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _destLabId = v),
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'Enregistrement...' : 'Enregistrer',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
