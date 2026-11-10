import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brews/domain/brew.dart';
import '../domain/brew_cost.dart';
import '../domain/cost_evaluation.dart';
import '../domain/fee.dart';
import '../domain/price.dart';
import 'bloc_cout.dart';
import 'costs_providers.dart';
import 'formats_cout.dart';

/// Textes du bloc Coût d'un brassin (CB1 à CB20). Aucune annonce ne porte de
/// montant (SE7) : seul le dialogue de « Recalculer » en affiche (CB16).
abstract final class TextesCoutBrassin {
  static const titre = 'Coût';
  static const chargement = 'Chargement du coût';
  static const lectureImpossible = 'Impossible de lire le coût.';
  static const estime = 'Coût estimé avec vos prix actuels';
  static const nonFige = 'Coût non figé';
  static const figer = 'Figer le coût';
  static const figerDesactive =
      'Complétez les éléments ci-dessus pour figer le coût.';
  static const recalculer = 'Recalculer avec mes prix actuels';
  static const illisible = 'Coût figé illisible.';
  static const aucunFraisParBouteille = 'Aucun frais par bouteille compté.';
  static String figeLe(DateTime date) =>
      'Coût figé le ${formatDateCourte(date)}';

  static const sansBouteillesTitre = 'Figer sans les frais par bouteille ?';
  static const sansBouteillesMessage =
      'Aucun nombre de bouteilles n\'est renseigné : les frais par bouteille ne '
      'seront pas comptés.';
  static const renseigner = 'Renseigner les bouteilles';

  static const remplacerTitre = 'Remplacer le coût figé ?';
  static String remplacerMessage(BrewCost? ancien, double nouveau) =>
      '${ancien == null ? 'Le coût figé illisible' : '${formatEuros(ancien.totalEur)} du ${formatDateCourte(ancien.computedAt)}'} '
      'deviendra ${formatEuros(nouveau)}. Les prix actuels remplacent ceux du '
      'figeage.';

  static const fige = 'Coût figé.';
  static const figeHorsLigne =
      'Coût figé sur l\'appareil. Il partira au retour du réseau.';
  static const figeRefuse = 'Coût non figé : l\'enregistrement a été refusé.';
  static const recalcule = 'Coût recalculé.';
  static const recalculeHorsLigne =
      'Coût recalculé sur l\'appareil. Il partira au retour du réseau.';
  static const recalculRefuse =
      'Coût non recalculé : l\'enregistrement a été refusé.';
}

/// Texte de l'écart entre un coût figé et l'embouteillage actuel (CB15) :
/// « L'embouteillage a changé depuis le figeage : Bouteilles 50 → 52. ».
({String texte, String parle}) texteEcarts(List<EcartEmbouteillage> ecarts) {
  String valeur(ChampEmbouteillage champ, Object? v) {
    if (v == null) return 'non renseigné';
    return switch (champ) {
      ChampEmbouteillage.bouteilles => '$v',
      ChampEmbouteillage.volume => formatLitres(v as double),
      ChampEmbouteillage.sucreResucrage => formatGrammes(v as double),
      ChampEmbouteillage.natureSucre => '$v',
    };
  }

  String libelle(ChampEmbouteillage champ) => switch (champ) {
    ChampEmbouteillage.bouteilles => 'Bouteilles',
    ChampEmbouteillage.volume => 'Volume',
    ChampEmbouteillage.sucreResucrage => 'Sucre de resucrage',
    ChampEmbouteillage.natureSucre => 'Nature du sucre',
  };

  final items = [
    for (final e in ecarts)
      (
        '${libelle(e.champ)} ${valeur(e.champ, e.figee)} → '
            '${valeur(e.champ, e.actuelle)}',
        '${libelle(e.champ)} ${valeur(e.champ, e.figee)} devient '
            '${valeur(e.champ, e.actuelle)}',
      ),
  ];
  const debut = 'L\'embouteillage a changé depuis le figeage : ';
  return (
    texte: '$debut${items.map((i) => i.$1).join(', ')}.',
    parle: '$debut${items.map((i) => i.$2).join(', ')}.',
  );
}

/// Bloc « Coût » de la fiche d'un brassin, pour son propriétaire seul (CB1) :
/// estimation, coût non figé et ses raisons, « Figer le coût », coût figé,
/// écart avec l'embouteillage, « Recalculer avec mes prix actuels ».
///
/// [prices], [fees] et [cout] sont lus par la fiche, qui les capture aussi à
/// l'embouteillage (CB5). Ouvrir la fiche n'écrit rien (CB2).
class BlocCoutBrassin extends ConsumerStatefulWidget {
  const BlocCoutBrassin({
    super.key,
    required this.brew,
    required this.prices,
    required this.fees,
    required this.cout,
    required this.titreKey,
    required this.titreFocus,
    required this.onModifierEmbouteillage,
  });

  final Brew brew;
  final AsyncValue<ListeLue<Price>> prices;
  final AsyncValue<ListeLue<Fee>> fees;
  final AsyncValue<RechercheDocument<BrewCost>> cout;

  /// Titre « Coût », cible de « Voir le coût ».
  final GlobalKey titreKey;
  final FocusNode titreFocus;

  /// « Modifier l'embouteillage » ou « Renseigner les bouteilles » : nul hors
  /// de En conditionnement et Terminé.
  final VoidCallback? onModifierEmbouteillage;

  @override
  ConsumerState<BlocCoutBrassin> createState() => _BlocCoutBrassinState();
}

class _BlocCoutBrassinState extends ConsumerState<BlocCoutBrassin> {
  /// Une écriture est en préparation : un second appui est ignoré.
  bool _enCours = false;

  Brew get _brew => widget.brew;
  String get _uid => _brew.ownerUid;

  EvaluationFigeage? _figeage(
    FreezeKind kind, {
    bool sansFraisParBouteille = false,
  }) {
    final prices = widget.prices.value;
    final fees = widget.fees.value;
    if (prices == null || fees == null) return null;
    return evaluerFigeageDuBrassin(
      _brew,
      prices: prices,
      fees: fees,
      kind: kind,
      now: ref.read(horlogeProvider)(),
      sansFraisParBouteille: sansFraisParBouteille,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(costReportsProvider),
    );
  }

  ActionsRaisons _actions(ListeLue<Price>? prices) => ActionsRaisons(
    onPrix: prices == null
        ? null
        : (raison) => unawaited(
            ouvrirPrixDeRaison(
              context,
              uid: _uid,
              mesPrix: prices.valides,
              raison: raison,
            ),
          ),
    onModifierEmbouteillage: widget.onModifierEmbouteillage,
    onMesPrix: () => unawaited(context.push(AppRoutes.prices)),
  );

  bool get _offline => ref.read(grantedAccessProvider)?.offline ?? false;

  Future<void> _uneFois(Future<void> Function() action) async {
    if (_enCours) return;
    _enCours = true;
    try {
      await action();
    } finally {
      _enCours = false;
    }
  }

  /// « Figer le coût » (CB10, CB11).
  Future<void> _figer() => _uneFois(() async {
    var figeage = _figeage(FreezeKind.initial);
    if (figeage is FigeageImpossible && figeage.seulementBouteilles) {
      final modifier = widget.onModifierEmbouteillage;
      final choix = await confirmerActionOuAlternative(
        context,
        titre: TextesCoutBrassin.sansBouteillesTitre,
        paragraphes: const [TextesCoutBrassin.sansBouteillesMessage],
        libelle: 'Figer',
        alternative: modifier == null ? null : TextesCoutBrassin.renseigner,
      );
      if (!mounted) return;
      switch (choix) {
        case ChoixConfirmation.annuler:
          return;
        case ChoixConfirmation.alternative:
          modifier?.call();
          return;
        case ChoixConfirmation.confirmer:
          figeage = _figeage(FreezeKind.initial, sansFraisParBouteille: true);
      }
    }
    if (figeage is! FigeagePossible) return;
    suivreEcriture(
      messenger: ScaffoldMessenger.of(context),
      written: ref
          .read(costsRepositoryProvider)
          .saveBrewCost(uid: _uid, cost: figeage.cout),
      succes: _offline
          ? TextesCoutBrassin.figeHorsLigne
          : TextesCoutBrassin.fige,
      refus: TextesCoutBrassin.figeRefuse,
    );
  });

  /// « Recalculer avec mes prix actuels » (CB16, CB20) : remplace le document
  /// entier après confirmation.
  Future<void> _recalculer(BrewCost? ancien) => _uneFois(() async {
    // Seul le nombre de bouteilles manque : le recalcul se fait sans les frais
    // par bouteille, et le dialogue le dit, comme pour « Figer le coût » (CB11).
    var sansFrais = false;
    var avant = _figeage(FreezeKind.recalculation);
    if (avant is FigeageImpossible && avant.seulementBouteilles) {
      sansFrais = true;
      avant = _figeage(FreezeKind.recalculation, sansFraisParBouteille: true);
    }
    if (avant is! FigeagePossible) return;
    final messenger = ScaffoldMessenger.of(context);
    final modifier = widget.onModifierEmbouteillage;
    final choix = await confirmerActionOuAlternative(
      context,
      titre: TextesCoutBrassin.remplacerTitre,
      paragraphes: [
        TextesCoutBrassin.remplacerMessage(ancien, avant.cout.totalEur),
        if (sansFrais) TextesCoutBrassin.sansBouteillesMessage,
      ],
      libelle: 'Remplacer',
      alternative: sansFrais && modifier != null
          ? TextesCoutBrassin.renseigner
          : null,
    );
    if (!mounted) return;
    switch (choix) {
      case ChoixConfirmation.annuler:
        return;
      case ChoixConfirmation.alternative:
        modifier?.call();
        return;
      case ChoixConfirmation.confirmer:
        break;
    }
    // L'heure du geste date le coût (HL3).
    final figeage = _figeage(
      FreezeKind.recalculation,
      sansFraisParBouteille: sansFrais,
    );
    if (figeage is! FigeagePossible) return;
    suivreEcriture(
      messenger: messenger,
      written: ref
          .read(costsRepositoryProvider)
          .saveBrewCost(uid: _uid, cost: figeage.cout),
      succes: _offline
          ? TextesCoutBrassin.recalculeHorsLigne
          : TextesCoutBrassin.recalcule,
      refus: TextesCoutBrassin.recalculRefuse,
    );
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: widget.titreKey,
          child: Focus(
            focusNode: widget.titreFocus,
            child: const TitreSection(TextesCoutBrassin.titre),
          ),
        ),
        ..._contenu(context),
      ],
    );
  }

  List<Widget> _contenu(BuildContext context) {
    final coutAsync = widget.cout;
    final cout = coutAsync.value;
    if (cout == null && coutAsync.hasError) {
      return [
        Row(
          children: [
            const Expanded(
              child: TexteAbsent(TextesCoutBrassin.lectureImpossible),
            ),
            TextButton(
              onPressed: () => ref.invalidate(
                brewCostProvider((uid: _uid, brewId: _brew.id)),
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ];
    }
    if (cout == null) return const [TexteAbsent(TextesCoutBrassin.chargement)];
    final readerUid = ref.watch(grantedAccessProvider)?.user.uid;
    return switch (cout) {
      DocumentTrouve<BrewCost>(:final value) => _fige(
        context,
        value,
        readerUid,
      ),
      DocumentIllisibleTrouve<BrewCost>() => [
        const TexteAbsent(TextesCoutBrassin.illisible),
        ..._recalcul(null, readerUid, cout, encadre: false),
      ],
      DocumentAbsent<BrewCost>() ||
      DocumentAbsentDuCache<BrewCost>() => _nonFige(context, readerUid, cout),
    };
  }

  Widget? _etatPrix() => etatLecturePrix(
    prices: widget.prices,
    fees: widget.fees,
    onRetry: () {
      ref.invalidate(pricesProvider(_uid));
      ref.invalidate(feesProvider(_uid));
    },
  );

  /// Aucun coût figé : estimation (CB2), et au rattrapage, « Coût non figé »,
  /// ses raisons et « Figer le coût » (CB10).
  List<Widget> _nonFige(
    BuildContext context,
    String? readerUid,
    RechercheDocument<BrewCost> coutLu,
  ) {
    final theme = Theme.of(context);
    final rattrapage = figerLeCoutPropose(
      brew: _brew,
      readerUid: readerUid,
      coutLu: coutLu,
    );
    final entete = rattrapage
        ? [
            MergeSemantics(
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TextesCoutBrassin.nonFige,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ]
        : const <Widget>[];
    final etat = _etatPrix();
    if (etat != null) return [...entete, etat];
    final prices = widget.prices.requireValue;
    final fees = widget.fees.requireValue;
    final actions = _actions(prices);
    final estimation = evaluerEstimationBrassin(
      _brew,
      prices: prices,
      fees: fees,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(costReportsProvider),
    );
    final aucunFrais = fees.documents.isEmpty;
    final widgets = <Widget>[
      ...entete,
      ...switch (estimation) {
        CoutIndisponible() => [
          ...vueIndisponible(context, estimation, actions),
          if (aucunFrais &&
              !estimation.raisons.any((r) => r is CalculImpossible))
            const MentionAucunFrais(),
        ],
        CoutObtenu() => _estimation(estimation),
      },
    ];
    if (!rattrapage) return widgets;

    final figeage = _figeage(FreezeKind.initial);
    final dejaDites = estimation is CoutIndisponible
        ? estimation.raisons
        : const <RaisonCout>[];
    final autres = figeage is FigeageImpossible
        ? [
            for (final r in figeage.raisons)
              if (!dejaDites.any((d) => memeRaison(d, r))) r,
          ]
        : const <RaisonCout>[];
    final possible =
        figeage is FigeagePossible ||
        (figeage is FigeageImpossible && figeage.seulementBouteilles);
    return [
      ...widgets,
      if (autres.any((r) => r is CalculImpossible))
        const CadreCalculImpossible(),
      ...lignesRaisons(autres, actions),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          hint: possible ? null : TextesCoutBrassin.figerDesactive,
          child: FilledButton(
            onPressed: possible ? () => unawaited(_figer()) : null,
            child: const Text(TextesCoutBrassin.figer),
          ),
        ),
      ),
      if (!possible)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: ExcludeSemantics(
            child: TexteAbsent(TextesCoutBrassin.figerDesactive),
          ),
        ),
    ];
  }

  /// Estimation avec les prix actuels (CB2) : nombre réel de bouteilles, sinon
  /// bouteilles de 33 cl.
  List<Widget> _estimation(CoutObtenu cout) {
    final volume = cout.volumeL;
    final bouteilles = cout.bouteilles;
    final hypothese = [
      if (volume != null) 'Pour ${formatLitres(volume)}',
      if (bouteilles != null)
        cout.bouteillesEstimees
            ? 'environ ${bouteilles.round()} bouteilles de 33 cl, nombre de '
                  'bouteilles non renseigné'
            : formatBouteilles(bouteilles),
    ].join(' · ');
    final reelles = _brew.bottlesCount;
    return [
      const TexteHypothese(TextesCoutBrassin.estime),
      LigneFiche(label: 'Total', value: formatEuros(cout.totalEur)),
      if (cout.perBottleEur case final perBottle? when reelles != null)
        LigneFiche(
          label: 'Par bouteille (${formatBouteilles(reelles)})',
          value: formatEuros(perBottle),
        )
      else if (cout.perBottle33clEur case final perBottle?)
        LigneFiche(label: 'Bouteille de 33 cl', value: formatEuros(perBottle)),
      if (cout.perLitreEur case final perLitre?)
        LigneFiche(label: 'Par litre', value: formatEurosParLitre(perLitre)),
      if (hypothese.isNotEmpty) TexteHypothese(hypothese),
      if (cout.aucunFrais) const MentionAucunFrais(),
      DetailCout(
        lignes: lignesDetail(cout),
        storageKey: 'cout-estime-${_brew.id}',
      ),
    ];
  }

  /// Coût figé (CB12 à CB15) : le montant ne dépend plus d'aucun prix.
  List<Widget> _fige(BuildContext context, BrewCost cout, String? readerUid) {
    final theme = Theme.of(context);
    final bouteilles = cout.bottlesCount;
    final volume = cout.packagedVolumeL;
    final ecarts = ecartsDepuisFigeage(cout, _brew);
    final coutLu = DocumentTrouve<BrewCost>(cout);
    return [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            TextesCoutBrassin.figeLe(cout.computedAt),
            style: theme.textTheme.titleSmall,
          ),
          if (cout.hasPendingWrites)
            const Etiquette(label: 'En attente du réseau'),
        ],
      ),
      LigneFiche(label: 'Total', value: formatEuros(cout.totalEur)),
      if (cout.perBottleEur case final perBottle? when bouteilles != null)
        LigneFiche(
          label: 'Par bouteille (${formatBouteilles(bouteilles)})',
          value: formatEuros(perBottle),
        ),
      if (cout.perLitreEur case final perLitre? when volume != null)
        LigneFiche(
          label: 'Par litre (${formatLitres(volume)})',
          value: formatEurosParLitre(perLitre),
        ),
      if (bouteilles == null)
        const TexteHypothese(TextesCoutBrassin.aucunFraisParBouteille),
      DetailCout(
        lignes: lignesFigees(cout),
        storageKey: 'cout-fige-${_brew.id}',
      ),
      if (ecarts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          texteEcarts(ecarts).texte,
                          semanticsLabel: texteEcarts(ecarts).parle,
                          style: TextStyle(
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ..._recalcul(cout, readerUid, coutLu, encadre: true),
                ],
              ),
            ),
          ),
        )
      else
        ..._recalcul(cout, readerUid, coutLu, encadre: false),
    ];
  }

  /// Bouton « Recalculer avec mes prix actuels », désactivé et suivi des raisons
  /// de CB8 quand elles l'empêchent.
  List<Widget> _recalcul(
    BrewCost? ancien,
    String? readerUid,
    RechercheDocument<BrewCost> coutLu, {
    required bool encadre,
  }) {
    if (!recalculerPropose(brew: _brew, readerUid: readerUid, coutLu: coutLu)) {
      return const [];
    }
    final etat = _etatPrix();
    final figeage = etat == null ? _figeage(FreezeKind.recalculation) : null;
    final possible =
        figeage is FigeagePossible ||
        (figeage is FigeageImpossible && figeage.seulementBouteilles);
    final onPressed = possible ? () => unawaited(_recalculer(ancien)) : null;
    const label = Text(TextesCoutBrassin.recalculer);
    return [
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: encadre
            ? OutlinedButton(onPressed: onPressed, child: label)
            : TextButton(onPressed: onPressed, child: label),
      ),
      ?etat,
      if (figeage is FigeageImpossible) ...[
        if (figeage.raisons.any((r) => r is CalculImpossible))
          const CadreCalculImpossible(),
        ...lignesRaisons(figeage.raisons, _actions(widget.prices.value)),
      ],
    ];
  }
}
