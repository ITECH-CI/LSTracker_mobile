import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lstracker/data/db/sample_dao.dart';
import 'package:lstracker/data/services/log_service.dart';
import 'package:lstracker/features/sync/sync_screen.dart';

/// Action AppBar : icône cloud avec **badge X actions en attente**.
///
/// Tap → navigation vers l'écran Sync. Le compteur (dirty + conflits)
/// se rafraîchit comme dans le bottom-nav :
///  - au mount
///  - sur logs 'Sync' / 'AutoSync'
///  - toutes les 30 s
///
/// À placer dans `AppBar(actions: [SyncQueueAction()])` pour rendre la
/// file d'attente visible depuis n'importe quel écran (dashboard,
/// listes, etc.) sans dépendre du bottom-nav.
class SyncQueueAction extends StatefulWidget {
  const SyncQueueAction({super.key});

  @override
  State<SyncQueueAction> createState() => _SyncQueueActionState();
}

class _SyncQueueActionState extends State<SyncQueueAction> {
  final SampleDao _dao = SampleDao();
  int _pending = 0;
  Timer? _timer;
  StreamSubscription<LogEntry>? _logSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _logSub = LogService.instance.stream.listen((e) {
      if (e.tag == 'Sync' || e.tag == 'AutoSync') _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final dirty = await _dao.countDirty();
      final conflicts = await _dao.countConflicts();
      final total = dirty + conflicts;
      if (mounted && total != _pending) {
        setState(() => _pending = total);
      }
    } catch (_) {
      // silencieux : un compteur UI ne doit pas planter l'app.
    }
  }

  void _openSync() {
    Navigator.of(context).pushNamed(SyncScreen.route).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = _pending > 0;
    final tooltip = hasPending
        ? '$_pending action(s) en attente : ouvrir la synchronisation'
        : 'Tout est synchronisé';
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: _openSync,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(hasPending ? Icons.cloud_sync : Icons.cloud_done_outlined),
            if (hasPending)
              Positioned(
                right: -8,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    _pending > 99 ? '99+' : '$_pending',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
