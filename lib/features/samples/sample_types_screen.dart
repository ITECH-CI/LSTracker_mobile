import 'package:flutter/material.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';

import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';
import 'sample_list_screen.dart';

class SampleTypesScreen extends StatefulWidget {
  static const route = '/samples/types';
  const SampleTypesScreen({super.key});

  @override
  State<SampleTypesScreen> createState() => _SampleTypesScreenState();
}

class _SampleTypesScreenState extends State<SampleTypesScreen> {
  final dao = SampleDao();

  // Peut être un seul statut OU plusieurs
  String? status; // ex: 'ON_TRANSIT'
  List<String>? statuses; // ex: ['RECEIVED_AT_HUB', 'RECEIVED_AT_TB_LAB']
  String? title;

  bool loading = true;
  List<Map<String, Object?>> rows = const [];

  // Types supportés (affichés même si 0)
  final supportedSampleTypes = const [
    'BI',
    'BS',
    'CV',
    'EID',
    'PrEP',
    'IVSA',
    'TB',
    'HPV',
    'Autre',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

    // Si l'appelant fournit 'statuses' (List<String>), on l’utilise
    final rawStatuses = args?['statuses'];
    if (rawStatuses is List) {
      statuses = rawStatuses.map((e) => e.toString()).toList();
    } else {
      statuses = null;
    }

    // Compat: si un seul 'status' (String) est passé, on continue de le supporter
    status = (args?['status'] as String?) ?? status;
    title = args?['title'] as String?;

    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    // Agrégation des compteurs par type
    final counts = <String, int>{};

    if (statuses != null && statuses!.isNotEmpty) {
      // Multi-statuts : on agrège en additionnant
      for (final st in statuses!) {
        final data = await dao.countsByType(status: st);
        for (final r in data) {
          final type = (r['sample_type'] ?? 'Autre').toString();
          final total =
              (r['total'] as int?) ?? (r['total'] as num?)?.toInt() ?? 0;
          counts[type] = (counts[type] ?? 0) + total;
        }
      }
    } else {
      // Statut unique (compat)
      final st = status ?? SampleStatus.onTransit;
      final data = await dao.countsByType(status: st);
      for (final r in data) {
        final type = (r['sample_type'] ?? 'Autre').toString();
        final total =
            (r['total'] as int?) ?? (r['total'] as num?)?.toInt() ?? 0;
        counts[type] = total;
      }
    }

    // Liste finale: tous les types supportés (0 si absent)
    final all = supportedSampleTypes
        .map((t) => {'sample_type': t, 'total': counts[t] ?? 0})
        .toList();

    if (!mounted) return;
    setState(() {
      rows = all;
      loading = false;
    });
  }

  Color _chipColor(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.primaryContainer;
  Color _chipTextColor(BuildContext ctx) =>
      Theme.of(ctx).colorScheme.onPrimaryContainer;

  String _titleText() {
    if (title != null && title!.trim().isNotEmpty) return title!;
    if (statuses != null && statuses!.isNotEmpty) {
      // Affiche un résumé multi-statuts
      return 'Échantillons (${statuses!.length} statuts)';
    }
    return 'Échantillons : ${SampleStatus.label(status ?? SampleStatus.onTransit)}';
  }

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: Text(_titleText())),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.only(top: 16,bottom: 16),
                    itemCount: rows.length,// + 1, // +1 pour le hint en tête
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      //if (i == 0) return _statusHint(ctx);

                      final r = rows[i]; //rows[i - 1];
                      final type = (r['sample_type'] ?? 'Autre').toString();
                      final total =
                          (r['total'] as int?) ??
                          (r['total'] as num?)?.toInt() ??
                          0;

                      return Card(
                        elevation: 1.5,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          onTap: () {
                            // On envoie à la fois 'status' (fallback) et 'statuses' (si multi)
                            final args = <String, dynamic>{'type': type};
                            if (statuses != null && statuses!.isNotEmpty) {
                              args['statuses'] = statuses;
                            } else if (status != null) {
                              args['status'] = status;
                            }
                            Navigator.of(context).pushNamed(
                              SampleListScreen.route,
                              arguments: args,
                            );
                          },
                          leading: CircleAvatar(
                            radius: 24,
                            child: Text(
                              type.length >= 2
                                  ? type.substring(0, 2).toUpperCase()
                                  : type.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            'Échantillons $type',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _chipColor(ctx),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$total',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _chipTextColor(ctx),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
    );
  }
}
