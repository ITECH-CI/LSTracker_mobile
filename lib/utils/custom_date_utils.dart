import 'package:intl/intl.dart';

class CustomDateUtils {
  /// Converts a date string to a human-readable format.
  static String? toHumanReadable(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return null;
    }

    // On s'assure que la chaîne a au moins 16 caractères avant de la découper.
    final String parsedString = dateString.length >= 16
        ? dateString.substring(0, 16)
        : dateString;

    try {
      final DateTime dateTime = DateTime.parse(parsedString);

      final DateFormat formatter = DateFormat('dd/MM/yyyy à HH:mm');
      return formatter.format(dateTime);
    } catch (e) {
      try {
        final String isoFormatted = parsedString.replaceFirst(' ', 'T');
        final DateTime dateTime = DateTime.parse(isoFormatted);

        final DateFormat formatter = DateFormat('dd/MM/yyyy à HH:mm');
        return formatter.format(dateTime);
      } catch (e2) {
        return null;
      }
    }
  }

  /// Borne basse acceptée pour une date de collecte (année en cours - 1).
  /// Toute date antérieure est considérée comme une erreur de saisie.
  static DateTime get minCollectionDate {
    final now = DateTime.now();
    return DateTime(now.year - 1, 1, 1);
  }

  /// Borne haute : aujourd'hui (pas de collecte dans le futur).
  /// Inclusif jusqu'à fin de journée (23:59:59).
  static DateTime get maxCollectionDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  /// Valide une date saisie comme "yyyy-MM-dd" ou ISO ("yyyy-MM-ddTHH:mm").
  /// Retourne null si valide, un message d'erreur sinon.
  /// Règles : non vide, parsable, dans [minCollectionDate, maxCollectionDate].
  static String? validateCollectionDate(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Date requise' : null;
    }
    final raw = value.trim();
    // Accepte "yyyy-MM-dd" ou "yyyy-MM-dd HH:mm" ou "yyyy-MM-ddTHH:mm"
    final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse(iso) ?? DateTime.tryParse(iso.substring(0, iso.length > 10 ? 10 : iso.length));
    if (dt == null) {
      return 'Date invalide (attendu yyyy-MM-dd)';
    }
    final minD = minCollectionDate;
    if (dt.isBefore(minD)) {
      return 'Date trop ancienne (depuis ${minD.year} uniquement)';
    }
    if (dt.isAfter(maxCollectionDate)) {
      return 'Date dans le futur non autorisée';
    }
    return null;
  }

  /// Variante combinée date + heure (ex. "yyyy-MM-dd HH:mm").
  /// Mêmes bornes que validateCollectionDate.
  static String? validateCollectionDateTime(String? value, {bool required = true}) {
    return validateCollectionDate(value, required: required);
  }

  /// Tolérance sur l'horloge du téléphone avant de considérer une date
  /// comme « dans le futur ».
  static const futureTolerance = Duration(minutes: 5);

  /// Contrôle d'une date d'étape (dépôt, acceptation, résultat…).
  /// Retourne null si valide, un message d'erreur sinon.
  /// [notBefore] : date de l'étape précédente la plus récente, décrite par
  /// [notBeforeLabel] avec sa préposition (ex. « à la collecte »).
  static String? checkStepDate(
    DateTime dt, {
    DateTime? notBefore,
    String? notBeforeLabel,
  }) {
    if (dt.isAfter(DateTime.now().add(futureTolerance))) {
      return 'Date dans le futur non autorisée.';
    }
    if (notBefore != null && dt.isBefore(notBefore)) {
      final when = DateFormat('dd/MM/yyyy à HH:mm').format(notBefore);
      return 'Date antérieure ${notBeforeLabel ?? "à l'étape précédente"} ($when).';
    }
    return null;
  }

  /// Parse une date stockée ("yyyy-MM-dd", "yyyy-MM-dd HH:mm" ou ISO).
  static DateTime? parseStored(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));
  }
}
