import 'package:flutter/material.dart';
import 'package:lstracker/data/services/auto_sync_manager.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/form_section.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';

class ResultsDepositFormScreen extends StatefulWidget {
  static const route = '/results-collected/deposit-form';
  const ResultsDepositFormScreen({super.key});

  @override
  State<ResultsDepositFormScreen> createState() =>
      _ResultsDepositFormScreenState();
}

class _ResultsDepositFormScreenState extends State<ResultsDepositFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _kmCtl = TextEditingController();
  final _dateCtl = TextEditingController();
  final _timeCtl = TextEditingController();

  final dao = SampleDao();

  Set<int> _ids = {};
  String _siteLabel = 'Site';
  bool _bootstrapped = false;
  bool _loading = true;

  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();

  // Règle métier kilométrage (pour les résultats)
  double? _minRequiredKm; // = MAX(result_start_mileage) des IDs sélectionnés
  String? _kmHint; // helper text dynamique

  @override
  void dispose() {
    _kmCtl.dispose();
    _dateCtl.dispose();
    _timeCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final idsArg = (args?['ids'] as List?)?.cast<int>() ?? const <int>[];
    _ids = idsArg.toSet();
    _siteLabel = (args?['siteLabel'] as String?) ?? 'Site';

    _syncDT();
    _init();
  }

  void _syncDT() {
    String two(int n) => n.toString().padLeft(2, '0');
    _dateCtl.text = '${_date.year}-${two(_date.month)}-${two(_date.day)}';
    _timeCtl.text = '${two(_time.hour)}:${two(_time.minute)}';
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      // Calcule MAX(result_start_mileage) pour les _ids sélectionnés
      if (_ids.isNotEmpty) {
        final db = await AppDatabase.instance.database;
        final placeholders = List.filled(_ids.length, '?').join(',');
        final r = await db.rawQuery('''
          SELECT MAX(result_start_mileage) AS maxStartKm
          FROM sample
          WHERE id IN ($placeholders) AND result_start_mileage IS NOT NULL
        ''', _ids.toList());

        double? minKm;
        if (r.isNotEmpty && r.first['maxStartKm'] != null) {
          minKm =
              (r.first['maxStartKm'] as double?) ??
              (r.first['maxStartKm'] as num?)?.toDouble();
        }

        if (!mounted) return;
        setState(() {
          _minRequiredKm = minKm;
          _kmHint = _minRequiredKm != null
              ? 'Doit être > ${_minRequiredKm} km'
              : 'Saisissez le kilométrage (réf. collecte résultats indisponible)';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _minRequiredKm = null;
          _kmHint =
              'Saisissez le kilométrage (aucun échantillon sélectionné ?)';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      // Pas de date future ; une valeur enregistrée hors borne est ramenée
      // à aujourd'hui (sinon showDatePicker lève une assertion).
      initialDate: _date.isAfter(DateTime.now()) ? DateTime.now() : _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() {
        _date = d;
        _syncDT();
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) {
      setState(() {
        _time = t;
        _syncDT();
      });
    }
  }

  Future<void> _submit() async {
    if (_ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun échantillon sélectionné.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final dt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final iso = dt.toIso8601String();

    // Chronologie : pas dans le futur, pas avant l'étape précédente.
    final dateError = await dao.stepDateError(dt, _ids, after: ['collection_date', 'result_collection_date']);
    if (dateError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }
    final endKm = int.tryParse(_kmCtl.text.trim());

    try {
      final n = await dao.depositResultsMany(
        _ids,
        deliveredDateIso: iso,
        endMileage: endKm, // result_end_mileage côté DAO
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Résultats déposés: $n / ${_ids.length}')),
      );
      AutoSyncManager.instance.pushNow();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _ids.length;
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(
            title: Text('Dépôt résultats — $_siteLabel'),
          ),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),
          persistentFooterButtons: _loading
              ? null
              : [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(
                          Icons.assignment_turned_in_outlined),
                      label: Text('Déposer $count résultat(s)'),
                    ),
                  ),
                ],
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Bandeau récap site/qté
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.place,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _siteLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '$count résultat(s) à déposer',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ===== Kilométrage =====
                      FormSection(
                        title: 'Kilométrage',
                        icon: Icons.speed,
                        subtitle: 'Kilométrage à l\'arrivée sur le site',
                        child: TextFormField(
                          controller: _kmCtl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            signed: false,
                            decimal: false,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Kilométrage *',
                            border: const OutlineInputBorder(),
                            helperText: _kmHint,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Saisissez le kilométrage';
                            }
                            final parsed = int.tryParse(v.trim());
                            if (parsed == null || parsed < 0) {
                              return 'Kilométrage invalide';
                            }
                            if (_minRequiredKm != null &&
                                parsed <= _minRequiredKm!) {
                              return 'Doit être strictement > $_minRequiredKm';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ===== Date / heure =====
                      FormSection(
                        title: 'Date et heure de dépôt',
                        icon: Icons.event_outlined,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _dateCtl,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Date *',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    tooltip: 'Sélectionner une date',
                                    icon: const Icon(
                                        Icons.calendar_month_outlined),
                                    onPressed: _pickDate,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Choisissez la date'
                                        : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _timeCtl,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Heure *',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    tooltip: "Sélectionner une heure",
                                    icon: const Icon(Icons.access_time),
                                    onPressed: _pickTime,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Choisissez l\'heure'
                                        : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
    );
  }
}
