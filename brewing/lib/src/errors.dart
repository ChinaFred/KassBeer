/// Erreur levée par le paquet sur une entrée invalide.
///
/// Le paquet ne fait aucun `catch` : il lève, et l'appelant journalise par
/// `ErrorReportService.reportError` avant d'afficher la panne (CLAUDE.md).
class BrewingInputException implements Exception {
  /// Crée l'erreur pour le champ [field], qui a reçu [value].
  const BrewingInputException(this.field, this.value, this.message);

  /// Nom du champ ou du paramètre fautif (`volumeLitres`, `hops[2].alphaPercent`…).
  final String field;

  /// Valeur reçue.
  final Object? value;

  /// Raison du refus, en français.
  final String message;

  @override
  String toString() => 'BrewingInputException($field = $value) : $message';
}

/// Vérifie qu'un nombre est fini et strictement positif.
void requirePositive(String field, num value) {
  if (!value.isFinite || value <= 0) {
    throw BrewingInputException(
      field,
      value,
      'doit être un nombre strictement positif',
    );
  }
}

/// Vérifie qu'un nombre est fini et positif ou nul.
void requireNonNegative(String field, num value) {
  if (!value.isFinite || value < 0) {
    throw BrewingInputException(
      field,
      value,
      'doit être un nombre positif ou nul',
    );
  }
}

/// Vérifie qu'un nombre est fini et compris entre [min] et [max] inclus.
void requireRange(String field, num value, num min, num max) {
  if (!value.isFinite || value < min || value > max) {
    throw BrewingInputException(
      field,
      value,
      'doit être compris entre $min et $max',
    );
  }
}
