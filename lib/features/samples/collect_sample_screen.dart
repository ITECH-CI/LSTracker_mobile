import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lstracker/data/services/auto_sync_manager.dart';
import 'package:lstracker/utils/auth_utils.dart';
import 'package:lstracker/utils/custom_date_utils.dart';
import 'package:lstracker/widgets/form_section.dart';
import 'package:lstracker/widgets/global_bottom_nav.dart';
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../../data/db/sample_dao.dart';
import '../../data/models/sample.dart';

class CollectSampleScreen extends StatefulWidget {
  static const route = '/samples/collect';
  const CollectSampleScreen({super.key});

  @override
  State<CollectSampleScreen> createState() => _CollectSampleScreenState();
}

class _CollectSampleScreenState extends State<CollectSampleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mileageCtl = TextEditingController();
  final _patientCtl = TextEditingController();
  final _sampleIdCtl = TextEditingController();
  final _collectionDateCtl = TextEditingController();
  final _collectionTimeCtl = TextEditingController();
  final _pickupDateCtl = TextEditingController();

  // didChangeDependencies est rappelé à chaque changement d'état de la route
  // (ex. ouverture d'une liste déroulante, qui pousse une route) : sans ce
  // garde-fou, les labos étaient rechargés, le formulaire remplacé par le
  // spinner, et le menu refermé au premier tap.
  bool _bootstrapped = false;

  // Sélections
  int? _circuitId;
  int? _siteId;
  String _circuitName = '';
  String _siteName = '';

  int? _labId;
  String? _sampleType; // CV, EID, HPV, TB, BI, BS, Autre
  String? _sampleNature; // sang total, plasma, etc.

  // Données de référence
  List<Map<String, Object?>> _labs = const [];

  // UI
  bool _saving = false;
  bool _keepSiteAndMileage = true;

  // État de chargement des métadonnées. On distingue explicitement
  // "en cours" / "chargé" pour ne PAS utiliser `_labs.isEmpty` comme
  // signal de loading : si la base ne contient aucun labo (scope vide,
  // métadonnées pas encore synchronisées, etc.), l'utilisateur restait
  // bloqué indéfiniment sur le spinner.
  bool _labsLoading = true;
  String? _labsError;

  final _dao = SampleDao();

  @override
  void initState() {
    super.initState();
    //_loadMetadata();
    _prefillDefaults();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    _circuitId = (args?['circuitId'] as int?);
    _siteId = (args?['siteId'] as int?);
    final mileage = (args?['mileage'] as int?);
    if (mileage != null) _mileageCtl.text = mileage.toString();
    _loadFixedNames();
    _loadLabs();
  }

  Future<void> _loadFixedNames() async {
    if (_circuitId == null || _siteId == null) return;
    final db = await AppDatabase.instance.database;
    final c = await db.query(
      'circuit',
      where: 'id=?',
      whereArgs: [_circuitId],
      limit: 1,
    );
    final s = await db.query(
      'site',
      where: 'id=?',
      whereArgs: [_siteId],
      limit: 1,
    );
    if (!mounted) return;
    setState(() {
      _circuitName = (c.isNotEmpty ? (c.first['name'] ?? '') : '').toString();
      _siteName = (s.isNotEmpty ? (s.first['name'] ?? '') : '').toString();
    });
  }

  Future<void> _loadLabs() async {
    if (mounted) {
      setState(() {
        _labsLoading = true;
        _labsError = null;
      });
    }
    try {
      final db = await AppDatabase.instance.database;
      // Saisie : seuls les labos que l'utilisateur peut choisir.
      final labs = await db.query(
        'lab',
        where: 'selectable = 1',
        orderBy: 'name ASC',
      );
      if (!mounted) return;
      setState(() {
        _labs = labs;
        _labsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _labsError = 'Échec de chargement des laboratoires: $e';
        _labsLoading = false;
      });
    }
  }

  /// Pré-remplit la date/heure de prélèvement (aujourd’hui), et pickupDate à maintenant.
  void _prefillDefaults() {
    final now = DateTime.now();
    final d = DateFormat('yyyy-MM-dd').format(now);
    final t = DateFormat('HH:mm').format(now);
    _collectionDateCtl.text = d;
    _collectionTimeCtl.text = t;
    _pickupDateCtl.text = DateFormat('yyyy-MM-dd HH:mm').format(now);
  }

  @override
  void dispose() {
    _mileageCtl.dispose();
    _patientCtl.dispose();
    _sampleIdCtl.dispose();
    _collectionDateCtl.dispose();
    _collectionTimeCtl.dispose();
    _pickupDateCtl.dispose();
    super.dispose();
  }

  // Utilitaires de choix date/heure.
  // Bornes : [année courante - 1, aujourd'hui] — cohérent avec
  // CustomDateUtils.validateCollectionDate côté validator.
  Future<void> _pickDate(TextEditingController ctl) async {
    final init = DateTime.tryParse(ctl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: CustomDateUtils.minCollectionDate,
      lastDate: CustomDateUtils.maxCollectionDate,
    );
    if (picked != null) {
      ctl.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _pickTime(TextEditingController ctl) async {
    final parts = ctl.text.split(':');
    final init = TimeOfDay(
      hour: int.tryParse(parts.firstOrNull ?? '') ?? TimeOfDay.now().hour,
      minute:
          int.tryParse(parts.elementAtOrNull(1) ?? '') ??
          TimeOfDay.now().minute,
    );
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      ctl.text = picked.format(context);
      // normaliser en HH:mm 24h
      final dt = DateTime(0, 1, 1, picked.hour, picked.minute);
      ctl.text = DateFormat('HH:mm').format(dt);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Chronologie : prélèvement (date + heure) pas dans le futur ; enlèvement
    // ni dans le futur, ni avant le prélèvement.
    final collectedAt = CustomDateUtils.parseStored(
      '${_collectionDateCtl.text.trim()}T${_collectionTimeCtl.text.trim()}',
    );
    final pickedUpAt = CustomDateUtils.parseStored(_pickupDateCtl.text);
    final dateError =
        (collectedAt == null
            ? null
            : CustomDateUtils.checkStepDate(collectedAt)) ??
        (pickedUpAt == null
            ? null
            : CustomDateUtils.checkStepDate(
                pickedUpAt,
                notBefore: collectedAt,
                notBeforeLabel: 'au prélèvement',
              ));
    if (dateError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }

    setState(() => _saving = true);

    try {
      // Construit les timestamps ISO simples
      final collectionDate = _collectionDateCtl.text.trim();
      final collectionTime = _collectionTimeCtl.text.trim();
      String? collectionDateTimeIso;
      if (collectionDate.isNotEmpty && collectionTime.isNotEmpty) {
        // concat en local time (on garde en TEXT dans SQLite comme ton schéma)
        collectionDateTimeIso = '${collectionDate}T$collectionTime';
      }

      final uuid = _makeUuid();

      // Crée l’objet Sample local
      final sample = Sample(
        // id: autoincr par SQLite
        externalId: null,
        uuid: uuid,
        sampleConveyor: await AuthUtils.getUserId(),
        referringSampleId: null,
        startMileage: int.tryParse(_mileageCtl.text.trim()),
        fromSiteCode: null,
        fromSiteName: _siteName,
        fromSiteId: _siteId,
        sampleType: _sampleType,
        sampleNature: _sampleNature,
        destinationLabId: _labId,
        sampleIdentifier: _sampleIdCtl.text.trim().isEmpty
            ? null
            : _sampleIdCtl.text.trim(),
        patientIdentifier: _patientCtl.text.trim().isEmpty
            ? null
            : _patientCtl.text.trim(),
        collectionDate: collectionDateTimeIso, // "yyyy-MM-ddTHH:mm"
        pickupDate: _pickupDateCtl.text.trim().isEmpty
            ? null
            : _pickupDateCtl.text.trim(),
        labNumber: null,
        endMileage: null,
        sampleStatus: SampleStatus.onTransit, // COLLECTED
        deliveredDate: null,
        deliveredLabId: null,
        acceptedDate: null,
        analysisStartedDate: null,
        analysisCompletedDate: null,
        analysisReleasedDate: null,
        resultCollectionDate: null,
        resultDeliveredDate: null,
        resultCollector: null,
        rejectionTypeId: null,
        rejectionComment: null,
        rejectionDate: null,
        resultStartMileage: null,
        resultEndMileage: null,
        createdAt: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
        lastupdatedAt: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
        dirty: 1,
      );

      // Insère en base (local)
      await _dao.insertSample(sample);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échantillon enregistré localement.')),
      );

      // 3) Push en arrière-plan (fire-and-forget)
      AutoSyncManager.instance.pushNow();

      // Après succès : conserver site + kilométrage si souhaité
      if (_keepSiteAndMileage) {
        _patientCtl.clear();
        _sampleIdCtl.clear();
        _prefillDefaults(); // régénère dates
        // ne pas effacer site/mileage
      } else {
        _formKey.currentState!.reset();
        _mileageCtl.clear();
        _patientCtl.clear();
        _sampleIdCtl.clear();
        _collectionDateCtl.clear();
        _collectionTimeCtl.clear();
        _pickupDateCtl.clear();
        setState(() {
          _circuitId = null;
          _siteId = null;
          _labId = null;
          _sampleType = null;
          _sampleNature = null;
        });
        _prefillDefaults();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l’enregistrement : $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _makeUuid() {
    var uuid = Uuid();
    return uuid.v4();
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadLabs,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoLabsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.science_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Aucun laboratoire disponible.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              "Synchronisez les métadonnées (onglet Sync → \"Recharger métadonnées\") puis revenez ici.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadLabs,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<int>> _labItems() => _labs
      .map(
        (e) => DropdownMenuItem<int>(
          value: (e['id'] as int?) ?? (e['id'] as num?)?.toInt(),
          child: Text((e['name'] ?? '').toString()),
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    // Rôle préchargé via AuthUtils.prime() au boot, lookup synchrone.
    final userRole = AuthUtils.roleOrNull() ?? 'ADMIN';
    return Scaffold(
          appBar: AppBar(title: const Text('Collecter un échantillon')),
          bottomNavigationBar: GlobalBottomNav(
            current: BottomTab.collect,
            userRole: userRole,
          ),
          // Sticky save bar : pour un convoyeur qui saisit 20-30 collectes
          // par jour, le bouton "Valider" doit être à portée de pouce sans
          // scroller jusqu'en bas du formulaire.
          persistentFooterButtons: _labs.isEmpty || _labsLoading
              ? null
              : [
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
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Enregistrement...' : 'Valider'),
                    ),
                  ),
                ],
          body: _labsLoading
              ? const Center(child: CircularProgressIndicator())
              : _labsError != null
                  ? _buildErrorState(_labsError!)
                  : _labs.isEmpty
                      ? _buildNoLabsState()
                      : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== Contexte (site + km) — bandeau compact non éditable =====
          _ContextHeader(
            siteName: _siteName.isEmpty ? 'Site #$_siteId' : _siteName,
            circuitName:
                _circuitName.isEmpty ? '#$_circuitId' : _circuitName,
            mileage: _mileageCtl.text,
          ),
          const SizedBox(height: 14),

          // ===== Identification =====
          FormSection(
            title: 'Identification',
            icon: Icons.badge_outlined,
            child: Column(
              children: [
                TextFormField(
                  controller: _patientCtl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Code patient *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Saisissez le code patient'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _sampleIdCtl,
                  decoration: const InputDecoration(
                    labelText: 'Identifiant échantillon (si dispo)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Type & nature =====
          FormSection(
            title: 'Nature du prélèvement',
            icon: Icons.science_outlined,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _sampleType,
                  items: const [
                    DropdownMenuItem(value: 'BI', child: Text('BI')),
                    DropdownMenuItem(value: 'BS', child: Text('BS')),
                    DropdownMenuItem(value: 'CV', child: Text('CV')),
                    DropdownMenuItem(value: 'EID', child: Text('EID')),
                    DropdownMenuItem(value: 'PrEP', child: Text('PrEP')),
                    DropdownMenuItem(value: 'IVSA', child: Text('IVSA')),
                    DropdownMenuItem(value: 'TB', child: Text('TB')),
                    DropdownMenuItem(value: 'HPV', child: Text('HPV')),
                    DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Nature du bilan demandé *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _sampleType = v),
                  validator: (v) =>
                      v == null ? 'Sélectionnez un type' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _sampleNature,
                  items: const [
                    DropdownMenuItem(value: 'DBS', child: Text('DBS')),
                    DropdownMenuItem(
                        value: 'SANG TOTAL', child: Text('SANG TOTAL')),
                    DropdownMenuItem(
                        value: 'PLASMA', child: Text('PLASMA')),
                    DropdownMenuItem(value: 'PSC', child: Text('PSC')),
                    DropdownMenuItem(
                        value: 'CRACHAT', child: Text('CRACHAT')),
                    DropdownMenuItem(value: 'LCR', child: Text('LCR')),
                    DropdownMenuItem(
                        value: 'SELLES', child: Text('SELLES')),
                    DropdownMenuItem(value: 'PV', child: Text('PV')),
                    DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Nature du prélèvement *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _sampleNature = v),
                  validator: (v) =>
                      v == null ? 'Sélectionnez la nature' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Dates =====
          FormSection(
            title: 'Dates',
            icon: Icons.event_outlined,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _collectionDateCtl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Date prélèvement *',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Sélectionner une date',
                            icon: const Icon(
                                Icons.calendar_today_outlined),
                            onPressed: () => _pickDate(_collectionDateCtl),
                          ),
                        ),
                        validator: CustomDateUtils.validateCollectionDate,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _collectionTimeCtl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Heure *',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: "Sélectionner une heure",
                            icon: const Icon(Icons.schedule_outlined),
                            onPressed: () => _pickTime(_collectionTimeCtl),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Choisissez l\'heure'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _pickupDateCtl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Date/Heure de collecte *',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Sélectionner une date',
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: () async {
                        await _pickDate(_pickupDateCtl);
                        final date = _pickupDateCtl.text.split(' ').first;
                        final timeCtl = TextEditingController(
                          text: DateFormat('HH:mm')
                              .format(DateTime.now()),
                        );
                        await _pickTime(timeCtl);
                        _pickupDateCtl.text = '$date ${timeCtl.text}';
                      },
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Choisissez la date/heure'
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Destination =====
          FormSection(
            title: 'Destination',
            icon: Icons.biotech_outlined,
            child: DropdownButtonFormField<int>(
              initialValue: _labId,
              items: _labItems(),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Laboratoire de destination *',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _labId = v),
              validator: (v) =>
                  v == null ? 'Sélectionnez un laboratoire' : null,
            ),
          ),
          const SizedBox(height: 12),

          // ===== Préférence de saisie =====
          FormSection(
            title: 'Préférences',
            icon: Icons.tune_outlined,
            child: CheckboxListTile(
              value: _keepSiteAndMileage,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) =>
                  setState(() => _keepSiteAndMileage = v ?? true),
              title: const Text(
                'Conserver site et kilométrage pour la saisie suivante',
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          // Espace pour ne pas que la dernière section soit collée à la
          // barre persistante de validation.
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// En-tête compact du contexte de collecte (site + circuit + km) : non
/// éditable depuis cet écran, affiché en pleine largeur en haut du
/// formulaire pour rappeler au convoyeur "où" il se trouve.
class _ContextHeader extends StatelessWidget {
  const _ContextHeader({
    required this.siteName,
    required this.circuitName,
    required this.mileage,
  });

  final String siteName;
  final String circuitName;
  final String mileage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.place, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  siteName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Circuit : $circuitName',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '${mileage.isEmpty ? '—' : mileage} km',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _ListSafe<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? elementAtOrNull(int index) =>
      (index < 0 || index >= length) ? null : this[index];
}
