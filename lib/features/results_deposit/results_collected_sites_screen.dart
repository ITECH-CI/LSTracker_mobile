import 'package:flutter/material.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';
import 'results_collected_list_screen.dart';

class ResultsCollectedSitesScreen extends StatefulWidget {
  static const route = '/results-collected/sites';
  const ResultsCollectedSitesScreen({super.key});

  @override
  State<ResultsCollectedSitesScreen> createState() =>
      _ResultsCollectedSitesScreenState();
}

class _ResultsCollectedSitesScreenState
    extends State<ResultsCollectedSitesScreen> {
  final dao = SampleDao();
  bool _loading = true;
  String? _error;

  // [{site_id, total, site_name, site_code}]
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
      final counts = await dao.countsCollectedBySite();
      // map site id -> {name, code}
      final db = await AppDatabase.instance.database;
      final sites = await db.query('site'); // id, name, dhis_code, circuit_id
      final siteName = <int, String>{};
      final siteCode = <int, String>{};
      for (final r in sites) {
        final sid = (r['id'] as int?) ?? (r['id'] as num?)?.toInt();
        if (sid != null) {
          siteName[sid] = (r['name'] ?? '').toString();
          siteCode[sid] = (r['dhis_code'] ?? '').toString();
        }
      }

      final merged = counts.map((r) {
        final total =
            (r['total'] as int?) ?? (r['total'] as num?)?.toInt() ?? 0;
        final nameFromCount = (r['site_name'] ?? '').toString();

        // Initialiser les valeurs du site par défaut
        String finalName;
        String finalCode;
        int? finalSid;

        if (nameFromCount == 'site_inconnu') {
          // Cas spécial pour 'site_inconnu'
          finalName = 'Site Inconnu';
          finalCode = 'N/A';
          finalSid = null; // Pas d'ID de site associé
        } else {
          // Cas normal : recherche par ID de site
          finalSid = (r['site_id'] as int?) ?? (r['site_id'] as num?)?.toInt();
          finalName = siteName[finalSid] ?? nameFromCount;
          finalCode = siteCode[finalSid] ?? '';
        }

        return {
          'site_id': finalSid,
          'total': total,
          'name': finalName,
          'dhis_code': finalCode,
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

  void _openSite(int siteId, String siteLabel, String name) {
    Navigator.of(context).pushNamed(
      ResultsCollectedListScreen.route,
      arguments: {'siteId': siteId, 'siteLabel': siteLabel, 'siteName': name},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: const Text('Résultats récupérés au laboratoire, par site')),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
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
                          'Aucun résultat récupéré en attente de dépôt.\n'
                          'Sélectionnez plus tard lorsque des résultats seront disponibles.',
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
                      final sid = (r['site_id'] as int?) ?? 0;
                      final name = (r['name'] ?? '—').toString();
                      final code = (r['dhis_code'] ?? '').toString();
                      final total = (r['total'] as int?) ?? 0;
                      final label = code.isNotEmpty ? '$code — $name' : name;

                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(label),
                          subtitle: Text('Résultats récupérés: $total'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openSite(sid, label, name),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
