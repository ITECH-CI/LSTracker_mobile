import 'package:flutter/material.dart';
import 'package:lstracker/data/services/auto_sync_manager.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/sample_dao.dart';

class SampleResultCollectScreen extends StatefulWidget {
  static const route = '/samples/result-collect';
  const SampleResultCollectScreen({super.key});

  @override
  State<SampleResultCollectScreen> createState() =>
      _SampleResultCollectScreenState();
}

class _SampleResultCollectScreenState extends State<SampleResultCollectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtl = TextEditingController();
  final _timeCtl = TextEditingController();
  final _kmStartCtl = TextEditingController();

  final dao = SampleDao();

  Set<int> _ids = {};
  bool _bootstrapped = false;

  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();

  @override
  void dispose() {
    _dateCtl.dispose();
    _timeCtl.dispose();
    _kmStartCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final idsArg =
        (args?['ids'] as List?)?.cast<int>() ??
        (args?['idsSet'] as Set<int>?) ??
        const <int>{};
    _ids = idsArg.toSet();

    _syncDT();
  }

  void _syncDT() {
    String two(int n) => n.toString().padLeft(2, '0');
    _dateCtl.text = '${_date.year}-${two(_date.month)}-${two(_date.day)}';
    _timeCtl.text = '${two(_time.hour)}:${two(_time.minute)}';
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
    final dateError = await dao.stepDateError(dt, _ids, after: ['collection_date', 'analysis_released_date']);
    if (dateError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }

    // km départ résultat : on le stocke dans result_start_mileage (même valeur appliquée à tous)
    final kmStart = int.tryParse(_kmStartCtl.text.trim());

    try {
      // 1) statut + date collecte résultat
      final n = await dao.collectResultsMany(_ids, collectedDateIso: iso);

      // 2) si km saisi -> maj champ result_start_mileage
      if (kmStart != null) {
        final placeholders = List.filled(_ids.length, '?').join(',');
        final args = <Object?>[kmStart, ..._ids];
        await dao.execRaw('''
          UPDATE sample
          SET result_start_mileage = ?,
              lastupdated_at = CURRENT_TIMESTAMP,
              dirty = 1
          WHERE id IN ($placeholders)
        ''', args);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Résultats collectés: $n / ${_ids.length}')),
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
            title: Text('Collecter résultats — $count sélection(s)'),
          ),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.accept,
            userRole: userRole,
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _kmStartCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kilométrage départ (collecte résultats)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Saisissez le kilométrage';
                    if (int.tryParse(v.trim()) == null)
                      return 'Kilométrage invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dateCtl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Date de collecte',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Sélectionner une date',
                            icon: const Icon(Icons.calendar_month_outlined),
                            onPressed: _pickDate,
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Choisissez la date'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _timeCtl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Heure de collecte',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: "Sélectionner une heure",
                            icon: const Icon(Icons.access_time),
                            onPressed: _pickTime,
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Choisissez l’heure'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text('Enregistrer la collecte'),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
