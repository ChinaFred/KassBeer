import 'dart:async';

import 'package:brewing/brewing.dart'
    show
        BrewComparison,
        BrewMeasurements,
        BrewingInputException,
        CalculationComputed,
        CalculationResult,
        ComparisonLine,
        FermentableKind,
        GravityRead,
        MeasuredComputed,
        MeasuredImpossible,
        MeasuredImpossibleKind,
        MeasuredResult,
        MeasuredUnavailable,
        MeasurementGap,
        MeasurementGapKind,
        PlannedBrewValues,
        compareBrewWithPlan,
        fermentationDayNumber,
        readGravity;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/services/error_report_service.dart';
import '../../brew_day/presentation/mesure_form.dart';
import '../../recipes/presentation/recipe_calculations_view.dart';
import '../../recipes/presentation/recipes_providers.dart';
import '../data/brews_repository.dart';
import '../domain/brew.dart';
import '../domain/brew_event.dart';
import '../domain/mesures_retenues.dart';
import 'brews_providers.dart';
import 'releve_fermentation.dart';

/// Texte de l'annonce d'un choix écrit hors ligne.
const _kChoixHorsLigne =
    'Choix enregistré sur l\'appareil. Il partira au retour du réseau.';

/// Résultat de la comparaison, pour l'écran.
sealed class ComparaisonEvaluee {
  const ComparaisonEvaluee();
}

class ComparaisonObtenue extends ComparaisonEvaluee {
  const ComparaisonObtenue(this.comparison);

  final BrewComparison comparison;
}

/// `brewing/` a refusé une valeur enregistrée : rapportée, l'écran affiche la panne.
class ComparaisonImpossible extends ComparaisonEvaluee {
  const ComparaisonImpossible(this.field);

  final String field;
}

double? _valeur(CalculationResult result) =>
    result is CalculationComputed ? result.value : null;

/// Valeurs prévues du brassin : copie figée, jamais une mesure (RR8).
PlannedBrewValues prevuDe(Brew brew, CalculsRecette calculs) {
  final calcul = calculs is CalculsObtenus ? calculs.calculation : null;
  return PlannedBrewValues(
    originalGravity: calcul == null ? null : _valeur(calcul.originalGravity),
    finalGravity: calcul == null ? null : _valeur(calcul.finalGravity),
    alcoholByVolume: calcul == null ? null : _valeur(calcul.alcoholByVolume),
    fermenterVolumeLitres: brew.recipe.batchVolumeL,
    mashEfficiencyPercent: brew.equipment.mashEfficiencyPct,
  );
}

/// Calcule la comparaison. Une valeur enregistrée hors limites est rapportée une fois
/// par brassin et rend [ComparaisonImpossible] : jamais de valeur de repli.
ComparaisonEvaluee evaluerComparaison({
  required Brew brew,
  required CalculsRecette calculs,
  required MesuresRetenues retenues,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  try {
    return ComparaisonObtenue(
      compareBrewWithPlan(
        planned: prevuDe(brew, calculs),
        measured: BrewMeasurements(
          originalGravity: retenues.densiteInitiale?.value,
          finalGravity: retenues.densiteFinale?.value,
          fermenterVolumeLitres: retenues.volumeFermenteur?.value,
          sugarsInWort: brew.sugarsInWort,
        ),
        fermentables: [for (final f in brew.recipe.fermentables) f.toInput()],
      ),
    );
  } on BrewingInputException catch (error, stackTrace) {
    if (reported.add('comparison|${brew.id}|${error.field}')) {
      errors.reportError(
        feature: 'brews.comparison',
        error: error,
        stackTrace: stackTrace,
        context: 'brews/${brew.id} : valeur refusée ${error.field}',
      );
    }
    return ComparaisonImpossible(error.field);
  }
}

/// Bloc « Prévu et mesuré » (RR7).
class BlocPrevuEtMesure extends ConsumerWidget {
  const BlocPrevuEtMesure({
    super.key,
    required this.brew,
    required this.eventsAsync,
    required this.mine,
    required this.offline,
    required this.calculs,
    required this.tokenName,
    required this.uneAction,
  });

  final Brew brew;
  final AsyncValue<ListeLue<BrewEvent>> eventsAsync;
  final bool mine;
  final bool offline;
  final CalculsRecette calculs;

  /// Nom du jeton, lu au premier affichage du propriétaire ; nul pour un autre membre,
  /// qui n'a aucune action.
  final Future<String?>? tokenName;

  /// Lance une action, ignorée si une autre est en cours.
  final Future<void> Function(Future<void> Function() action) uneAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = eventsAsync.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Prévu et mesuré'),
        if (liste == null && eventsAsync.hasError)
          Row(
            children: [
              const Expanded(
                child: TexteAbsent('Impossible de lire les mesures.'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(brewEventsProvider(brew.id)),
                child: const Text('Réessayer'),
              ),
            ],
          )
        else if (liste == null)
          const TexteAbsent('Chargement des mesures')
        else if (liste.documents.isEmpty && liste.fromCache && offline)
          const TexteAbsent(
            'Mesures indisponibles sur cet appareil hors ligne.',
          )
        else
          _Tableau(
            brew: brew,
            events: liste.valides,
            mine: mine,
            offline: offline,
            calculs: calculs,
            tokenName: tokenName,
            uneAction: uneAction,
          ),
      ],
    );
  }
}

class _Tableau extends ConsumerWidget {
  const _Tableau({
    required this.brew,
    required this.events,
    required this.mine,
    required this.offline,
    required this.calculs,
    required this.tokenName,
    required this.uneAction,
  });

  final Brew brew;
  final List<BrewEvent> events;
  final bool mine;
  final bool offline;
  final CalculsRecette calculs;
  final Future<String?>? tokenName;
  final Future<void> Function(Future<void> Function() action) uneAction;

  String _etape(BrewEvent e) {
    if (e.isFermentation) {
      final brewed = brew.brewedAt;
      return brewed == null
          ? 'Relevé'
          : 'Relevé J+${fermentationDayNumber(brewedAt: brewed, at: e.measuredAt)}';
    }
    final key = e.stepKey;
    if (key != null) {
      for (final s in brew.deroule.lignes) {
        if (s.key == key) return s.name;
      }
    }
    return 'Sans étape';
  }

  String _origine(MesureRetenue retenue, {required bool masquerDerniere}) => [
    _etape(retenue.event),
    formatJourCourtHeure(retenue.event.measuredAt),
    if (retenue.choisie) 'Choisie' else if (!masquerDerniere) 'Dernière mesure',
  ].join(' · ');

  /// « Changer » : présent pour le propriétaire dès qu'une mesure peut être retenue.
  VoidCallback? _actionChanger(
    BuildContext context,
    WidgetRef ref,
    MesureRetenueChamp champ,
    MesureRetenue? retenue,
  ) {
    final candidats = candidatsRetenus(champ, events);
    if (!mine || candidats.isEmpty) return null;
    return () => unawaited(
      uneAction(() => _changer(context, ref, champ, retenue, candidats)),
    );
  }

  Future<void> _changer(
    BuildContext context,
    WidgetRef ref,
    MesureRetenueChamp champ,
    MesureRetenue? retenue,
    List<BrewEvent> candidats,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(brewsRepositoryProvider);
    final courant = retenue != null && retenue.choisie
        ? retenue.event.id
        : null;
    final titre = _titreChoix(champ);
    final choix = await showFeuilleOuDialogue<_Choix>(
      context: context,
      builder: (context) => _FeuilleChoix(
        titre: titre,
        aUneRetenue: retenue != null,
        courant: courant,
        candidats: candidats,
        libelle: (e) => (
          valeur: libelleMesure(e.measureType!, e.value!),
          origine: '${_etape(e)} · ${formatJourCourtHeure(e.measuredAt)}',
        ),
      ),
    );
    if (choix == null) return;
    final ownerName = await tokenName!;
    final written = repo.setMesureRetenue(
      brewId: brew.id,
      champ: champ,
      eventId: choix.eventId,
      ownerName: ownerName,
    );
    final event = choix.event;
    final annonce = event == null
        ? '${_titreChamp(champ)} : dernière mesure. ${_recalcule(champ)}'
        : '${_titreChamp(champ)} : '
              '${libelleMesure(event.measureType!, event.value!)}. '
              '${_recalcule(champ)}';
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: offline ? _kChoixHorsLigne : annonce,
      refus: 'L\'enregistrement de « ${brew.name} » a échoué.',
    );
  }

  Future<void> _saisir(
    BuildContext context,
    WidgetRef ref,
    MeasureType type,
    String titre,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(brewsRepositoryProvider);
    await showFeuilleOuDialogue<void>(
      context: context,
      fermetureProtegee: true,
      builder: (_) => _FormulaireMesureSeule(
        titre: titre,
        type: type,
        brewedAt: brew.brewedAt,
        now: ref.read(horlogeProvider),
        onSubmit: (value, at) {
          final created = repo.addEvent(
            brewId: brew.id,
            input: BrewEventInput(
              ownerUid: brew.ownerUid,
              kind: BrewEventKind.measurement,
              measureType: type,
              value: value,
              measuredAt: at,
            ),
          );
          unawaited(
            created.written.catchError((Object _) {
              annoncerRefus(
                messenger,
                '${type.label} ${libelleMesure(type, value)} du '
                '${formatJourCourtHeure(at)}',
              );
            }),
          );
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                offline
                    ? 'Mesure enregistrée sur l\'appareil. Elle partira au retour du réseau.'
                    : 'Mesure enregistrée.',
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sucres(BuildContext context, WidgetRef ref, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(brewsRepositoryProvider);
    final ownerName = await tokenName!;
    final written = repo.setSugarsInWort(
      brewId: brew.id,
      value: value,
      ownerName: ownerName,
    );
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: offline ? _kChoixHorsLigne : 'Réponse enregistrée.',
      refus: 'L\'enregistrement de « ${brew.name} » a échoué.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retenues = MesuresRetenues.de(brew, events);
    final evaluee = evaluerComparaison(
      brew: brew,
      calculs: calculs,
      retenues: retenues,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(calculationReportsProvider),
    );
    final theme = Theme.of(context);
    if (evaluee is ComparaisonImpossible) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(messageCalculImpossible(evaluee.field))),
        ],
      );
    }
    final c = (evaluee as ComparaisonObtenue).comparison;
    final provisoire =
        brew.status == BrewStatus.fermenting && brew.fgEventId == null;
    final finaleAuto = provisoire;
    // Tout ce qui n'est pas un malt, nature à préciser comprise, comme
    // compareBrewWithPlan (brewing/).
    final nonMaltes = {
      for (final f in brew.recipe.fermentables)
        if (f.kind != FermentableKind.malt) f.name.trim(),
    }.toList();
    final ligneSucres = nonMaltes.isEmpty
        ? null
        : mine
        ? _QuestionSucres(
            question: questionSucres(nonMaltes),
            valeur: brew.sugarsInWort,
            onChanged: (v) =>
                unawaited(uneAction(() => _sucres(context, ref, v))),
          )
        : null;

    final lignes = <_DonneesLigne>[
      _DonneesLigne(
        mine: mine,
        label: 'Densité initiale',
        ligne: c.originalGravity,
        format: formatDensite,
        ecart: formatEcart,
        retenue: retenues.densiteInitiale,
        origine: retenues.densiteInitiale == null
            ? null
            : _origine(retenues.densiteInitiale!, masquerDerniere: false),
        onChanger: _actionChanger(
          context,
          ref,
          MesureRetenueChamp.densiteInitiale,
          retenues.densiteInitiale,
        ),
        changerSemantique: 'Changer la densité initiale',
        raisons: _raisonsDensite(c.originalGravity.measured, mine, () {
          unawaited(
            _saisir(
              context,
              ref,
              MeasureType.gravity,
              'Saisir la densité initiale',
            ),
          );
        }, initiale: true),
      ),
      _DonneesLigne(
        mine: mine,
        label: provisoire
            ? 'Densité finale (dernière mesure)'
            : 'Densité finale',
        ligne: c.finalGravity,
        format: formatDensite,
        ecart: formatEcart,
        retenue: retenues.densiteFinale,
        origine: retenues.densiteFinale == null
            ? null
            : _origine(retenues.densiteFinale!, masquerDerniere: finaleAuto),
        onChanger: _actionChanger(
          context,
          ref,
          MesureRetenueChamp.densiteFinale,
          retenues.densiteFinale,
        ),
        changerSemantique: 'Changer la densité finale',
        raisons: _raisonsDensite(
          c.finalGravity.measured,
          mine,
          null,
          initiale: false,
        ),
      ),
      _DonneesLigne(
        mine: mine,
        label: 'Degré',
        ligne: c.alcoholByVolume,
        format: formatDegre,
        ecart: (v) => formatEcart(v, unite: '%${nbsp}vol'),
        suffixeValeur: provisoire ? 'provisoire' : null,
        avertissements: [
          if (nonMaltes.isNotEmpty && brew.sugarsInWort == false)
            'Les sucres ajoutés après cette densité initiale ne comptent pas '
                'dans ce degré.',
        ],
        raisons: _raisonsDegre(c.alcoholByVolume.measured),
      ),
      _DonneesLigne(
        mine: mine,
        label: 'Volume en fermenteur',
        ligne: c.fermenterVolume,
        format: formatLitres,
        ecart: (v) => formatEcart(v, unite: 'L'),
        retenue: retenues.volumeFermenteur,
        origine: retenues.volumeFermenteur == null
            ? null
            : _origine(retenues.volumeFermenteur!, masquerDerniere: false),
        onChanger: _actionChanger(
          context,
          ref,
          MesureRetenueChamp.volumeFermenteur,
          retenues.volumeFermenteur,
        ),
        changerSemantique: 'Changer le volume en fermenteur',
        raisons: _raisonsVolume(c.fermenterVolume.measured, mine, () {
          unawaited(
            _saisir(
              context,
              ref,
              MeasureType.volume,
              'Saisir le volume en fermenteur',
            ),
          );
        }),
      ),
      _DonneesLigne(
        mine: mine,
        label: 'Rendement',
        ligne: c.mashEfficiency,
        format: formatPourcent,
        ecart: formatEcart,
        raisons: _raisonsRendement(
          c.mashEfficiency.measured,
          mine,
          () {
            unawaited(
              _saisir(
                context,
                ref,
                MeasureType.volume,
                'Saisir le volume en fermenteur',
              ),
            );
          },
          () {
            unawaited(
              _saisir(
                context,
                ref,
                MeasureType.gravity,
                'Saisir la densité initiale',
              ),
            );
          },
        ),
        avertissements: [
          if (c.mashEfficiency.measured case MeasuredComputed(
            :final value,
          ) when value > 100)
            mine
                ? 'Rendement au-delà de 100 % : vérifiez le volume et la densité.'
                : 'Rendement au-delà de 100 %.',
        ],
        bas: ligneSucres,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final minColonne = kComparaisonValeurMinWidth * scale;
        final disposition =
            constraints.maxWidth >= kCompactMaxWidth &&
                constraints.maxWidth * 2 / 9 >= minColonne
            ? _Disposition.lignes
            : constraints.maxWidth >= minColonne * 3
            ? _Disposition.colonnes
            : _Disposition.empilee;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (disposition == _Disposition.lignes) const _EnTeteTableau(),
            for (final l in lignes)
              _LigneComparaison(donnees: l, disposition: disposition),
          ],
        );
      },
    );
  }

  String _titreChamp(MesureRetenueChamp champ) => switch (champ) {
    MesureRetenueChamp.densiteInitiale => 'Densité initiale',
    MesureRetenueChamp.densiteFinale => 'Densité finale',
    MesureRetenueChamp.volumeFermenteur => 'Volume',
  };

  String _titreChoix(MesureRetenueChamp champ) => switch (champ) {
    MesureRetenueChamp.densiteInitiale => 'Densité initiale retenue',
    MesureRetenueChamp.densiteFinale => 'Densité finale retenue',
    MesureRetenueChamp.volumeFermenteur => 'Volume retenu',
  };

  String _recalcule(MesureRetenueChamp champ) => switch (champ) {
    MesureRetenueChamp.volumeFermenteur => 'Rendement recalculé.',
    MesureRetenueChamp.densiteFinale => 'Degré recalculé.',
    MesureRetenueChamp.densiteInitiale => 'Degré et rendement recalculés.',
  };
}

enum _Disposition { lignes, colonnes, empilee }

class _DonneesLigne {
  const _DonneesLigne({
    required this.mine,
    required this.label,
    required this.ligne,
    required this.format,
    required this.ecart,
    this.retenue,
    this.origine,
    this.onChanger,
    this.changerSemantique,
    this.suffixeValeur,
    this.avertissements = const [],
    this.raisons = const _Raisons(),
    this.bas,
  });

  /// Vrai pour le propriétaire : un lecteur ne reçoit aucune consigne.
  final bool mine;
  final String label;
  final ComparisonLine ligne;
  final String Function(double) format;
  final String Function(double) ecart;
  final MesureRetenue? retenue;
  final String? origine;
  final VoidCallback? onChanger;
  final String? changerSemantique;
  final String? suffixeValeur;
  final List<String> avertissements;
  final _Raisons raisons;
  final Widget? bas;
}

/// Raisons d'une valeur indisponible et action possible.
class _Raisons {
  const _Raisons({this.lignes = const [], this.actions = const []});

  final List<String> lignes;
  final List<({String label, VoidCallback onTap})> actions;
}

_Raisons _raisonsDensite(
  MeasuredResult result,
  bool mine,
  VoidCallback? saisir, {
  required bool initiale,
}) {
  if (result is! MeasuredUnavailable) return const _Raisons();
  return _Raisons(
    lignes: [
      initiale
          ? 'Aucune densité mesurée le jour du brassage.'
          : 'Aucune densité mesurée en fermentation.',
    ],
    actions: [
      if (mine && saisir != null)
        (label: 'Saisir la densité initiale', onTap: saisir),
    ],
  );
}

_Raisons _raisonsDegre(MeasuredResult result) {
  if (result is! MeasuredUnavailable) return const _Raisons();
  final kinds = result.gaps.map((g) => g.kind).toSet();
  final initiale = kinds.contains(MeasurementGapKind.originalGravity);
  final finale = kinds.contains(MeasurementGapKind.finalGravity);
  return _Raisons(
    lignes: [
      initiale && finale
          ? 'Dépend des deux densités.'
          : initiale
          ? 'Dépend de la densité initiale.'
          : 'Dépend de la densité finale.',
    ],
  );
}

_Raisons _raisonsVolume(MeasuredResult result, bool mine, VoidCallback saisir) {
  if (result is! MeasuredUnavailable) return const _Raisons();
  return _Raisons(
    lignes: const ['Aucun volume mesuré le jour du brassage.'],
    actions: [
      if (mine) (label: 'Saisir le volume en fermenteur', onTap: saisir),
    ],
  );
}

_Raisons _raisonsRendement(
  MeasuredResult result,
  bool mine,
  VoidCallback saisirVolume,
  VoidCallback saisirDensite,
) {
  if (result is! MeasuredUnavailable) return const _Raisons();
  final lignes = <String>[];
  final actions = <({String label, VoidCallback onTap})>[];
  for (final gap in result.gaps) {
    switch (gap.kind) {
      case MeasurementGapKind.noMalt:
        return const _Raisons(
          lignes: ['Sans malt, le rendement ne s\'applique pas.'],
        );
      case MeasurementGapKind.originalGravity:
        lignes.add('Aucune densité initiale mesurée.');
        if (mine) {
          actions.add((
            label: 'Saisir la densité initiale',
            onTap: saisirDensite,
          ));
        }
      case MeasurementGapKind.fermenterVolume:
        lignes.add('Aucun volume mesuré le jour du brassage.');
        if (mine) {
          actions.add((
            label: 'Saisir le volume en fermenteur',
            onTap: saisirVolume,
          ));
        }
      case MeasurementGapKind.extractYield:
        lignes.add('Rendement d\'extrait non renseigné : ${_noms(gap)}.');
      case MeasurementGapKind.fermentableKind:
        lignes.add(
          'Nature inconnue dans la recette du brassin : ${_noms(gap)}. Le '
          'rendement ne peut pas être calculé.',
        );
      case MeasurementGapKind.sugarsInWort:
        lignes.add(
          mine
              ? "Indiquez si les ingrédients ajoutés hors de l'empâtage étaient dans le "
                    'moût à cette mesure.'
              : "Le brasseur n'a pas indiqué si les ingrédients ajoutés hors de "
                    "l'empâtage étaient dans le moût.",
        );
      case MeasurementGapKind.finalGravity:
        break;
    }
  }
  return _Raisons(lignes: lignes, actions: actions);
}

String _noms(MeasurementGap gap) =>
    {for (final i in gap.items) i.name}.join(', ');

const _tabulaire = [FontFeature.tabularFigures()];

/// Question posée quand la copie figée contient autre chose qu'un malt (RR3) :
/// sucre, miel, fruit, jus, extrait de malt, nature à préciser. Elle nomme ces
/// ingrédients, tels que la recette les écrit (« Les ingrédients ajoutés hors
/// de l'empâtage (Candi, Miel) étaient-ils dans le moût à cette mesure ? ») ;
/// « hors de l'empâtage » reste juste pour un extrait de malt, qui n'est pas
/// empâté. Les noms n'ont pas d'article : la phrase ne dépend pas de leur genre.
String questionSucres(List<String> noms) => noms.length == 1
    ? 'L\'ingrédient ajouté hors de l\'empâtage (${noms.single}) était-il '
          'dans le moût à cette mesure ?'
    : 'Les ingrédients ajoutés hors de l\'empâtage (${noms.join(', ')}) '
          'étaient-ils dans le moût à cette mesure ?';

class _EnTeteTableau extends StatelessWidget {
  const _EnTeteTableau();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return ExcludeSemantics(
      child: Row(
        children: [
          const Expanded(flex: 3, child: SizedBox.shrink()),
          for (final t in const ['Prévu', 'Mesuré', 'Écart'])
            Expanded(flex: 2, child: Text(t, style: style)),
        ],
      ),
    );
  }
}

class _LigneComparaison extends StatelessWidget {
  const _LigneComparaison({required this.donnees, required this.disposition});

  final _DonneesLigne donnees;
  final _Disposition disposition;

  String? get _prevu {
    final p = donnees.ligne.planned;
    return p == null ? null : donnees.format(p);
  }

  String? get _ecart {
    final d = donnees.ligne.difference;
    return d == null ? null : donnees.ecart(d);
  }

  Widget _valeurMesuree(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    switch (donnees.ligne.measured) {
      case MeasuredComputed(:final value):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              donnees.format(value),
              style: theme.textTheme.titleLarge?.copyWith(
                fontFeatures: _tabulaire,
              ),
            ),
            if (donnees.suffixeValeur != null)
              Text(donnees.suffixeValeur!, style: theme.textTheme.bodySmall),
          ],
        );
      case MeasuredUnavailable():
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 18, color: muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Indisponible',
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
            ),
          ],
        );
      case MeasuredImpossible():
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 18, color: muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Calcul impossible',
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
            ),
          ],
        );
    }
  }

  /// Lecture d'une ligne, dans toutes les dispositions : un seul nœud, qui nomme ses
  /// colonnes et dit « non renseigné » à la place de « — ».
  String get _libelleLigne {
    const absent = 'non renseigné';
    final mesure = switch (donnees.ligne.measured) {
      MeasuredComputed(:final value) => [
        donnees.format(value),
        ?donnees.suffixeValeur,
      ].join(', '),
      MeasuredUnavailable() => 'indisponible',
      MeasuredImpossible() => 'calcul impossible',
    };
    return '${donnees.label}. Prévu ${_prevu ?? absent}. Mesuré $mesure. '
        'Écart ${_ecart ?? absent}.';
  }

  String? get _texteImpossible {
    final m = donnees.ligne.measured;
    if (m is! MeasuredImpossible) return null;
    return switch (m.kind) {
      MeasuredImpossibleKind.finalAboveOriginal =>
        donnees.mine
            ? 'Calcul impossible : la densité finale dépasse la densité '
                  'initiale. Vérifiez les mesures retenues.'
            : 'Calcul impossible : la densité finale dépasse la densité '
                  'initiale.',
      MeasuredImpossibleKind.sugarsExplainGravity =>
        'Calcul impossible : les sucres expliquent à eux seuls la densité mesurée.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textePlein = theme.textTheme.bodyLarge?.copyWith(
      fontFeatures: _tabulaire,
    );
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final d = donnees;
    final prevu = _prevu;
    final ecart = _ecart;
    final valeurs = disposition == _Disposition.empilee
        ? <Widget>[
            Text('Prévu : ${prevu ?? '—'}', style: textePlein),
            Row(
              children: [
                const Text('Mesuré : '),
                Flexible(child: _valeurMesuree(context)),
              ],
            ),
            Text('Écart : ${ecart ?? '—'}', style: textePlein),
          ]
        : <Widget>[];
    Widget colonne(String titre, Widget valeur) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titre, style: theme.textTheme.labelMedium),
          valeur,
        ],
      ),
    );
    final Widget corps = switch (disposition) {
      _Disposition.empilee => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.label, style: theme.textTheme.titleSmall),
          ...valeurs,
        ],
      ),
      _Disposition.colonnes => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.label, style: theme.textTheme.titleSmall),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              colonne('Prévu', Text(prevu ?? '—', style: textePlein)),
              colonne('Mesuré', _valeurMesuree(context)),
              colonne('Écart', Text(ecart ?? '—', style: textePlein)),
            ],
          ),
        ],
      ),
      _Disposition.lignes => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(d.label, style: theme.textTheme.titleSmall),
          ),
          Expanded(flex: 2, child: Text(prevu ?? '—', style: textePlein)),
          Expanded(flex: 2, child: _valeurMesuree(context)),
          Expanded(flex: 2, child: Text(ecart ?? '—', style: textePlein)),
        ],
      ),
    };
    final retenue = d.retenue;
    final impossible = _texteImpossible;
    final origine = d.origine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: _libelleLigne,
            excludeSemantics: true,
            child: corps,
          ),
          if (origine != null || d.onChanger != null)
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (origine != null) Text(origine, style: muted),
                      if (retenue != null && retenue.event.hasPendingWrites)
                        const Etiquette(label: 'En attente du réseau'),
                    ],
                  ),
                ),
                if (d.onChanger != null)
                  Semantics(
                    label: d.changerSemantique,
                    button: true,
                    excludeSemantics: true,
                    onTap: d.onChanger,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: d.onChanger,
                      child: const Text('Changer'),
                    ),
                  ),
              ],
            ),
          for (final r in d.raisons.lignes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: Text('•  ')),
                  Expanded(child: Text(r, style: muted)),
                ],
              ),
            ),
          for (final a in d.raisons.actions)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: a.onTap, child: Text(a.label)),
            ),
          if (impossible != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(impossible),
            ),
          for (final a in d.avertissements)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(a)),
                ],
              ),
            ),
          ?d.bas,
        ],
      ),
    );
  }
}

class _QuestionSucres extends StatelessWidget {
  const _QuestionSucres({
    required this.question,
    required this.valeur,
    required this.onChanged,
  });

  final String question;
  final bool? valeur;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(question)),
          const SizedBox(height: 4),
          Semantics(
            container: true,
            label: question,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Oui')),
                ButtonSegment(value: false, label: Text('Non')),
              ],
              emptySelectionAllowed: true,
              selected: {?valeur},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) onChanged(s.single);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Choix d'une mesure : `event` nul pour la dernière mesure.
class _Choix {
  const _Choix(this.event);

  final BrewEvent? event;

  String? get eventId => event?.id;
}

class _FeuilleChoix extends StatelessWidget {
  const _FeuilleChoix({
    required this.titre,
    required this.aUneRetenue,
    required this.courant,
    required this.candidats,
    required this.libelle,
  });

  final String titre;

  /// Faux quand aucune mesure n'est retenue : revenir à la dernière mesure n'a pas de
  /// sens, et aucune ligne n'est marquée « Retenue ».
  final bool aUneRetenue;
  final String? courant;
  final List<BrewEvent> candidats;
  final ({String valeur, String origine}) Function(BrewEvent) libelle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget radio(bool actif) => Icon(
      actif ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: actif ? theme.colorScheme.primary : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(titre, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        if (aUneRetenue)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: radio(courant == null),
            selected: courant == null,
            title: const Text('Dernière mesure (automatique)'),
            trailing: courant == null ? const Text('Retenue') : null,
            onTap: () => Navigator.of(context).pop(const _Choix(null)),
          ),
        for (final e in candidats)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: radio(courant == e.id),
            selected: courant == e.id,
            title: Text(libelle(e).valeur),
            subtitle: Text(libelle(e).origine),
            trailing: courant == e.id ? const Text('Retenue') : null,
            onTap: () => Navigator.of(context).pop(_Choix(e)),
          ),
      ],
    );
  }
}

/// « Saisir la densité initiale » et « Saisir le volume en fermenteur » : mesure du
/// jour sans étape, datée (VR11).
class _FormulaireMesureSeule extends StatefulWidget {
  const _FormulaireMesureSeule({
    required this.titre,
    required this.type,
    required this.brewedAt,
    required this.now,
    required this.onSubmit,
  });

  final String titre;
  final MeasureType type;
  final DateTime? brewedAt;
  final DateTime Function() now;
  final void Function(double value, DateTime at) onSubmit;

  @override
  State<_FormulaireMesureSeule> createState() => _FormulaireMesureSeuleState();
}

class _FormulaireMesureSeuleState extends State<_FormulaireMesureSeule> {
  final _formKey = GlobalKey<FormState>();
  final _value = TextEditingController();
  final _focus = FocusNode();
  DateTime? _at;
  String? _erreur;
  bool _envoye = false;

  @override
  void dispose() {
    _value.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _changerDate() async {
    final now = widget.now();
    final base = _at ?? now;
    final aujourdhui = DateTime(now.year, now.month, now.day);
    final premier = widget.brewedAt;
    final debut = premier == null
        ? DateTime(aujourdhui.year - 5)
        : DateTime(premier.year, premier.month, premier.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(debut) ? debut : base,
      firstDate: debut.isAfter(aujourdhui) ? aujourdhui : debut,
      lastDate: aujourdhui,
    );
    if (picked == null || !mounted) return;
    final heure = await demanderHeure24(context, TimeOfDay.fromDateTime(base));
    if (heure == null || !mounted) return;
    setState(() {
      _erreur = null;
      _at = DateTime(
        picked.year,
        picked.month,
        picked.day,
        heure.hour,
        heure.minute,
      );
    });
  }

  void _soumettre() {
    if (_envoye) return;
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      unawaited(montrerChamp(invalid.first.context));
      return;
    }
    final now = widget.now();
    final at = _at ?? now;
    if (at.isAfter(now)) {
      setState(() => _erreur = kHeureFutureRefusee);
      return;
    }
    final brewedAt = widget.brewedAt;
    if (brewedAt != null && jourAvant(at, brewedAt)) {
      setState(() => _erreur = 'La mesure ne peut pas précéder le brassage.');
      return;
    }
    final double value = switch (widget.type) {
      MeasureType.gravity => switch (readGravity(_value.text)) {
        GravityRead(:final sg) => sg,
        _ => lireNombre(_value.text).valeur!,
      },
      _ => lireNombre(_value.text).valeur!,
    };
    _envoye = true;
    Navigator.of(context).pop();
    widget.onSubmit(value, at);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = _at;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(widget.titre, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          if (widget.type == MeasureType.gravity)
            ChampDensite(
              controller: _value,
              focusNode: _focus,
              autofocus: true,
              onSubmit: _soumettre,
            )
          else
            ChampNombre(
              controller: _value,
              focusNode: _focus,
              autofocus: true,
              label: 'Volume (L)',
              obligatoire: true,
              minExclu: true,
              max: 1000,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _soumettre(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  at == null
                      ? 'Date et heure : maintenant'
                      : 'Date et heure : ${formatJourHeure(at)}',
                ),
              ),
              TextButton(
                onPressed: () => unawaited(_changerDate()),
                child: const Text('Changer la date'),
              ),
            ],
          ),
          if (_erreur != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _erreur!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: _soumettre,
            child: const Text('Enregistrer la mesure'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}
