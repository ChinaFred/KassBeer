import 'package:brewing/brewing.dart'
    show
        ActualDayDuration,
        ActualDayKind,
        ActualStepDuration,
        ActualStepKind,
        StepStatus;

import '../../../core/presentation/formats.dart';
import '../../recipes/domain/chronologie.dart';
import '../domain/deroule.dart';

/// Libellés du déroulé d'un brassin (ADR-010) : « Nouveau brassin », fiche,
/// liste, « Préparer le brassage ». Dates par `JourneeDeroulee.date`, durées par
/// `dureeChronologie`, prévu et réel par `actualDurations` : aucun calcul ici
/// (P3).

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

/// Texte affiché et texte lu d'une durée prévue et réelle.
typedef TexteDuree = ({String affiche, String lu});

/// Durée en minutes entières, déjà arrondie par `brewing/` : « 45 min »,
/// « 1 h 30 ». Nombre et unité sont soudés par `formatDuree` ; les autres
/// espaces restent sécables : à 200 %, la ligne se coupe entre les mots.
String _minutes(int minutes) => formatDuree(Duration(minutes: minutes));

/// Écart affiché : « +12 min », « −5 min » (signe moins U+2212), « 0 min »,
/// « +1 h 15 ».
String formatEcartMinutes(int minutes) {
  final signe = minutes > 0
      ? '+'
      : minutes < 0
      ? '−'
      : '';
  return '$signe${_minutes(minutes.abs())}';
}

/// Durée lue : « 12 minutes », « 1 minute », « 1 h 15 ».
String _minutesLues(int minutes) => minutes < 60
    ? '$minutes minute${minutes > 1 ? 's' : ''}'
    : _minutes(minutes);

/// Écart lu : « 12 minutes de plus », « 5 minutes de moins », « sans écart ».
String _ecartLu(int minutes) => minutes == 0
    ? 'sans écart'
    : '${_minutesLues(minutes.abs())} de ${minutes > 0 ? 'plus' : 'moins'}';

/// Durée d'une étape sur la fiche, après son état : « prévu 45 min · réel
/// 57 min · +12 min », « prévu 45 min · réel — » (sautée, non faite),
/// « prévu 45 min » (à venir), « prévu 45 min · réel en cours », « prévu
/// 45 min · réel sans heure de fin ». `null` pour une action de 0 min : sa
/// ligne ne change pas. [status] : état de la ligne. Valeurs de `brewing/` (P3).
TexteDuree? dureeEtapeReelle(ActualStepDuration duree, StepStatus status) {
  final prevu = 'prévu ${_minutes(duree.plannedMinutes)}';
  final reel = duree.actualMinutes;
  final ecart = duree.deltaMinutes;
  return switch (duree.kind) {
    ActualStepKind.action => null,
    ActualStepKind.measured when reel != null && ecart != null => (
      affiche: '$prevu · réel ${_minutes(reel)} · ${formatEcartMinutes(ecart)}',
      lu: '$prevu, réel ${_minutes(reel)}, ${_ecartLu(ecart)}',
    ),
    ActualStepKind.running => (
      affiche: '$prevu · réel en cours',
      lu: '$prevu, réel en cours',
    ),
    ActualStepKind.missingEnd => (
      affiche: '$prevu · réel sans heure de fin',
      lu: '$prevu, réel sans heure de fin',
    ),
    ActualStepKind.none when status == StepStatus.pending => (
      affiche: prevu,
      lu: prevu,
    ),
    ActualStepKind.measured || ActualStepKind.none => (
      affiche: '$prevu · réel —',
      lu: '$prevu, pas de durée réelle',
    ),
  };
}

/// Ligne de durée d'une journée sur la fiche : « Durée totale : prévu 6 h 10 ·
/// réel 6 h 52, dont 32 min entre les étapes · +42 min ». `null` tant
/// qu'aucune étape n'a début et fin. Valeurs de `brewing/` (P3).
TexteDuree? dureeJourneeReelle(ActualDayDuration duree) {
  final prevu = _minutes(duree.plannedMinutes);
  const titre = 'Durée totale$nbsp:';
  final reel = duree.actualMinutes;
  final ecart = duree.deltaMinutes;
  final entre = duree.betweenStepsMinutes;
  switch (duree.kind) {
    case ActualDayKind.none:
      return null;
    case ActualDayKind.running:
      return (
        affiche: '$titre prévu $prevu · réel en cours',
        lu: '$titre prévue $prevu, réelle en cours.',
      );
    case ActualDayKind.missingEnd:
      final sansFin =
          '${formatEtapes(duree.stepsWithoutEnd).replaceFirst(' ', nbsp)} '
          'sans heure de fin';
      return (
        affiche: '$titre prévu $prevu · réel inconnu$nbsp: $sansFin',
        lu: '$titre prévue $prevu, réelle inconnue : $sansFin.',
      );
    case ActualDayKind.measured:
      if (reel == null || ecart == null) return null;
      final avecEntre = entre != null && entre >= 1;
      final dont = avecEntre
          ? ', dont ${_minutes(entre)} entre les étapes'
          : '';
      final dontLu = avecEntre
          ? ' dont ${_minutesLues(entre)} entre les étapes'
          : '';
      return (
        affiche:
            '$titre prévu $prevu · réel ${_minutes(reel)}$dont · '
            '${formatEcartMinutes(ecart)}',
        lu:
            '$titre prévue $prevu, réelle ${_minutes(reel)}$dontLu, '
            '${ecart == 0 ? 'sans écart' : '${_ecartLu(ecart)} que prévu'}.',
      );
  }
}

/// « Mesure de densité · 5 min » ; une action de 0 min garde son nom seul.
String ligneEtapeJournee(BrewStepLine ligne) => ligne.durationMin == 0
    ? ligne.name
    : '${ligne.name} · '
          '${formatDuree(Duration(seconds: (ligne.durationMin * 60).round()))}';
