import 'dart:async';

import 'package:brewing/brewing.dart'
    show
        ActualDayDuration,
        BrewingInputException,
        DurationUpdateIssue,
        roundedStepMinutes;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/services/error_report_service.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brew_day/presentation/chronologie_jour.dart';
import '../../processes/domain/modele_processus.dart';
import '../../processes/presentation/processes_providers.dart';
import '../domain/brew.dart';
import '../domain/mise_a_jour_processus.dart';
import 'brews_providers.dart';
import 'choix_processus.dart' show TextesChoixProcessus;

/// « Mettre à jour mon processus avec ce brassin » (ADR-010) : sur la fiche d'un
/// brassin après le brassage, le propriétaire reprend des durées réelles dans
/// son modèle de processus. Seul `duration_min` des étapes cochées change ; le
/// brassin et sa recette ne sont pas écrits.

/// Textes de l'action et de sa feuille.
abstract final class TextesMajProcessus {
  static const action = 'Mettre à jour mon processus avec ce brassin';
  static const titre = 'Mettre à jour mon processus';
  static const aide =
      'Cochez les durées à reprendre. Les brassins existants gardent leur '
      'déroulé.';
  static const horsLigne =
      'Processus indisponible hors ligne. Mettez-le à jour au retour du '
      'réseau.';
  static const panne = 'Impossible de lire votre processus.';
  static const rien = 'Aucune durée à reprendre.';
  static const auMoinsUne = 'Cochez au moins une durée.';
  static const recette =
      'Les étapes tirées de la recette ne sont pas proposées.';
  static const enregistrement = 'Enregistrement';

  static String processus(String nom) => 'Processus : $nom';
  static String durees(int n) => '$n durée${n > 1 ? 's' : ''}';
  static String bouton(int n) =>
      n == 0 ? 'Mettre à jour' : 'Mettre à jour ${durees(n)}';
  static String misAJour(String nom, int n) =>
      'Processus « $nom » mis à jour : ${durees(n)}.';
  static String misAJourHorsLigne(String nom, int n) =>
      'Processus « $nom » mis à jour sur l\'appareil : ${durees(n)}. Il '
      'partira au retour du réseau.';
  static String _retablies(int n) =>
      '$n durée${n > 1 ? 's rétablies' : ' rétablie'}';
  static String retabli(String nom, int n) =>
      'Processus « $nom » : ${_retablies(n)}.';
  static String retabliHorsLigne(String nom, int n) =>
      'Processus « $nom » : ${_retablies(n)} sur l\'appareil. '
      '${n > 1 ? 'Elles partiront' : 'Elle partira'} au retour du réseau.';

  /// Journée d'une étape répétée dont la valeur n'est pas proposée :
  /// « Houblonnage à cru 1 : réel 10 min, déjà à cette durée ».
  static String journeeNonProposee(DureeDeJournee d) {
    final minutes = d.minutes;
    final raison = switch (d.raison) {
      DurationUpdateIssue.unchanged => 'déjà à cette durée',
      DurationUpdateIssue.outOfBounds => 'hors de 1 à 600 min',
      DurationUpdateIssue.noActual || null => null,
    };
    if (minutes == null || raison == null) {
      return '${d.journee} : pas de durée réelle';
    }
    return '${d.journee} : réel ${_minutes(minutes)}, $raison';
  }

  static String refus(String nom) => 'L\'enregistrement de « $nom » a échoué.';

  /// « Non proposées : 2 sans durée réelle, 1 déjà à cette durée, … », suivi
  /// de la phrase sur la recette ; `null` s'il n'y a rien à dire.
  static String? nonProposees(MiseAJourProposee p) {
    String compte(int n, String singulier, String pluriel) =>
        '$n ${n > 1 ? pluriel : singulier}';
    final raisons = [
      if (p.sansDureeReelle > 0)
        compte(p.sansDureeReelle, 'sans durée réelle', 'sans durée réelle'),
      if (p.dejaALaDuree > 0)
        compte(p.dejaALaDuree, 'déjà à cette durée', 'déjà à cette durée'),
      if (p.retirees > 0)
        compte(p.retirees, 'retirée du processus', 'retirées du processus'),
      if (p.horsBornes > 0)
        compte(p.horsBornes, 'hors de 1 à 600 min', 'hors de 1 à 600 min'),
    ];
    final phrases = [
      if (raisons.isNotEmpty) 'Non proposées : ${raisons.join(', ')}.',
      if (p.etapesDeLaRecette) recette,
    ];
    return phrases.isEmpty ? null : phrases.join(' ');
  }
}

/// « 45 min », « 1 h 30 » : minutes entières.
String _minutes(int minutes) => formatDuree(Duration(minutes: minutes));

/// Durée actuelle d'une étape du modèle, arrondie comme la compare `brewing/`.
String _actuelle(EtapeAMettreAJour e) =>
    _minutes(roundedStepMinutes(e.dureeActuelle));

/// État de l'action sur la fiche.
sealed class EtatMajProcessus {
  const EtatMajProcessus();
}

/// Hors ligne, le processus n'est pas dans le cache.
class MajHorsLigne extends EtatMajProcessus {
  const MajHorsLigne();
}

/// Lecture des processus en échec.
class MajPanne extends EtatMajProcessus {
  const MajPanne();
}

/// Au moins une durée se propose.
class MajPossible extends EtatMajProcessus {
  const MajPossible(this.modele, this.proposition);

  final ModeleProcessus modele;
  final MiseAJourProposee proposition;
}

/// État de « Mettre à jour mon processus avec ce brassin », ou `null` sans
/// action : autre membre, brassin prévu ou en cours, brassin sans processus,
/// processus en lecture, supprimé, illisible ou d'un autre membre, rien à
/// proposer. [durees] : prévu et réel des journées du brassin
/// ([dureesDesJournees]).
EtatMajProcessus? etatMajProcessus({
  required Brew brew,
  required String? readerUid,
  required bool offline,
  required AsyncValue<ListeLue<ModeleProcessus>>? modeles,
  required Map<String, ActualDayDuration> durees,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  final process = brew.process;
  final templateId = process?.templateId;
  if (readerUid == null ||
      brew.ownerUid != readerUid ||
      brew.status == BrewStatus.planned ||
      brew.status == BrewStatus.brewing ||
      process == null ||
      process.probleme != null ||
      templateId == null ||
      modeles == null) {
    return null;
  }
  final liste = modeles.value;
  if (liste == null) return modeles.hasError ? const MajPanne() : null;
  switch (liste.chercher(templateId)) {
    case DocumentTrouve<ModeleProcessus>(:final value):
      if (value.ownerUid != readerUid) return null;
      try {
        final proposition = proposerMiseAJour(
          deroule: process,
          durees: durees,
          modele: value.content,
        );
        return proposition.vide ? null : MajPossible(value, proposition);
      } on BrewingInputException catch (error, stackTrace) {
        if (reported.add('${brew.id}|maj|${value.id}|${error.field}')) {
          errors.reportError(
            feature: 'brews.process_update',
            error: error,
            stackTrace: stackTrace,
            context:
                'process_templates/${value.id} : durée refusée ${error.field}',
          );
        }
        return null;
      }
    case DocumentAbsentDuCache<ModeleProcessus>():
      return offline ? const MajHorsLigne() : null;
    case DocumentAbsent<ModeleProcessus>() ||
        DocumentIllisibleTrouve<ModeleProcessus>():
      return null;
  }
}

/// Bouton « Mettre à jour mon processus avec ce brassin », ou son état hors
/// ligne ou en panne, dans la section « Déroulé ».
class ActionMajProcessus extends StatelessWidget {
  const ActionMajProcessus({
    super.key,
    required this.etat,
    required this.onOuvrir,
    required this.onReessayer,
  });

  final EtatMajProcessus etat;
  final VoidCallback onOuvrir;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) => switch (etat) {
    MajPossible() => Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: onOuvrir,
        icon: const Icon(Icons.update),
        label: const Text(TextesMajProcessus.action),
      ),
    ),
    MajHorsLigne() => const TexteAbsent(TextesMajProcessus.horsLigne),
    MajPanne() => Row(
      children: [
        const Expanded(child: TexteAbsent(TextesMajProcessus.panne)),
        TextButton(onPressed: onReessayer, child: const Text('Réessayer')),
      ],
    ),
  };
}

/// Feuille « Mettre à jour mon processus » : un groupe par journée du modèle,
/// une case par étape proposée (décochée), des boutons radio pour une étape
/// répétée (« Garder X min » au départ). Les lignes se recalculent quand le
/// processus ou les saisies changent ; les choix restent attachés à la clé de
/// l'étape.
class FeuilleMajProcessus extends ConsumerStatefulWidget {
  const FeuilleMajProcessus({
    super.key,
    required this.brew,
    required this.tokenName,
  });

  final Brew brew;

  /// Nom du jeton, lu au premier affichage de la fiche.
  final Future<String?> tokenName;

  @override
  ConsumerState<FeuilleMajProcessus> createState() =>
      _FeuilleMajProcessusState();
}

typedef _Choix = ({String journee, int minutes});

class _FeuilleMajProcessusState extends ConsumerState<FeuilleMajProcessus> {
  /// Choix du brasseur, par clé d'étape du modèle.
  final _choix = <String, _Choix>{};
  bool _saving = false;
  String? _error;

  /// Choix encore proposés par [proposition] : clé → durée en minutes.
  Map<String, int> _choisies(MiseAJourProposee proposition) => {
    for (final MapEntry(key: cle, value: c) in _choix.entries)
      if (proposition
              .etape(cle)
              ?.valeurs
              .any((v) => v.journee == c.journee && v.minutes == c.minutes) ??
          false)
        cle: c.minutes,
  };

  EtatMajProcessus? _etat() {
    final brew = widget.brew;
    final access = ref.watch(grantedAccessProvider);
    final events = ref.watch(brewEventsProvider(brew.id)).value;
    final errors = ref.read(errorReportServiceProvider);
    final now = ref.read(horlogeProvider)();
    final plans = <String, PlanEvalue>{
      if (events != null)
        for (final j in brew.deroule.journees)
          j.key: evaluerPlan(
            brew: brew,
            events: [...events.valides],
            now: now,
            errors: errors,
            reported: ref.read(planReportsProvider),
            journee: j,
          ),
    };
    return etatMajProcessus(
      brew: brew,
      readerUid: access?.user.uid,
      offline: access?.offline ?? false,
      modeles: ref.watch(processTemplatesProvider),
      durees: dureesDesJournees(
        brew: brew,
        plans: plans,
        errors: errors,
        reported: ref.read(planReportsProvider),
      ),
      errors: errors,
      reported: ref.read(planReportsProvider),
    );
  }

  Future<void> _mettreAJour(
    ModeleProcessus modele,
    Map<String, int> choisies,
  ) async {
    if (_saving || choisies.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final nouvelles = {
      for (final MapEntry(:key, :value) in choisies.entries)
        key: value.toDouble(),
    };
    final anciennes = dureesActuelles(modele.content, nouvelles.keys);
    final contenu = avecDurees(modele.content, nouvelles);
    if (erreurModele(contenu) != null) {
      setState(() => _error = TextesChoixProcessus.modeleInvalide);
      return;
    }
    setState(() => _saving = true);
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final ownerName = await widget.tokenName;
    if (!mounted) return;
    final repository = ref.read(processesRepositoryProvider);
    final nom = modele.content.name.trim();
    final n = nouvelles.length;
    final written = repository.update(
      id: modele.id,
      content: contenu,
      ownerName: ownerName,
    );
    unawaited(
      written.catchError((Object _) {
        // Déjà rapportée par le dépôt de données ; le refus s'affiche.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(TextesMajProcessus.refus(nom))),
        );
      }),
    );
    annoncerAvecAnnulation(
      messenger,
      offline
          ? TextesMajProcessus.misAJourHorsLigne(nom, n)
          : TextesMajProcessus.misAJour(nom, n),
      // Réécrit les durées d'avant ; le dernier enregistrement l'emporte.
      onAnnuler: () => suivreEcriture(
        messenger: messenger,
        written: repository.update(
          id: modele.id,
          content: avecDurees(contenu, anciennes),
          ownerName: ownerName,
        ),
        succes: offline
            ? TextesMajProcessus.retabliHorsLigne(nom, n)
            : TextesMajProcessus.retabli(nom, n),
        refus: TextesMajProcessus.refus(nom),
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final etat = _etat();
    final titre = Semantics(
      header: true,
      child: Text(TextesMajProcessus.titre, style: theme.textTheme.titleLarge),
    );
    void fermer() => Navigator.of(context).pop();
    final annuler = TextButton(onPressed: fermer, child: const Text('Annuler'));
    if (etat is! MajPossible) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titre,
          const SizedBox(height: 16),
          TexteAbsent(switch (etat) {
            MajHorsLigne() => TextesMajProcessus.horsLigne,
            MajPanne() => TextesMajProcessus.panne,
            _ => TextesMajProcessus.rien,
          }),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (etat is MajPanne)
                TextButton(
                  onPressed: () => ref.invalidate(processTemplatesProvider),
                  child: const Text('Réessayer'),
                ),
              TextButton(onPressed: fermer, child: const Text('Fermer')),
            ],
          ),
        ],
      );
    }
    final modele = etat.modele;
    final proposition = etat.proposition;
    final choisies = _choisies(proposition);
    final nonProposees = TextesMajProcessus.nonProposees(proposition);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titre,
        const SizedBox(height: 8),
        Text(
          TextesMajProcessus.processus(modele.content.name.trim()),
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(TextesMajProcessus.aide, style: muted),
        for (final g in proposition.groupes) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(g.journee, style: theme.textTheme.titleSmall),
            ),
          ),
          for (final e in g.etapes) _etape(e, choisies, muted, theme),
        ],
        if (nonProposees != null) ...[
          const SizedBox(height: 16),
          Text(nonProposees, style: muted),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (choisies.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              TextesMajProcessus.auMoinsUne,
              textAlign: TextAlign.end,
              style: muted,
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            annuler,
            FilledButton(
              onPressed: _saving || choisies.isEmpty
                  ? null
                  : () => unawaited(_mettreAJour(modele, choisies)),
              child: _saving
                  ? const IndicateurBouton(
                      label: TextesMajProcessus.enregistrement,
                    )
                  : Text(TextesMajProcessus.bouton(choisies.length)),
            ),
          ],
        ),
      ],
    );
  }

  /// Une étape proposée : case à cocher, ou boutons radio quand plusieurs
  /// journées du brassin proposent une durée.
  Widget _etape(
    EtapeAMettreAJour e,
    Map<String, int> choisies,
    TextStyle? muted,
    ThemeData theme,
  ) {
    final actuelle = _actuelle(e);
    final autres = [
      for (final a in e.autres)
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Text(TextesMajProcessus.journeeNonProposee(a), style: muted),
        ),
    ];
    void choisir(DureeDeJournee? v) => setState(() {
      _error = null;
      if (v == null) {
        _choix.remove(e.cle);
      } else {
        _choix[e.cle] = (journee: v.journee, minutes: v.minutes!);
      }
    });

    if (e.valeurs.length == 1) {
      final v = e.valeurs.single;
      final reel = _minutes(v.minutes!);
      final journee = e.repetee ? ' · ${v.journee}' : '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: choisies.containsKey(e.cle),
            onChanged: _saving
                ? null
                : (coche) => choisir(coche ?? false ? v : null),
            title: Text(e.nom),
            subtitle: Text(
              'processus $actuelle → réel $reel$journee',
              semanticsLabel:
                  'processus $actuelle, réel $reel'
                  '${e.repetee ? ', ${v.journee}' : ''}',
            ),
          ),
          ...autres,
        ],
      );
    }

    final choisie = choisies[e.cle];
    final c = _choix[e.cle];
    final index = choisie == null || c == null
        ? -1
        : e.valeurs.indexWhere(
            (v) => v.journee == c.journee && v.minutes == c.minutes,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Même style que le titre d'une case ; le groupe ci-dessous le lit.
        ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${e.nom} · processus $actuelle',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
        Semantics(
          container: true,
          label: '${e.nom}, processus $actuelle',
          child: RadioGroup<int>(
            groupValue: index,
            onChanged: (i) {
              if (_saving || i == null) return;
              choisir(i < 0 ? null : e.valeurs[i]);
            },
            child: Column(
              children: [
                RadioListTile<int>(
                  value: -1,
                  enabled: !_saving,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Garder $actuelle'),
                ),
                for (final (i, v) in e.valeurs.indexed)
                  RadioListTile<int>(
                    value: i,
                    enabled: !_saving,
                    contentPadding: EdgeInsets.zero,
                    title: Text('réel ${_minutes(v.minutes!)} · ${v.journee}'),
                  ),
              ],
            ),
          ),
        ),
        ...autres,
      ],
    );
  }
}
