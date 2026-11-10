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
  String toString() => value == null
      ? 'BrewingInputException($field) : $message'
      : 'BrewingInputException($field = $value) : $message';
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

/// Comme [requirePositive], sans la valeur reçue dans l'erreur : un prix, un
/// montant ou une quantité saisis par le brasseur n'entrent pas dans
/// `error_reports/`, que l'admin lit (P13).
void requirePositiveHidden(String field, num value) {
  if (!value.isFinite || value <= 0) {
    throw BrewingInputException(
      field,
      null,
      'doit être un nombre strictement positif',
    );
  }
}

/// Comme [requireNonNegative], sans la valeur reçue dans l'erreur (voir
/// [requirePositiveHidden]).
void requireNonNegativeHidden(String field, num value) {
  if (!value.isFinite || value < 0) {
    throw BrewingInputException(
      field,
      null,
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

/// Élément de [values] dont la valeur stockée ([storedValueOf]) vaut [value].
///
/// Lève [BrewingInputException] pour le champ [field] si aucun ne correspond ;
/// son `value` est alors la longueur de [value], jamais le texte stocké.
T enumFromStored<T>(
  List<T> values,
  String Function(T) storedValueOf,
  String field,
  String value,
) {
  for (final candidate in values) {
    if (storedValueOf(candidate) == value) return candidate;
  }
  // La valeur stockée n'entre pas dans l'erreur : écrite par un autre membre,
  // elle finirait dans error_reports/. Sa longueur suffit au diagnostic.
  throw BrewingInputException(
    field,
    value.length,
    'valeur inconnue de ${value.length} caractères, attendu : '
    '${values.map(storedValueOf).join(', ')}',
  );
}
