import 'package:flutter/material.dart';
import 'package:lstracker/data/services/connectivity_service.dart';

/// Bannière persistante affichée en haut de l'écran quand l'appareil est
/// hors ligne. Mountée globalement via `MaterialApp.builder` au-dessus
/// du Scaffold de chaque route (cf. [OfflineBannerOverlay]).
///
/// L'animation `AnimatedSize` rend l'apparition/disparition fluide. Aucune
/// hauteur réservée quand on est en ligne (taille = 0).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (context, online, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: online ? const SizedBox.shrink() : const _Banner(),
        );
      },
    );
  }
}

/// Wrapper destiné au `MaterialApp.builder` : empile la bannière offline
/// en surimpression du `child` (donc au-dessus de toute la pile de
/// routes), sans modifier le layout du Scaffold sous-jacent.
class OfflineBannerOverlay extends StatelessWidget {
  const OfflineBannerOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: OfflineBanner(),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade700,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: const [
              Icon(Icons.cloud_off, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hors ligne : vos modifications seront envoyées dès le retour du réseau.',
                  style: TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
