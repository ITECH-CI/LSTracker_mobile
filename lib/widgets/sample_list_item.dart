import 'package:flutter/material.dart';

/// Une ligne d'info (icône + texte) pour le corps d'un [SampleListItem].
class SampleInfoLine {
  final IconData icon;
  final String text;
  final Color? color;
  const SampleInfoLine(this.icon, this.text, {this.color});
}

/// List item harmonisé pour afficher un échantillon dans les listes.
///
/// Présentation : un badge "type" coloré à gauche, un titre (identifiant) en
/// gras, puis des lignes d'info (icône + texte) fournies par l'appelant, et un
/// widget trailing optionnel (icône sync, chevron, checkbox...).
///
/// Centralise le look & feel pour rester cohérent entre tous les écrans de
/// liste (samples, results ready, results collected, etc.).
class SampleListItem extends StatelessWidget {
  /// Type d'échantillon (BI/BS/CV/EID/TB/HPV/PrEP/IVSA...) affiché dans le badge.
  final String? sampleType;

  /// Titre principal (identifiant de l'échantillon ou uuid).
  final String title;

  /// Lignes d'info du corps (patient, prélèvement, labo, site...).
  final List<SampleInfoLine> lines;

  /// Widget affiché à droite (sync + chevron, ou rien). Ignoré si [selected]
  /// non-null (mode sélection → une checkbox est affichée).
  final Widget? trailing;

  /// Mode sélection : si non-null, une checkbox est affichée à droite et la
  /// bordure de la carte prend la couleur du type quand cochée.
  final bool? selected;
  final ValueChanged<bool?>? onSelectedChanged;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SampleListItem({
    super.key,
    required this.title,
    this.sampleType,
    this.lines = const [],
    this.trailing,
    this.selected,
    this.onSelectedChanged,
    this.onTap,
    this.onLongPress,
  });

  // Couleur propre à chaque type, identique au tableau de bord web
  // (TYPE_COLORS dans templates/home/index.html). Palette catégorielle validée
  // (outil dataviz validate_palette), attribuée par fréquence. Clés en
  // MAJUSCULES : typeColor() compare en majuscules (« PrEP » → « PREP »).
  // Type inconnu → gris ardoise.
  static const Map<String, Color> _typeColors = {
    'CV': Color(0xFF2A78D6),
    'EID': Color(0xFFEB6834),
    'TB': Color(0xFF1BAF7A),
    'BI': Color(0xFFEDA100),
    'BS': Color(0xFFE87BA4),
    'HPV': Color(0xFF008300),
    'PREP': Color(0xFF4A3AA7),
    'IVSA': Color(0xFFE34948),
  };

  static Color typeColor(String? type) {
    if (type == null) return const Color(0xFF64748B);
    return _typeColors[type.trim().toUpperCase()] ?? const Color(0xFF64748B);
  }

  /// Construit la ligne "Prélèvement: {nature} le {date}" (parties optionnelles).
  /// Retourne null si ni nature ni date.
  static String? prelevementText(String? nature, String? humanReadableDate) {
    final n = nature?.trim();
    final d = humanReadableDate?.trim();
    if (n?.isNotEmpty == true && d?.isNotEmpty == true) {
      return 'Prélèvement: $n le $d';
    }
    if (n?.isNotEmpty == true) return 'Prélèvement: $n';
    if (d?.isNotEmpty == true) return 'Prélèvement le $d';
    return null;
  }

  Widget _badge() {
    final type = (sampleType?.trim().isNotEmpty == true)
        ? sampleType!.trim()
        : '—';
    final color = typeColor(sampleType);
    // Le texte ne prend pas la couleur brute (illisible pour les teintes
    // claires comme le jaune de BI) : on l'assombrit pour le contraste.
    final ink = Color.lerp(color, Colors.black, 0.45)!;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        type,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
          fontSize: type.length > 3 ? 10 : 12,
        ),
      ),
    );
  }

  Widget _infoLine(SampleInfoLine l) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(l.icon, size: 14, color: l.color ?? Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelectMode = selected != null;
    final isChecked = selected ?? false;
    final color = typeColor(sampleType);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
        const SizedBox(height: 2),
        ...lines.map(_infoLine),
      ],
    );

    final Widget right = isSelectMode
        ? Checkbox(value: isChecked, onChanged: onSelectedChanged)
        : (trailing ?? const SizedBox.shrink());

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isChecked ? color : Colors.transparent,
          width: isChecked ? 1.4 : 0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(),
              const SizedBox(width: 12),
              Expanded(child: body),
              const SizedBox(width: 4),
              right,
            ],
          ),
        ),
      ),
    );
  }
}
