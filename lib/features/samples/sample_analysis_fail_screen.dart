// lib/features/samples/sample_analysis_fail_screen.dart
import 'package:flutter/material.dart';

import '../../data/db/sample_dao.dart';

class SampleAnalysisFailScreen extends StatefulWidget {
  static const route = '/samples/analysis-fail';
  const SampleAnalysisFailScreen({super.key});

  @override
  State<SampleAnalysisFailScreen> createState() =>
      _SampleAnalysisFailScreenState();
}

class _SampleAnalysisFailScreenState extends State<SampleAnalysisFailScreen> {
  final dao = SampleDao();
  bool _bootstrapped = false;
  bool _saving = false;
  late final List<int> _ids;

  final _dateCtl = TextEditingController();
  final _timeCtl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;

  @override
  void dispose() {
    _dateCtl.dispose();
    _timeCtl.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  void _updateCtrls() {
    _dateCtl.text = _date == null
        ? ''
        : '${_date!.year}-${_two(_date!.month)}-${_two(_date!.day)}';
    _timeCtl.text = _time == null
        ? ''
        : '${_two(_time!.hour)}:${_two(_time!.minute)}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now, // pas de date future
      initialDate: (_date == null || _date!.isAfter(now)) ? now : _date!,
    );
    if (d != null) {
      setState(() {
        _date = d;
        _updateCtrls();
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (t != null) {
      setState(() {
        _time = t;
        _updateCtrls();
      });
    }
  }

  DateTime? _combine(DateTime? d, TimeOfDay? t) {
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    _ids =
        (args?['ids'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [];
    if (_ids.isEmpty) Navigator.pop(context);
  }

  Future<void> _save() async {
    final completed = _combine(_date, _time); // optionnel
    if (completed != null) {
      // Chronologie : pas dans le futur, pas avant l'étape précédente.
      final dateError = await dao.stepDateError(
        completed,
        _ids,
        after: ['collection_date'],
      );
      if (dateError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(dateError)));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final completedIso = _combine(
        _date,
        _time,
      )?.toIso8601String(); // optionnel
      await dao.markAnalysisFailedMany(
        _ids,
        analysisCompletedDate: completedIso,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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
    final n = _bootstrapped ? _ids.length : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifier analyse échouée')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.block_outlined),
              title: Text('Sélection: $n échantillon(s)'),
              subtitle: const Text('Statut → ANALYSIS_FAILED'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Fin analyse (optionnel)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dateCtl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Date',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Sélectionner une date',
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: _pickDate,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _timeCtl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Heure',
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}
