import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lstracker/data/db/lab_dao.dart';
import 'package:lstracker/data/services/log_service.dart';
import 'package:lstracker/features/samples/sample_analysis_fail_screen.dart';
import 'package:lstracker/features/samples/sample_result_ready_screen.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/utils/custom_date_utils.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';
import 'package:lstracker/widgets/sample_list_item.dart';
import 'package:lstracker/widgets/skeleton.dart';

import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';
import 'sample_accept_screen.dart';
import 'sample_deposit_edit_screen.dart';
import 'sample_deposit_screen.dart';
import 'sample_detail_screen.dart';
import 'sample_edit_screen.dart';
import 'sample_reject_screen.dart';
import 'sample_result_collect_screen.dart';

class SampleListScreen extends StatefulWidget {
  static const route = '/samples/list';
  const SampleListScreen({super.key});

  @override
  State<SampleListScreen> createState() => _SampleListScreenState();
}

class _SampleListScreenState extends State<SampleListScreen> {
  final dao = SampleDao();
  final labDao = LabDao();
  Map<int, String> labNames = {};
  String? status;
  List<String>? statuses;
  String type = 'Autre';

  final _searchCtl = TextEditingController();
  Timer? _debounce;

  bool loading = true;
  List<Sample> items = const [];

  // Pagination
  // Charge 50 lignes par page : compromis confortable entre vitesse de la
  // requête SQLite et fluidité du scroll. Le ScrollController détecte
  // l'approche du bas (200 px) pour précharger la suite.
  static const int _pageSize = 50;
  final ScrollController _scrollCtl = ScrollController();
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  // Sélection
  bool selectMode = false;
  final Set<int> selectedIds = {};

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    statuses = (args?['statuses'] as List?)?.map((e) => e.toString()).toList();
    status = (args?['status'] as String?) ?? (statuses?.first);
    type = (args?['type'] as String?) ?? type;
    _load();
  }

  @override
  void dispose() {
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    _searchCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtl.hasClients) return;
    final remaining =
        _scrollCtl.position.maxScrollExtent - _scrollCtl.position.pixels;
    if (remaining < 200 && !_loadingMore && _hasMore && !loading) {
      _loadMore();
    }
  }

  /// (Re)charge la première page. Remet la pagination à zéro et
  /// nettoie la sélection des éléments qui auraient disparu.
  Future<void> _load() async {
    setState(() {
      loading = true;
      _offset = 0;
      _hasMore = true;
      items = const [];
    });

    final data = await dao.listByTypeAndStatus(
      type: type,
      status: status!,
      statuses: statuses,
      query: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
      limit: _pageSize,
      offset: 0,
    );

    final ids = data
        .where((s) => s.destinationLabId != null)
        .map((s) => s.destinationLabId!)
        .toSet();
    final names = await labDao.namesByIds(ids);

    if (!mounted) return;
    setState(() {
      items = data;
      labNames = names;
      loading = false;
      _offset = data.length;
      _hasMore = data.length == _pageSize;
      // si des éléments ont disparu, nettoie la sélection
      selectedIds.removeWhere((id) => items.indexWhere((s) => s.id == id) < 0);
      if (selectedIds.isEmpty) selectMode = false;
    });
  }

  /// Charge la page suivante et l'append à `items`. No-op si une autre
  /// charge est déjà en cours ou si on a atteint la fin.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final next = await dao.listByTypeAndStatus(
        type: type,
        status: status!,
        statuses: statuses,
        query: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        limit: _pageSize,
        offset: _offset,
      );

      final newLabIds = next
          .where((s) => s.destinationLabId != null)
          .map((s) => s.destinationLabId!)
          .where((id) => !labNames.containsKey(id))
          .toSet();
      final newLabNames = newLabIds.isEmpty
          ? <int, String>{}
          : await labDao.namesByIds(newLabIds);

      if (!mounted) return;
      setState(() {
        items = [...items, ...next];
        labNames = {...labNames, ...newLabNames};
        _offset += next.length;
        _hasMore = next.length == _pageSize;
      });
    } catch (e, st) {
      LogService.instance.warn(
        'UI',
        'pagination échantillons: échec page (offset=$_offset, type=$type, status=$status)',
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

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  // --- Sélection ---
  void _enterSelectModeWith(Sample s) {
    if (s.id == null) return;
    setState(() {
      selectMode = true;
      selectedIds
        ..clear()
        ..add(s.id!);
    });
  }

  void _toggleSelection(Sample s) {
    if (s.id == null) return;
    setState(() {
      if (selectedIds.contains(s.id)) {
        selectedIds.remove(s.id);
        if (selectedIds.isEmpty) selectMode = false;
      } else {
        selectedIds.add(s.id!);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      selectedIds.clear();
      selectMode = false;
    });
  }

  bool get _isCollected => status == SampleStatus.onTransit;
  bool get _isDelivered =>
      (status == SampleStatus.receivedAtDistrictLab ||
      status == SampleStatus.receivedAtHub ||
      status == SampleStatus.receivedAtReferenceLab ||
      status == SampleStatus.receivedAtTbLab);
  bool get _isAccepted =>
      (status == SampleStatus.acceptedAtDistrictLab ||
      status == SampleStatus.acceptedAtHub ||
      status == SampleStatus.acceptedAtReferenceLab ||
      status == SampleStatus.acceptedAtTbLab);
  bool get _canEditOne => selectedIds.length == 1;
  bool get _canDeleteOne => selectedIds.length == 1;
  bool get _canDepositMany => selectedIds.isNotEmpty;

  void _actionDepositMany() async {
    final ids = selectedIds.toList();
    final changed = await Navigator.of(
      context,
    ).pushNamed(SampleDepositScreen.route, arguments: {'ids': ids});
    _clearSelection();
    if (changed == true) {
      await _load();
    }
  }

  void _actionEditOne() async {
    final id = selectedIds.first;
    final changed = await Navigator.of(
      context,
    ).pushNamed(SampleEditScreen.route, arguments: {'id': id});
    _clearSelection();
    if (changed == true) {
      await _load();
    }
  }

  void _actionDeleteOne() async {
    final id = selectedIds.first;
    final sample = items.firstWhere((s) => s.id == id);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer'),
        content: Text(
          'Supprimer cet échantillon ?\n${sample.sampleIdentifier ?? sample.uuid}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => loading = true);
    try {
      final n = await dao.deleteById(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 1 ? 'Échantillon supprimé' : 'Aucune ligne supprimée',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      _clearSelection();
      await _load();
    }
  }

  // Modifier le dépôt (sélection unique)
  void _actionEditDepositOne() async {
    if (selectedIds.length != 1) return;
    final id = selectedIds.first;
    final changed = await Navigator.of(
      context,
    ).pushNamed(SampleDepositEditScreen.route, arguments: {'id': id});
    _clearSelection();
    if (changed == true) await _load();
  }

  // Accepter (sélection unique)
  void _actionAcceptOne() async {
    if (selectedIds.length != 1) return;
    final id = selectedIds.first;
    final changed = await Navigator.of(
      context,
    ).pushNamed(SampleAcceptScreen.route, arguments: {'id': id});
    _clearSelection();
    if (changed == true) await _load();
  }

  // Rejeter (sélection multiple OK)
  void _actionRejectMany() async {
    if (selectedIds.isEmpty) return;
    final ids = selectedIds.toList();
    final changed = await Navigator.of(
      context,
    ).pushNamed(SampleRejectScreen.route, arguments: {'ids': ids});
    _clearSelection();
    if (changed == true) await _load();
  }

  void _actionResultReadyMany() async {
    if (selectedIds.isEmpty) return;
    final changed = await Navigator.of(context).pushNamed(
      SampleResultReadyScreen.route,
      arguments: {'ids': selectedIds.toList()},
    );
    _clearSelection();
    if (changed == true) await _load();
  }

  void _actionAnalysisFailedMany() async {
    if (selectedIds.isEmpty) return;
    final changed = await Navigator.of(context).pushNamed(
      SampleAnalysisFailScreen.route,
      arguments: {'ids': selectedIds.toList()},
    );
    _clearSelection();
    if (changed == true) await _load();
  }

  void _actionCollectResultsMany() async {
    if (selectedIds.isEmpty) return;
    final changed = await Navigator.of(context).pushNamed(
      SampleResultCollectScreen.route,
      arguments: {'ids': selectedIds.toList()},
    );
    _clearSelection();
    if (changed == true) await _load(); // recharger la liste
  }

  PreferredSizeWidget _buildAppBar(String userRole) {
    final n = selectedIds.length;
    final conveyorTasks = AuthUtils.canDoConveyorTasks(userRole);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
        tooltip: 'Annuler',
      ),
      title: Text('$n sélectionné${n > 1 ? 's' : ''}'),
      actions: [
        if (userRole != "USER") ...[
          if (_isCollected && conveyorTasks) ...[
            IconButton(
              tooltip: 'Déposer au labo',
              onPressed: _canDepositMany ? _actionDepositMany : null,
              icon: const Icon(Icons.biotech_outlined),
            ),
            IconButton(
              tooltip: 'Modifier',
              onPressed: _canEditOne ? _actionEditOne : null,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Supprimer',
              onPressed: _canDeleteOne ? _actionDeleteOne : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ] else if (_isAccepted) ...[
            IconButton(
              tooltip: 'Résultat prêt',
              onPressed: selectedIds.isNotEmpty
                  ? _actionResultReadyMany
                  : null,
              icon: const Icon(Icons.assignment_turned_in_outlined),
            ),
            IconButton(
              tooltip: 'Analyses échouées',
              onPressed: selectedIds.isNotEmpty
                  ? _actionAnalysisFailedMany
                  : null,
              icon: const Icon(Icons.report_problem_outlined),
            ),
          ] else if (_isDelivered) ...[
            IconButton(
              tooltip: 'Accepter',
              onPressed: _canEditOne ? _actionAcceptOne : null,
              icon: const Icon(Icons.verified_outlined),
            ),
            IconButton(
              tooltip: 'Rejeter',
              onPressed: selectedIds.isNotEmpty ? _actionRejectMany : null,
              icon: const Icon(Icons.block_outlined),
            ),
            if (conveyorTasks)
              IconButton(
                tooltip: 'Modifier le dépôt',
                onPressed: _canEditOne ? _actionEditDepositOne : null,
                icon: const Icon(Icons.edit_outlined),
              ),
          ] else if (status == SampleStatus.analysisDone && conveyorTasks) ...[
            IconButton(
              tooltip: 'Collecter résultats',
              onPressed: selectedIds.isNotEmpty
                  ? _actionCollectResultsMany
                  : null,
              icon: const Icon(Icons.assignment_turned_in_outlined),
            ),
          ],
        ],
      ],
    );
  }

  Widget _tileFor(Sample s) {
    final title = s.sampleIdentifier?.isNotEmpty == true
        ? s.sampleIdentifier!
        : (s.uuid);

    final dateTxt = s.collectionDate?.isNotEmpty == true
        ? CustomDateUtils.toHumanReadable(s.collectionDate)
        : null;
    final prelevement = SampleListItem.prelevementText(s.sampleNature, dateTxt);
    final labName = s.destinationLabId != null
        ? (labNames[s.destinationLabId!] ?? '#${s.destinationLabId}')
        : null;

    final isChecked = s.id != null && selectedIds.contains(s.id);
    final isDirty = (s.dirty) == 1;

    final lines = <SampleInfoLine>[
      if (s.patientIdentifier?.isNotEmpty == true)
        SampleInfoLine(Icons.person_outline, 'Patient: ${s.patientIdentifier}'),
      if (prelevement != null)
        SampleInfoLine(Icons.water_drop_outlined, prelevement,
            color: SampleListItem.typeColor(s.sampleType)),
      if (labName != null)
        SampleInfoLine(Icons.local_hospital_outlined, 'Labo: $labName'),
      if (s.fromSiteName?.isNotEmpty == true)
        SampleInfoLine(Icons.place_outlined, 'Site: ${s.fromSiteName}'),
      if (s.labNumber?.isNotEmpty == true)
        SampleInfoLine(Icons.tag, 'N° Labo: ${s.labNumber}'),
    ];

    final syncIcon = Tooltip(
      message: isDirty ? 'Non synchronisé' : 'Synchronisé avec le serveur',
      child: Icon(
        isDirty ? Icons.cloud_upload : Icons.cloud_done,
        size: 20,
        color: isDirty ? Colors.orange : Colors.green,
      ),
    );

    return SampleListItem(
      title: title,
      sampleType: s.sampleType,
      lines: lines,
      selected: selectMode ? isChecked : null,
      onSelectedChanged: (_) => _toggleSelection(s),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          syncIcon,
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: () {
        if (selectMode) {
          _toggleSelection(s);
          return;
        }
        if (s.id == null) return;
        Navigator.of(context)
            .pushNamed(SampleDetailScreen.route, arguments: {'id': s.id});
      },
      onLongPress: () => _enterSelectModeWith(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: _buildAppBar(userRole),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),
          body: Column(
            children: [
              // Barre de recherche
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _searchCtl,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher (patient, échantillon)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),

              // Liste
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: loading
                      ? const SampleListSkeleton()
                      : items.isEmpty
                      ? const Center(child: Text('Aucun échantillon trouvé.'))
                      : ListView.separated(
                          controller: _scrollCtl,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          // Si on n'a pas encore vu la dernière page, on
                          // ajoute une ligne "loader" à la fin pour servir
                          // d'ancre visuelle au pré-chargement.
                          itemCount: items.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            if (i >= items.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            return _tileFor(items[i]);
                          },
                        ),
                ),
              ),
            ],
          ),

          // Action flottante qui bascule la sélection même sans long-press
          floatingActionButton: loading || items.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      if (selectMode) {
                        _clearSelection();
                      } else {
                        selectMode = true;
                      }
                    });
                  },
                  icon: Icon(
                    selectMode ? Icons.close : Icons.checklist_outlined,
                  ),
                  label: Text(selectMode ? 'Annuler' : 'Sélectionner'),
                ),
    );
  }
}
