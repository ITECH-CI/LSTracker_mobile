// lib/features/samples/sample_result_ready_screen.dart
import 'package:flutter/material.dart';
import 'package:lstracker/data/db/app_database.dart';
import 'package:lstracker/data/db/sample_dao.dart';
import 'package:lstracker/data/models/sample.dart';
import 'package:lstracker/data/services/auto_sync_manager.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

/// ------- Widget réutilisable: champ Date + Heure --------
class DateTimePickerField extends StatefulWidget {
  final String dateLabel;
  final String timeLabel;
  final DateTime? initial;
  final ValueChanged<DateTime> onChanged;
  final FormFieldValidator<String>? validator;

  const DateTimePickerField({
    super.key,
    required this.dateLabel,
    required this.timeLabel,
    required this.onChanged,
    this.initial,
    this.validator,
  });

  @override
  State<DateTimePickerField> createState() => _DateTimePickerFieldState();
}

class _DateTimePickerFieldState extends State<DateTimePickerField> {
  late DateTime _dt;
  final _dateCtl = TextEditingController();
  final _timeCtl = TextEditingController();
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _dt = widget.initial ?? DateTime.now();
    _syncCtrls();
  }

  @override
  void didUpdateWidget(covariant DateTimePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != null && widget.initial != oldWidget.initial) {
      _dt = widget.initial!;
      _syncCtrls();
    }
  }

  @override
  void dispose() {
    _dateCtl.dispose();
    _timeCtl.dispose();
    super.dispose();
  }

  void _unfocus() {
    final scope = FocusScope.of(context);
    if (!scope.hasPrimaryFocus && scope.hasFocus) scope.unfocus();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  void _syncCtrls() {
    _dateCtl.text = '${_dt.year}-${_two(_dt.month)}-${_two(_dt.day)}';
    _timeCtl.text = '${_two(_dt.hour)}:${_two(_dt.minute)}';
  }

  Future<void> _pickDate() async {
    if (_picking) return;
    _picking = true;
    _unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _dt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _dt.hour,
          _dt.minute,
        );
        _syncCtrls();
      });
      widget.onChanged(_dt);
    }
    _picking = false;
  }

  Future<void> _pickTime() async {
    if (_picking) return;
    _picking = true;
    _unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _dt.hour, minute: _dt.minute),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _dt = DateTime(
          _dt.year,
          _dt.month,
          _dt.day,
          picked.hour,
          picked.minute,
        );
        _syncCtrls();
      });
      widget.onChanged(_dt);
    }
    _picking = false;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _dateCtl,
            readOnly: true,
            onTap: _pickDate,
            decoration: InputDecoration(
              labelText: widget.dateLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Sélectionner une date',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: _pickDate,
              ),
            ),
            validator: widget.validator,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _timeCtl,
            readOnly: true,
            onTap: _pickTime,
            decoration: InputDecoration(
              labelText: widget.timeLabel,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: "Sélectionner une heure",
                icon: const Icon(Icons.access_time),
                onPressed: _pickTime,
              ),
            ),
            validator: widget.validator,
          ),
        ),
      ],
    );
  }
}

/// --------- Écran: déclarer “Résultat prêt” pour 1 ou plusieurs échantillons ---------
///
/// Arguments de route : `{'id': int}` (un échantillon) ou `{'ids': List<int>}`
/// (lot). En lot, les mêmes dates s'appliquent à tous les échantillons
/// sélectionnés.
class SampleResultReadyScreen extends StatefulWidget {
  static const route = '/samples/result-ready';
  const SampleResultReadyScreen({super.key});

  @override
  State<SampleResultReadyScreen> createState() =>
      _SampleResultReadyScreenState();
}

class _SampleResultReadyScreenState extends State<SampleResultReadyScreen> {
  final _formKey = GlobalKey<FormState>();
  final dao = SampleDao();

  bool _bootstrapped = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Sample> _samples = const [];

  // Infos affichées (cas d'un seul échantillon)
  String? _siteName;

  // Dates (via pickers). Initialisées à la valeur affichée par le champ
  // (existante, sinon maintenant) : ce qui est vu est ce qui est enregistré.
  DateTime? _analysisEnd;
  DateTime? _releasedAt; // obligatoire

  bool get _isBatch => _samples.length > 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final single = (args?['id'] as int?) ?? (args?['sampleId'] as int?);
    final ids =
        (args?['ids'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        (single != null ? [single] : const <int>[]);
    if (ids.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Identifiant échantillon manquant.';
      });
      return;
    }
    _load(ids);
  }

  Future<void> _load(List<int> ids) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final samples = <Sample>[];
      for (final id in ids) {
        final s = await dao.findById(id);
        if (s != null) samples.add(s);
      }
      if (samples.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Échantillon introuvable.';
        });
        return;
      }

      // Résoudre nom du site si besoin (un seul échantillon)
      String? siteName;
      if (samples.length == 1) {
        final s = samples.first;
        siteName = s.fromSiteName;
        if ((siteName == null || siteName.isEmpty) && s.fromSiteId != null) {
          final db = await AppDatabase.instance.database;
          final rs = await db.query(
            'site',
            where: 'id = ?',
            whereArgs: [s.fromSiteId],
            limit: 1,
          );
          if (rs.isNotEmpty) {
            siteName = (rs.first['name'] ?? '').toString();
          }
        }
      }

      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _samples = samples;
        _siteName = siteName;
        // Pré-remplir si déjà saisi (un seul échantillon), sinon maintenant.
        final first = samples.length == 1 ? samples.first : null;
        _analysisEnd = _parseIso(first?.analysisCompletedDate) ?? now;
        _releasedAt = _parseIso(first?.analysisReleasedDate) ?? now;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parseIso(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ids = _samples.where((s) => s.id != null).map((s) => s.id!).toList();
    if (ids.isEmpty) return;

    // releasedAt est obligatoire
    if (_releasedAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La date de validation biologique est obligatoire.'),
        ),
      );
      return;
    }
    if (_analysisEnd != null && _analysisEnd!.isAfter(_releasedAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "La fin d'analyse ne peut pas être postérieure à la validation.",
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await dao.markResultReadyMany(
        ids,
        analysisCompletedDate: _analysisEnd?.toIso8601String(),
        analysisReleasedDate: _releasedAt!.toIso8601String(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ids.length > 1
                ? '${ids.length} résultats marqués comme prêts.'
                : 'Résultat marqué comme prêt.',
          ),
        ),
      );
      // Push en arrière-plan
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

  Widget _infoTile(String label, String? value, {IconData? icon}) {
    final v = (value == null || value.trim().isEmpty) ? '—' : value;
    return ListTile(
      dense: true,
      leading: icon != null ? Icon(icon) : null,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(v, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  String _labelFor(Sample s) {
    final main = s.labNumber?.isNotEmpty == true
        ? s.labNumber!
        : (s.patientIdentifier?.isNotEmpty == true
              ? s.patientIdentifier!
              : s.uuid);
    final patient =
        s.labNumber?.isNotEmpty == true &&
            s.patientIdentifier?.isNotEmpty == true
        ? ' · ${s.patientIdentifier}'
        : '';
    return '$main$patient';
  }

  Widget _singleHeader(Sample s) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _infoTile('Site de collecte', _siteName, icon: Icons.place_outlined),
          const Divider(height: 1),
          _infoTile(
            'Code patient',
            s.patientIdentifier,
            icon: Icons.badge_outlined,
          ),
          const Divider(height: 1),
          _infoTile('Numéro laboratoire', s.labNumber, icon: Icons.numbers),
        ],
      ),
    );
  }

  Widget _batchHeader() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: const Icon(Icons.checklist),
        title: Text(
          '${_samples.length} échantillons sélectionnés',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Les mêmes dates seront appliquées à tous.'),
        children: [
          for (final s in _samples)
            ListTile(
              dense: true,
              leading: const Icon(Icons.science_outlined, size: 20),
              title: Text(_labelFor(s)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final role = AuthUtils.roleOrNull() ?? 'ADMIN';
    final title = _isBatch
        ? 'Résultats prêts (${_samples.length})'
        : 'Résultat prêt \n ${_samples.isEmpty ? '' : _labelFor(_samples.first)}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      bottomNavigationBar: GlobalBottomNav(
        current: BottomTab.accept,
        userRole: role,
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
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Infos en-tête
                  _isBatch ? _batchHeader() : _singleHeader(_samples.first),
                  const SizedBox(height: 12),

                  // Fin analyse
                  DateTimePickerField(
                    key: const ValueKey('analysis-end'),
                    dateLabel: 'Fin analyse (date)',
                    timeLabel: 'Fin analyse (heure)',
                    initial: _analysisEnd,
                    onChanged: (dt) => _analysisEnd = dt,
                  ),
                  const SizedBox(height: 12),

                  // Validation biologique (obligatoire)
                  DateTimePickerField(
                    key: const ValueKey('released-at'),
                    dateLabel: 'Validation biologique (date)',
                    timeLabel: 'Validation biologique (heure)',
                    initial: _releasedAt,
                    onChanged: (dt) => _releasedAt = dt,
                    validator: (_) =>
                        _releasedAt == null ? 'Obligatoire' : null,
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isBatch
                            ? 'Marquer ${_samples.length} résultats prêts'
                            : 'Enregistrer',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
