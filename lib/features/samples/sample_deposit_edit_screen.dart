import 'package:flutter/material.dart';
import 'package:lstracker/data/services/auto_sync_manager.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';

class SampleDepositEditScreen extends StatefulWidget {
  static const route = '/samples/deposit-edit';
  const SampleDepositEditScreen({super.key});

  @override
  State<SampleDepositEditScreen> createState() =>
      _SampleDepositEditScreenState();
}

class _SampleDepositEditScreenState extends State<SampleDepositEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _kmCtl = TextEditingController();
  final _dateCtl = TextEditingController();
  final _patientCodeCtl = TextEditingController();
  final _timeCtl = TextEditingController();

  final dao = SampleDao();

  Sample? _sample;
  bool _loading = true;

  // Empêche le reboot à chaque changement d’InheritedWidget (clavier / MediaQuery)
  bool _bootstrapped = false;

  // Meta
  List<Map<String, Object?>> _labs = const [];

  int? _labId;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();

  @override
  void dispose() {
    _kmCtl.dispose();
    _dateCtl.dispose();
    _timeCtl.dispose();
    _patientCodeCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  void _updateDT() {
    String two(int n) => n.toString().padLeft(2, '0');
    _dateCtl.text = '${_date.year}-${two(_date.month)}-${two(_date.day)}';
    _timeCtl.text = '${two(_time.hour)}:${two(_time.minute)}';
  }

  Future<void> _init(int id) async {
    setState(() => _loading = true);
    final db = await AppDatabase.instance.database;
    try {
      final s = await dao.findById(id);
      // Labos sélectionnables + le labo actuel de l'échantillon, pour que la
      // valeur pré-remplie figure toujours dans la liste déroulante.
      final labs = await db.query(
        'lab',
        where: 'selectable = 1 OR id = ?',
        whereArgs: [s?.deliveredLabId ?? s?.destinationLabId ?? -1],
        orderBy: 'name ASC',
      );

      // Pré-remplissage UNIQUEMENT une fois
      _sample = s;

      // Labo pré-sélection : livré -> destination -> premier
      _labId =
          s?.deliveredLabId ??
          s?.destinationLabId ??
          (labs.isNotEmpty
              ? ((labs.first['id'] as int?) ??
                    (labs.first['id'] as num?)?.toInt())
              : null);

      // Date/heure depuis delivered_date si dispo
      if ((s?.deliveredDate ?? '').isNotEmpty) {
        final dt = DateTime.tryParse(s!.deliveredDate!);
        if (dt != null) {
          _date = DateTime(dt.year, dt.month, dt.day);
          _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
        }
      }

      if (s?.endMileage != null) _kmCtl.text = s!.endMileage!.toString();

      setState(() {
        _labs = labs;
        _patientCodeCtl.text = s?.patientIdentifier ?? '';
      });
      _updateDT();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DropdownMenuItem<int>> _labItems() => _labs
      .map(
        (e) => DropdownMenuItem<int>(
          value: (e['id'] as int?) ?? (e['id'] as num?)?.toInt(),
          child: Text(
            (e['name'] ?? '').toString(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      )
      .toList();

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
        _updateDT();
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) {
      setState(() {
        _time = t;
        _updateDT();
      });
    }
  }

  Future<void> _submit() async {
    if (_sample?.id == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (_labId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un laboratoire.')),
      );
      return;
    }
    final dt = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final deliveredIso = dt.toIso8601String();

    // Chronologie : pas dans le futur, pas avant l'étape précédente.
    final dateError = await dao.stepDateError(dt, [_sample!.id!], after: ['collection_date', 'pickup_date']);
    if (dateError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }
    final endKm = _kmCtl.text.trim().isEmpty
        ? null
        : int.tryParse(_kmCtl.text.trim());

    try {
      final n = await dao.updateDeposit(
        id: _sample!.id!,
        labId: _labId!,
        patientCode: _patientCodeCtl.text.trim(),
        deliveredDateIso: deliveredIso,
        endMileage: endKm,
      );
      if (!mounted) return;
      if (n > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dépôt mis à jour.')));
        // Push en arrière-plan (fire-and-forget)
        AutoSyncManager.instance.pushNow();
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Aucune modification.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: const Text('Modifier le dépôt')),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.accept,
            userRole: userRole,
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<int>(
                        value: _labId,
                        isExpanded: true,
                        items: _labItems(),
                        decoration: const InputDecoration(
                          labelText: 'Laboratoire de livraison',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _labId = v),
                        validator: (v) =>
                            v == null ? 'Choisissez un laboratoire' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _patientCodeCtl,
                        decoration: const InputDecoration(
                          labelText: 'Code patient',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Code du patient'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dateCtl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Date de dépôt',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: 'Sélectionner une date',
                                  icon: const Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                  onPressed: _pickDate,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _timeCtl,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Heure de dépôt',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: "Sélectionner une heure",
                                  icon: const Icon(Icons.access_time),
                                  onPressed: _pickTime,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _kmCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Kilométrage d’arrivée (fin collecte)',
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
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Enregistrer'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
