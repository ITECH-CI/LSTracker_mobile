import 'package:flutter/material.dart';
import 'package:lstracker/features/common/account_menu_button.dart';
import 'package:lstracker/features/dashboard/_dashboard_sections.dart';
import 'package:lstracker/features/results_deposit/results_collected_sites_screen.dart';
import 'package:lstracker/features/results_ready/results_ready_labs_screen.dart';
import 'package:lstracker/features/samples/sample_types_screen.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';
import 'package:lstracker/widgets/status_card.dart';
import 'package:lstracker/widgets/sync_queue_action.dart';

import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';

class DashboardLabScreen extends StatefulWidget {
  const DashboardLabScreen({super.key});

  @override
  State<DashboardLabScreen> createState() => _DashboardLabScreenState();
}

class _DashboardLabScreenState extends State<DashboardLabScreen> {
  final dao = SampleDao();
  Map<String, int>? counters;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final c = await dao.dashboardCounters();
    if (!mounted) return;
    setState(() {
      counters = c;
      loading = false;
    });
  }

  void _openStatusList(String status, String title) {
    Navigator.of(context)
        .pushNamed(
          SampleTypesScreen.route,
          arguments: {'status': status, 'title': title},
        )
        .then((_) => _load());
  }

  void _openStatusesList(List<String> statuses, String title) {
    Navigator.of(context)
        .pushNamed(
          SampleTypesScreen.route,
          arguments: {'statuses': statuses, 'title': title},
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final c = counters ?? const <String, int>{};
    final collected = c['collected'] ?? 0;
    final delivered = c['delivered'] ?? 0;
    final received = c['received'] ?? 0;
    final resultReady = c['resultReady'] ?? 0;
    final resultCollected = c['resultCollected'] ?? 0;
    final resultDeposited = c['resultDeposited'] ?? 0;
    final rejected = c['rejected'] ?? 0;
    final analysisFailed = c['analysisFailed'] ?? 0;

    final hasAnyData = collected +
            delivered +
            received +
            resultReady +
            resultCollected +
            resultDeposited +
            rejected +
            analysisFailed >
        0;

    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(
            title: const Text('Tableau de bord — Biologiste'),
            actions: [
              const SyncQueueAction(),
              AccountMenuButton(),
            ],
          ),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.dashboard,
            userRole: userRole,
          ),
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const DashboardInfoNote(),
                // ===== À FAIRE =====
                SectionHeader(
                  title: 'À faire',
                  badge: delivered + received,
                ),
                const SizedBox(height: 10),
                CardsGrid(
                  cards: [
                    StatusCard(
                      label: 'À recevoir',
                      count: delivered,
                      icon: Icons.biotech_outlined,
                      accent: const Color(0xFF0891B2),
                      actionable: true,
                      onTap: () => _openStatusesList(
                        const [
                          SampleStatus.receivedAtDistrictLab,
                          SampleStatus.receivedAtHub,
                          SampleStatus.receivedAtReferenceLab,
                          SampleStatus.receivedAtTbLab,
                        ],
                        'Échantillons déposés au labo',
                      ),
                    ),
                    StatusCard(
                      label: 'À finaliser',
                      count: received,
                      icon: Icons.verified_outlined,
                      accent: const Color(0xFF16A34A),
                      actionable: true,
                      onTap: () => _openStatusesList(
                        const [
                          SampleStatus.acceptedAtDistrictLab,
                          SampleStatus.acceptedAtHub,
                          SampleStatus.acceptedAtReferenceLab,
                          SampleStatus.acceptedAtTbLab,
                        ],
                        'Échantillons acceptés par le labo',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ===== SUIVI =====
                SectionHeader(
                  title: 'Suivi',
                  badge: collected + resultReady + resultCollected +
                      resultDeposited,
                ),
                const SizedBox(height: 10),
                CardsGrid(
                  cards: [
                    StatusCard(
                      label: 'En transit',
                      count: collected,
                      icon: Icons.local_shipping_outlined,
                      accent: const Color(0xFF2563EB),
                      actionable: collected > 0,
                      onTap: collected == 0
                          ? null
                          : () => _openStatusList(
                                SampleStatus.onTransit,
                                'Échantillons en transit',
                              ),
                    ),
                    StatusCard(
                      label: 'Résultats prêts',
                      count: resultReady,
                      icon: Icons.fact_check_outlined,
                      accent: const Color(0xFF7C3AED),
                      actionable: resultReady > 0,
                      onTap: resultReady == 0
                          ? null
                          : () {
                              Navigator.of(context)
                                  .pushNamed(ResultsReadyLabsScreen.route)
                                  .then((_) => _load());
                            },
                    ),
                    StatusCard(
                      label: 'Résultats récupérés',
                      count: resultCollected,
                      icon: Icons.assignment_return_outlined,
                      accent: const Color(0xFFEA580C),
                      actionable: resultCollected > 0,
                      onTap: resultCollected == 0
                          ? null
                          : () {
                              Navigator.of(context)
                                  .pushNamed(ResultsCollectedSitesScreen.route)
                                  .then((_) => _load());
                            },
                    ),
                    StatusCard(
                      label: 'Résultats déposés',
                      count: resultDeposited,
                      icon: Icons.assignment_turned_in_outlined,
                      accent: const Color(0xFF059669),
                      actionable: resultDeposited > 0,
                      onTap: resultDeposited == 0
                          ? null
                          : () => _openStatusList(
                                SampleStatus.resultOnSite,
                                'Résultats déposés',
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ===== ANOMALIES (conditionnel) =====
                if (rejected > 0 || analysisFailed > 0) ...[
                  SectionHeader(
                    title: 'Anomalies',
                    badge: rejected + analysisFailed,
                    accent: Colors.red.shade700,
                  ),
                  const SizedBox(height: 10),
                  CardsGrid(
                    cards: [
                      if (rejected > 0)
                        StatusCard(
                          label: 'Rejetés',
                          count: rejected,
                          icon: Icons.block_outlined,
                          accent: Colors.red.shade600,
                          actionable: true,
                          onTap: () => _openStatusList(
                            SampleStatus.nonConform,
                            'Échantillons rejetés',
                          ),
                        ),
                      if (analysisFailed > 0)
                        StatusCard(
                          label: 'Analyses échouées',
                          count: analysisFailed,
                          icon: Icons.report_problem_outlined,
                          accent: Colors.orange.shade700,
                          actionable: true,
                          onTap: () => _openStatusList(
                            SampleStatus.analysisFailed,
                            'Analyses échouées',
                          ),
                        ),
                    ],
                  ),
                ],

                if (!loading && !hasAnyData) ...[
                  const SizedBox(height: 16),
                  const EmptyDashboardState(
                    title: 'Aucune activité pour le moment',
                    subtitle:
                        'Les échantillons et résultats s\'afficheront ici après synchronisation.',
                  ),
                ],

                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
    );
  }
}
