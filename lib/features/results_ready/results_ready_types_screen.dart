import 'package:flutter/material.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/sample_dao.dart';
import 'results_ready_list_screen.dart';

class ResultsReadyTypesScreen extends StatefulWidget {
  static const route = '/results-ready/types';
  const ResultsReadyTypesScreen({super.key});

  @override
  State<ResultsReadyTypesScreen> createState() =>
      _ResultsReadyTypesScreenState();
}

class _ResultsReadyTypesScreenState extends State<ResultsReadyTypesScreen> {
  final dao = SampleDao();
  bool _loading = true;
  String? _error;

  late int _labId;
  late String _labName;

  // [{sample_type, total}]
  List<Map<String, Object?>> _rows = const [];

  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    _labId = (args?['labId'] as int?) ?? 0;
    _labName = (args?['labName'] as String?) ?? 'Labo';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final counts = await dao.countsReadyByTypeForLab(_labId);
      if (!mounted) return;
      setState(() => _rows = counts);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openList(String type) {
    Navigator.of(context).pushNamed(
      ResultsReadyListScreen.route,
      arguments: {'labId': _labId, 'labName': _labName, 'type': type},
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Types : $_labName';
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: Text(title)),
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
                          Icons.category_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Aucun type d’échantillon trouvé pour ce laboratoire.\n'
                          'Les résultats ne sont pas encore disponibles.',
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
                      final type = (r['sample_type'] ?? 'Autre').toString();
                      final total = (r['total'] as int?) ?? 0;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.biotech_outlined),
                          title: Text(type),
                          subtitle: Text('Résultats prêts: $total'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openList(type),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
