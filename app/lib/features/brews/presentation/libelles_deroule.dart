import '../../../core/presentation/formats.dart';
import '../../recipes/domain/chronologie.dart';
import '../domain/deroule.dart';

/// Libellés du déroulé d'un brassin (ADR-010) : « Nouveau brassin », fiche,
/// liste, « Préparer le brassage ». Dates par `JourneeDeroulee.date`, durées par
/// `dureeChronologie` : aucun calcul ici (P3).

/// Texte d'un déroulé résolu illisible (`process`), sans repli sur la recette.
const kDerouleIllisible =
    'Déroulé illisible. Mettez l\'application à jour, ou prévenez '
    'l\'administrateur.';

/// « Processus : {nom} », ou « Chronologie de la recette seule » sans `process`.
String libelleProcessus(Deroule deroule) {
  final name = deroule.templateName;
  if (!deroule.resolu) return 'Chronologie de la recette seule';
  return name == null || name.trim().isEmpty
      ? 'Processus sans nom'
      : 'Processus : ${name.trim()}';
}

/// Titre d'une journée : « Brassage · sam. 21 nov. », « Houblonnage à cru ·
/// mer. 25 nov. (J+4) », « … (J+3, jour fixé par la recette) », « … (J+5, date
/// changée) » ; sans départ (`brewed_at`, `planned_for`), « Houblonnage à cru ·
/// J+4 ».
String titreJournee(JourneeDeroulee journee, DateTime? depart) {
  final date = journee.date(depart);
  final name = journee.name.trim();
  if (journee.role == RoleJournee.brassage) {
    return date == null ? name : '$name · ${formatJourMois(date)}';
  }
  final source = switch (journee.sourceEcart) {
    SourceEcart.modele => '',
    SourceEcart.recette => ', jour fixé par la recette',
    SourceEcart.brasseur => ', date changée',
  };
  final ecart = 'J+${journee.offsetDays}$source';
  return date == null
      ? '$name · $ecart'
      : '$name · ${formatJourMois(date)} ($ecart)';
}

/// « 4 étapes · 25 min ».
String resumeJourneeDeroulee(JourneeDeroulee journee) =>
    '${formatEtapes(journee.etapes.length)} · '
    '${formatDuree(dureeChronologie(journee.lignes))}';

/// Ligne du « Déroulé prévu » : « Brassage · sam. 21 nov. · 14 étapes · 6 h 10 »,
/// « Houblonnage à cru · mer. 25 nov. (J+4) · 4 étapes ».
String ligneDeroulePrevu(JourneeDeroulee journee, DateTime? depart) {
  final titre = titreJournee(journee, depart);
  return journee.role == RoleJournee.brassage
      ? '$titre · ${resumeJourneeDeroulee(journee)}'
      : '$titre · ${formatEtapes(journee.etapes.length)}';
}

/// « Mesure de densité · 5 min » ; une action de 0 min garde son nom seul.
String ligneEtapeJournee(BrewStepLine ligne) => ligne.durationMin == 0
    ? ligne.name
    : '${ligne.name} · '
          '${formatDuree(Duration(seconds: (ligne.durationMin * 60).round()))}';
