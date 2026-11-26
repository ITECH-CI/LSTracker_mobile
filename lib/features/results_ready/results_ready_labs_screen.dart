import 'package:flutter/material.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';
import 'results_ready_types_screen.dart';

class ResultsReadyLabsScreen extends StatefulWidget {
  static const route = '/results-ready/labs';
  const ResultsReadyLabsScreen({super.key});

  @override
  State<ResultsReadyLabsScreen> createState() => _ResultsReadyLabsScreenState();
}

class _ResultsReadyLabsScreenState extends State<ResultsReadyLabsScreen> {
  final dao = SampleDao();
  bool _loading = true;
  String? _error;

  // [{lab_id, total, lab_name}]
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final counts = await dao.countsReadyByLab();
      final db = await AppDatabase.instance.database;

      // map id -> name
      final labs = await db.query('lab');
      final labNames = <int, String>{};
      for (final r in labs) {
        final id = (r['id'] as int?) ?? (r['id'] as num?)?.toInt();
        if (id != null) labNames[id] = (r['name'] ?? '').toString();
      }

      final merged = counts.map((r) {
        final id = (r['lab_id'] as int?) ?? (r['lab_id'] as num?)?.toInt();
        final total =
            (r['total'] as int?) ?? (r['total'] as num?)?.toInt() ?? 0;
        return {
          'lab_id': id,
          'total': total,
          'lab_name': (id != null ? (labNames[id] ?? 'Labo #$id') : '-'),
        };
      }).toList();

      if (!mounted) return;
      setState(() => _rows = merged);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTypes(int labId, String labName) {
    Navigator.of(context).pushNamed(
      ResultsReadyTypesScreen.route,
      arguments: {'labId': labId, 'labName': labName},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: const Text('Résultats prêts (par labo)')),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.accept,
            userRole: userRole,
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Aucun résultat prêt trouvé.\n'
                          'Les laboratoires n’ont pas encore publié de résultats.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final labId = (r['lab_id'] as int?) ?? 0;
                      final name = (r['lab_name'] ?? '-').toString();
                      final total = (r['total'] as int?) ?? 0;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.local_hospital_outlined),
                          title: Text(name),
                          subtitle: Text('Résultats prêts: $total'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openTypes(labId, name),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
