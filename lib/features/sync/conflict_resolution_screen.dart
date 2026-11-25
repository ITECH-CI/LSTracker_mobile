import 'package:flutter/material.dart';
import 'package:lstracker/data/db/sample_dao.dart';
import 'package:lstracker/data/models/sample.dart';
import 'package:lstracker/data/services/log_service.dart';

/// Écran dédié à la résolution des conflits de synchronisation.
///
/// Liste tous les échantillons marqués [has_conflict=1] (= modifiés
/// localement ET reçus du serveur entre temps). Pour chaque conflit,
/// l'utilisateur a deux choix :
///   - **Garder ma version** : on relance le push, la version locale
///     sera renvoyée et écrasera la version serveur.
///   - **Accepter la version serveur** : on supprime la copie locale,
///     le prochain pull la re-téléchargera "propre".
class ConflictResolutionScreen extends StatefulWidget {
  static const route = '/conflicts';
  const ConflictResolutionScreen({super.key});

  @override
  State<ConflictResolutionScreen> createState() => _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen> {
  final SampleDao _dao = SampleDao();
  bool _loading = true;
  List<Sample> _conflicts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final list = await _dao.listConflicts();
    if (!mounted) return;
    setState(() {
      _conflicts = list;
      _loading = false;
    });
  }

  Future<void> _keepLocal(Sample s) async {
    final confirmed = await _confirm(
      title: 'Garder votre version ?',
      message: 'Votre version locale sera renvoyée au serveur lors du prochain envoi '
          'et remplacera la version serveur.',
      confirmLabel: 'Garder ma version',
      confirmColor: Colors.blue,
    );
    if (confirmed != true) return;
    await _dao.resolveConflictKeepLocal(s.uuid);
    LogService.instance.info('Conflict', 'keepLocal pour uuid=${s.uuid}');
    await _load();
    _toast('Version locale conservée. Sera renvoyée à la prochaine synchro.');
  }

  Future<void> _acceptServer(Sample s) async {
    final confirmed = await _confirm(
      title: 'Accepter la version serveur ?',
      message: 'Vos modifications locales sur cet échantillon seront perdues. '
          'La version serveur sera re-téléchargée lors du prochain pull.',
      confirmLabel: 'Accepter le serveur',
      confirmColor: Colors.orange,
    );
    if (confirmed != true) return;
    await _dao.resolveConflictDiscardLocal(s.uuid);
    LogService.instance.warn('Conflict', 'acceptServer pour uuid=${s.uuid} '
        '(données locales écartées)');
    await _load();
    _toast('Version serveur acceptée. Resynchronisez pour la récupérer.');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflits de synchronisation'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conflicts.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _conflicts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildConflictCard(_conflicts[i]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 72, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text(
              'Aucun conflit',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Toutes vos données sont synchronisées sans conflit.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictCard(Sample s) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.sampleIdentifier?.isNotEmpty == true
                            ? s.sampleIdentifier!
                            : '(sans identifiant)',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (s.patientIdentifier?.isNotEmpty == true)
                        Text('Patient : ${s.patientIdentifier}',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (s.sampleType?.isNotEmpty == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s.sampleType!,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Détails clés
            _buildKv('Statut', SampleStatus.label(s.sampleStatus)),
            _buildKv('Site', s.fromSiteName ?? '—'),
            _buildKv('Date collecte', _fmtDate(s.collectionDate)),
            _buildKv('Dernière modif. locale', _fmtDate(s.lastupdatedAt)),

            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Vous avez modifié cet échantillon avant de synchroniser, '
                      'et le serveur en a une version différente.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _acceptServer(s),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('Version serveur'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _keepLocal(s),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Ma version'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
  }
}
