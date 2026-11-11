import 'package:brewing/brewing.dart' show maxProcessOffsetDays;
import 'package:flutter/material.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../processes/presentation/libelles_processus.dart';
import '../domain/brew.dart';
import '../domain/deroule.dart';
import 'libelles_deroule.dart';

/// Section « Déroulé » de la fiche d'un brassin (ADR-009, lot D3) : processus
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
/// les suivantes, leurs étapes repliées. Un déroulé illisible ne montre que
/// [chronologieBrassage], qui affiche la panne.
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
  });

  final Brew brew;
  final bool mine;
  final Widget chronologieBrassage;

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
    required this.onChangerDate,
    required this.onRetablirDate,
  });

  final String brewId;
  final JourneeDeroulee journee;
  final DateTime? depart;
  final ValueChanged<JourneeDeroulee>? onChangerDate;
  final ValueChanged<JourneeDeroulee>? onRetablirDate;

  @override
  Widget build(BuildContext context) {
    final changer = onChangerDate;
    final retablir = onRetablirDate;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SectionRepliable(
            titre: titreJournee(journee, depart),
            storageKey: 'journee-$brewId-${journee.key}',
            resume: resumeJourneeDeroulee(journee),
            children: [
              if (journee.etapes.isEmpty)
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
        if (changer != null)
          // ticket: /brassins/:id/menu/journee
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Actions de la journée ${journee.name.trim()}',
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: () => changer(journee),
                child: const Text(TextesDeroule.changerDate),
              ),
              if (retablir != null)
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
