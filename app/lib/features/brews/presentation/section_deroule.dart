import 'package:brewing/brewing.dart' show StepStatus, maxProcessOffsetDays;
import 'package:flutter/material.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../brew_day/domain/plan_du_jour.dart';
import '../../processes/presentation/libelles_processus.dart';
import '../domain/brew.dart';
import '../domain/deroule.dart';
import 'libelles_deroule.dart';

/// Section « Déroulé » de la fiche d'un brassin (ADR-010, lot D3) : processus
/// d'origine, journées et leurs dates, changements avant le départ.

/// Textes de la section.
abstract final class TextesDeroule {
  static const titre = 'Déroulé';
  static const modeleSupprime =
      'Modèle supprimé depuis ; ce brassin garde son déroulé.';
  static const fige = 'Le déroulé est figé depuis le début du brassage.';
  static const changerProcessus = 'Changer de processus';
  static const choisirAutre = 'Choisissez un autre processus.';
  static const changerDate = 'Changer la date';
  static const retablirDate = 'Rétablir la date du processus';
  static const change = 'Déroulé changé.';
  static const changeHorsLigne =
      'Déroulé changé sur l\'appareil. Il partira au retour du réseau.';
  static String prevuLe(String journee, DateTime date) =>
      '« $journee » prévu le ${formatJourMois(date)}';
  static String ecartHorsLigne(String journee) =>
      'Date de « $journee » changée sur l\'appareil. Elle partira au retour du '
      'réseau.';
  static String prevuA(String journee, int ecart) =>
      '« $journee » prévu à J+$ecart.';
  static const passer = 'Passer la journée';
  static const garder = 'Garder la journée';
  static String passerTitre(String journee) =>
      'Passer la journée « $journee » ?';
  static const passerMessage =
      'Ses étapes non commencées seront marquées sautées.';
  static String passee(String journee) => 'Journée « $journee » passée.';
  static String passeeHorsLigne(String journee) =>
      'Journée « $journee » passée sur l\'appareil. Elle partira au retour du '
      'réseau.';
}

/// Résumé d'une journée terminée : « Terminée · 3 faites, 1 sautée », ou
/// « Terminée » seul quand [plan] manque ou que la journée n'a pas d'étape. Une
/// étape ni faite ni sautée (embouteillage fait avant elle) compte « non
/// faite ».
String resumeJourneeTerminee(PlanDuJour? plan) {
  var faites = 0;
  var sautees = 0;
  var autres = 0;
  for (final l in plan?.lignes ?? const <LigneJour>[]) {
    switch (l.status) {
      case StepStatus.done:
        faites++;
      case StepStatus.skipped:
        sautees++;
      case StepStatus.running || StepStatus.pending || StepStatus.notDone:
        autres++;
    }
  }
  String compte(int n, String mot) => '$n $mot${n > 1 ? 's' : ''}';
  final parts = [
    if (faites > 0) compte(faites, 'faite'),
    if (sautees > 0) compte(sautees, 'sautée'),
    if (autres > 0) compte(autres, 'non faite'),
  ];
  return parts.isEmpty ? 'Terminée' : 'Terminée · ${parts.join(', ')}';
}

/// Résumé du pli « Déroulé » après le brassage : « 3 journées », ou le nombre
/// d'étapes d'un déroulé d'une journée ; `null` pour un déroulé illisible.
String? resumeDeroule(Deroule deroule) {
  if (deroule.probleme != null) return null;
  final journees = deroule.journees;
  return journees.length > 1
      ? formatJournees(journees.length)
      : formatEtapes(deroule.brassage?.etapes.length ?? 0);
}

/// Contenu de la section : en-tête du processus, puis chaque journée. La
/// journée de brassage montre [chronologieBrassage] (heures, états, mesures) ;
/// les suivantes, repliées, leur chronologie une fois commencées
/// ([chronologieJournee], lot D4), sinon leurs étapes. Un déroulé illisible ne
/// montre que [chronologieBrassage], qui affiche la panne.
class SectionDeroule extends StatelessWidget {
  const SectionDeroule({
    super.key,
    required this.brew,
    required this.mine,
    required this.chronologieBrassage,
    required this.modeleSupprime,
    this.onChangerProcessus,
    this.onChangerDate,
    this.onRetablirDate,
    this.retablissables = const {},
    this.chronologieJournee,
    this.resumeJournee,
    this.onPasser,
    this.passables = const {},
  });

  final Brew brew;
  final bool mine;
  final Widget chronologieBrassage;

  /// Chronologie d'une journée après le brassage déjà commencée, ou `null` pour
  /// lister ses étapes.
  final Widget? Function(JourneeDeroulee journee)? chronologieJournee;

  /// Résumé d'une journée après le brassage, ou `null` pour son résumé prévu
  /// (« 4 étapes · 25 min ») : une journée terminée (« Terminée · … »).
  final String? Function(JourneeDeroulee journee)? resumeJournee;

  /// « Passer la journée » ; offert pour les clés de [passables] seulement.
  final ValueChanged<JourneeDeroulee>? onPasser;
  final Set<String> passables;

  /// Le modèle d'origine n'existe plus sur le serveur.
  final bool modeleSupprime;

  /// « Changer de processus » ; `null` le masque (après le départ, autre
  /// membre).
  final VoidCallback? onChangerProcessus;

  /// « Changer la date » d'une journée après le brassage ; `null` le masque.
  final ValueChanged<JourneeDeroulee>? onChangerDate;

  /// « Rétablir la date du processus » ; offert pour les clés de
  /// [retablissables] seulement.
  final ValueChanged<JourneeDeroulee>? onRetablirDate;
  final Set<String> retablissables;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final deroule = brew.deroule;
    final depart = brew.departDeroule;
    final changer = onChangerProcessus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deroule.probleme == null)
          Text(libelleProcessus(deroule), style: theme.textTheme.bodyLarge),
        if (modeleSupprime) Text(TextesDeroule.modeleSupprime, style: muted),
        if (changer != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: changer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text(TextesDeroule.changerProcessus),
              ),
            ),
          ),
        if (mine && brew.brewedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(TextesDeroule.fige, style: muted),
          ),
        if (deroule.probleme != null)
          chronologieBrassage
        else
          for (final j in deroule.journees)
            if (j.role == RoleJournee.brassage) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    titreJournee(j, depart),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
              chronologieBrassage,
            ] else
              _Journee(
                brewId: brew.id,
                journee: j,
                depart: depart,
                chronologie: chronologieJournee?.call(j),
                resume: resumeJournee?.call(j),
                onPasser: passables.contains(j.key) ? onPasser : null,
                onChangerDate: onChangerDate,
                onRetablirDate: retablissables.contains(j.key)
                    ? onRetablirDate
                    : null,
              ),
      ],
    );
  }
}

/// Journée après le brassage, repliée : ses étapes, nom et durée.
class _Journee extends StatelessWidget {
  const _Journee({
    required this.brewId,
    required this.journee,
    required this.depart,
    required this.chronologie,
    required this.resume,
    required this.onPasser,
    required this.onChangerDate,
    required this.onRetablirDate,
  });

  final String brewId;
  final JourneeDeroulee journee;
  final DateTime? depart;

  /// Chronologie de la journée commencée ; `null` : ses étapes « nom · durée ».
  final Widget? chronologie;

  /// Résumé de la journée terminée ; `null` : son résumé prévu.
  final String? resume;
  final ValueChanged<JourneeDeroulee>? onPasser;
  final ValueChanged<JourneeDeroulee>? onChangerDate;
  final ValueChanged<JourneeDeroulee>? onRetablirDate;

  @override
  Widget build(BuildContext context) {
    final changer = onChangerDate;
    final retablir = onRetablirDate;
    final passer = onPasser;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SectionRepliable(
            titre: titreJournee(journee, depart),
            storageKey: 'journee-$brewId-${journee.key}',
            resume: resume ?? resumeJourneeDeroulee(journee),
            children: [
              if (chronologie != null)
                chronologie!
              else if (journee.etapes.isEmpty)
                const TexteAbsent('Aucune étape.')
              else
                for (final l in journee.lignes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(ligneEtapeJournee(l)),
                  ),
            ],
          ),
        ),
        if (changer != null || passer != null)
          // ticket: /brassins/:id/menu/journee
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Actions de la journée ${journee.name.trim()}',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              if (changer != null)
                PopupMenuItem(
                  value: () => changer(journee),
                  child: const Text(TextesDeroule.changerDate),
                ),
              if (passer != null)
                PopupMenuItem(
                  value: () => passer(journee),
                  child: const Text(TextesDeroule.passer),
                ),
              if (changer != null && retablir != null)
                PopupMenuItem(
                  value: () => retablir(journee),
                  child: const Text(TextesDeroule.retablirDate),
                ),
            ],
          ),
      ],
    );
  }
}

/// Feuille « Écart (jours après le brassage) » d'une journée d'un brassin sans
/// date de départ. Rend l'écart saisi, de 0 à 365.
class FormulaireEcartJournee extends StatefulWidget {
  const FormulaireEcartJournee({super.key, required this.journee});

  final JourneeDeroulee journee;

  @override
  State<FormulaireEcartJournee> createState() => _FormulaireEcartJourneeState();
}

class _FormulaireEcartJourneeState extends State<FormulaireEcartJournee> {
  final _formKey = GlobalKey<FormState>();
  late final _ecart = TextEditingController(
    text: '${widget.journee.offsetDays}',
  );

  @override
  void dispose() {
    _ecart.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(lireNombre(_ecart.text).valeur!.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '${TextesDeroule.changerDate} « ${widget.journee.name.trim()} »',
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          ChampNombre(
            controller: _ecart,
            label: 'Écart (jours après le brassage)',
            aide: 'Sans date prévue, la journée garde son écart en jours.',
            obligatoire: true,
            entier: true,
            max: maxProcessOffsetDays.toDouble(),
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: _submit,
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
