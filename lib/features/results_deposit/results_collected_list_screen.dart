import 'package:flutter/material.dart';
import 'package:lstracker/data/services/log_service.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/utils/custom_date_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';
import 'package:lstracker/widgets/sample_list_item.dart';
import 'package:lstracker/widgets/skeleton.dart';

import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';
import 'results_deposit_form_screen.dart';

class ResultsCollectedListScreen extends StatefulWidget {
  static const route = '/results-collected/list';
  const ResultsCollectedListScreen({super.key});

  @override
  State<ResultsCollectedListScreen> createState() =>
      _ResultsCollectedListScreenState();
}

class _ResultsCollectedListScreenState
    extends State<ResultsCollectedListScreen> {
  final dao = SampleDao();

  bool _bootstrapped = false;
  bool _loading = true;
  String? _error;

  late int _siteId;
  late String _siteLabel;
  late String _siteName;

  final _searchCtl = TextEditingController();
  List<Sample> _items = const [];
  final Set<int> _selected = {};

  // Pagination (cf. SampleListScreen).
  static const int _pageSize = 50;
  final ScrollController _scrollCtl = ScrollController();
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtl.hasClients) return;
    final remaining =
        _scrollCtl.position.maxScrollExtent - _scrollCtl.position.pixels;
    if (remaining < 200 && !_loadingMore && _hasMore && !_loading) {
      _loadMore();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    _siteId = (args?['siteId'] as int?) ?? 0;
    _siteName = (args?['siteName'] as String?) ?? '';
    _siteLabel = (args?['siteLabel'] as String?) ?? 'Site';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _offset = 0;
      _hasMore = true;
      _items = const [];
    });
    try {
      final items = await dao.listCollectedBySite(
        siteId: _siteId,
        siteName: _siteName,
        query: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected.clear();
        _offset = items.length;
        _hasMore = items.length == _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await dao.listCollectedBySite(
        siteId: _siteId,
        siteName: _siteName,
        query: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...next];
        _offset += next.length;
        _hasMore = next.length == _pageSize;
      });
    } catch (e, st) {
      LogService.instance.warn(
        'UI',
        'pagination résultats récupérés: échec page (offset=$_offset, site=$_siteId)',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chargement interrompu. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toggle(int id, bool v) {
    setState(() {
      if (v) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  Future<void> _openDeposit({required Set<int> ids}) async {
    if (ids.isEmpty) return;
    final changed = await Navigator.of(context).pushNamed(
      ResultsDepositFormScreen.route,
      arguments: {
        'ids': ids.toList(),
        'siteId': _siteId,
        'siteLabel': _siteLabel,
      },
    );
    if (changed == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dépôt enregistré.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDeposit = _selected.isNotEmpty;
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Résultats récupérés'),
                Text(_siteLabel, style: const TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              if (_items.isNotEmpty && AuthUtils.canDoConveyorTasks(userRole))
                TextButton.icon(
                  onPressed: () => _openDeposit(
                    ids: _items
                        .where((e) => e.id != null)
                        .map((e) => e.id!)
                        .toSet(),
                  ),
                  icon: const Icon(
                    Icons.done_all,
                    color: Color.fromARGB(255, 54, 1, 52),
                  ),
                  label: const Text(
                    'Tout déposer',
                    style: TextStyle(color: Color.fromARGB(255, 13, 13, 13)),
                  ),
                ),
            ],
          ),
          floatingActionButton: canDeposit && AuthUtils.canDoConveyorTasks(userRole)
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  label: const Text('Déposer sélection'),
                  onPressed: () => _openDeposit(ids: _selected),
                )
              : null,
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),

          body: _loading
              ? const SampleListSkeleton()
              : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Aucun résultat récupéré pour ce site.\n'
                          'Rien à déposer pour le moment.',
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
                    controller: _scrollCtl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i >= _items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final s = _items[i];
                      final id = s.id!;
                      final dateTxt = (s.collectionDate ?? '').isNotEmpty
                          ? CustomDateUtils.toHumanReadable(s.collectionDate)
                          : null;
                      final lines = <SampleInfoLine>[
                        if ((s.patientIdentifier ?? '').isNotEmpty)
                          SampleInfoLine(Icons.person_outline,
                              'Patient: ${s.patientIdentifier}'),
                        if (SampleListItem.prelevementText(
                                s.sampleNature, dateTxt) !=
                            null)
                          SampleInfoLine(
                              Icons.water_drop_outlined,
                              SampleListItem.prelevementText(
                                  s.sampleNature, dateTxt)!,
                              color: SampleListItem.typeColor(s.sampleType)),
                        if ((s.labNumber ?? '').isNotEmpty)
                          SampleInfoLine(Icons.tag, 'N° Labo: ${s.labNumber}'),
                        if ((s.analysisReleasedDate ?? '').isNotEmpty)
                          SampleInfoLine(
                              Icons.verified_outlined,
                              'Validation: ${CustomDateUtils.toHumanReadable(s.analysisReleasedDate)}',
                              color: Colors.green),
                      ];

                      return SampleListItem(
                        title: s.sampleIdentifier?.isNotEmpty == true
                            ? s.sampleIdentifier!
                            : s.uuid,
                        sampleType: s.sampleType,
                        lines: lines,
                        selected: _selected.contains(id),
                        onSelectedChanged: (v) => _toggle(id, v ?? false),
                        onTap: () => _toggle(id, !_selected.contains(id)),
                      );
                    },
                  ),
                ),
    );
  }
}
