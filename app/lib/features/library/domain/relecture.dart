import '../../../core/data/lecture_document.dart';

/// Relecture d'un texte rédigé par l'API Claude (`beer_hop_aromas/`, ADR-013 ;
/// `beer_misc_descriptions/`, ADR-018) : `reviewed`, et `reviewed_at` quand il
/// est vrai.
typedef Relecture = ({bool relu, DateTime? reluLe});

/// Lit `reviewed` (booléen obligatoire) et, s'il est vrai, `reviewed_at` en
/// `AAAA-MM-JJ`, date du calendrier. Sinon [DocumentIllisible], sans valeur du
/// document dans la raison. Non relu : `reviewed_at` est ignoré.
Relecture lireRelecture(LecteurChamps read) {
  final relu = read.boolFacultatif('reviewed');
  if (relu == null) {
    throw const DocumentIllisible('reviewed', 'booléen obligatoire absent');
  }
  return (relu: relu, reluLe: relu ? _dateRelecture(read) : null);
}

DateTime _dateRelecture(LecteurChamps read) {
  final value = read.texteFacultatif('reviewed_at');
  final match = value == null
      ? null
      : RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match != null) {
    final annee = int.parse(match.group(1)!);
    final mois = int.parse(match.group(2)!);
    final jour = int.parse(match.group(3)!);
    final date = DateTime(annee, mois, jour);
    if (date.year == annee && date.month == mois && date.day == jour) {
      return date;
    }
  }
  throw const DocumentIllisible(
    'reviewed_at',
    'date AAAA-MM-JJ attendue quand reviewed est vrai',
  );
}
