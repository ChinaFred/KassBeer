import 'dart:async';

import 'package:brewing/brewing.dart'
    show
        BrewingInputException,
        FermentationPoint,
        FermentationReading,
        GravityRead,
        fermentationDayNumber,
        fermentationSeries,
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
import '../../auth/presentation/access_providers.dart';
import '../../brew_day/presentation/mesure_form.dart';
import '../data/brews_repository.dart';
import '../domain/brew.dart';
import '../domain/brew_event.dart';
import '../domain/releves.dart';
import 'brews_providers.dart';
import 'courbe_fermentation.dart';

/// Relevés affichés sur téléphone avant « Voir les N relevés plus anciens ».
const kRelevesVisibles = 5;

/// Relevé refusé : le jour du relevé précède le brassage (FE3).
const kReleveAvantBrassage = 'Le relevé ne peut pas précéder le brassage.';

/// Saisie vide (FE1).
const kReleveVide = 'Saisissez une densité, une température ou une note.';

/// Information : relevé postérieur à l'embouteillage (VR2).
const kReleveApresEmbouteillage =
    'Après l\'embouteillage : ce relevé ne compte pas dans la densité finale.';

/// Vrai si le jour calendaire de [a] précède celui de [b].
bool jourAvant(DateTime a, DateTime b) =>
    DateTime(a.year, a.month, a.day).isBefore(DateTime(b.year, b.month, b.day));

/// Série calculée par `brewing/` des relevés qui portent une valeur, ou `null` si une
/// valeur enregistrée est refusée (rapportée une fois par brassin). Sans `brewed_at`,
/// la première mesure sert d'origine : seuls les écarts sont alors lus.
List<FermentationPoint>? serieDesReleves({
  required Brew brew,
  required List<Releve> ascendants,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  if (ascendants.isEmpty) return const [];
  try {
    return fermentationSeries(
      brewedAt: brew.brewedAt ?? ascendants.first.measuredAt,
      readings: [
        for (final r in ascendants)
          FermentationReading(
            measuredAt: r.measuredAt,
            gravity: r.gravityValue,
            temperature: r.temperatureValue,
          ),
      ],
    );
  } on BrewingInputException catch (error, stackTrace) {
    if (reported.add('releve|${brew.id}|${error.field}')) {
      errors.reportError(
        feature: 'brews.fermentation_series',
        error: error,
        stackTrace: stackTrace,
        context: 'brews/${brew.id} : valeur refusée ${error.field}',
      );
    }
    return null;
  }
}

/// Libellé d'un relevé pour un refus du serveur.
String libelleReleve(ReleveSaisi releve) {
  final quand = 'du ${formatJourCourtHeure(releve.measuredAt)}';
  final gravity = releve.gravity;
  if (gravity != null) return 'Densité ${formatDensite(gravity)} $quand';
  final temperature = releve.temperature;
  if (temperature != null) {
    return 'Température ${formatCelsius(temperature)} $quand';
  }
  return 'Note $quand';
}

/// Texte lu par un lecteur d'écran pour une ligne de relevé.
String releveParle({
  required Releve releve,
  required int? jour,
  required double? ecart,
}) {
  final gravity = releve.gravityValue;
  final temperature = releve.temperatureValue;
  final note = releve.note;
  return [
    jourHeureParle(releve.measuredAt),
    if (jour != null) 'jour $jour',
    if (gravity != null) 'densité ${formatDensite(gravity)}',
    if (temperature != null)
      '${formatNombre(temperature, decimales: 1)} degrés',
    if (ecart != null)
      '${ecart < 0 ? 'moins' : 'plus'} ${formatNombre(ecart.abs(), decimales: 1)} points',
    ?note,
    if (releve.hasPendingWrites) 'en attente du réseau',
  ].join(', ');
}

/// Bloc « Relevé de fermentation » : liste, états, ajout.
class SectionReleve extends ConsumerStatefulWidget {
  const SectionReleve({
    super.key,
    required this.brew,
    required this.eventsAsync,
    required this.mine,
    required this.offline,
  });

  final Brew brew;
  final AsyncValue<ListeLue<BrewEvent>> eventsAsync;
  final bool mine;
  final bool offline;

  @override
  ConsumerState<SectionReleve> createState() => _SectionReleveState();
}

class _SectionReleveState extends ConsumerState<SectionReleve> {
  bool _tout = false;

  @override
  Widget build(BuildContext context) {
    final brew = widget.brew;
    final mine = widget.mine;
    final async = widget.eventsAsync;
    final liste = async.value;
    final peutAjouter =
        mine &&
        (brew.status == BrewStatus.fermenting ||
            brew.status == BrewStatus.conditioning);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Relevé de fermentation'),
        if (liste == null && async.hasError)
          Row(
            children: [
              const Expanded(
                child: TexteAbsent('Impossible de lire les relevés.'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(brewEventsProvider(brew.id)),
                child: const Text('Réessayer'),
              ),
            ],
          )
        else if (liste == null)
          const TexteAbsent('Chargement des relevés')
        else if (liste.documents.isEmpty && liste.fromCache && widget.offline)
          const TexteAbsent(
            'Relevés indisponibles sur cet appareil hors ligne.',
          )
        else
          ..._contenu(liste, peutAjouter),
        if (peutAjouter && brew.status == BrewStatus.conditioning)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => ouvrirAjoutReleve(context, ref, brew),
              child: const Text('Ajouter un relevé'),
            ),
          ),
      ],
    );
  }

  List<Widget> _contenu(ListeLue<BrewEvent> liste, bool peutAjouter) {
    final brew = widget.brew;
    final mine = widget.mine;
    final releves = relevesDe(liste.valides);
    if (releves.isEmpty) {
      return [
        TexteAbsent(
          peutAjouter
              ? 'Aucun relevé. Appuyez sur Ajouter un relevé.'
              : 'Aucun relevé.',
        ),
      ];
    }
    final ascendants = [
      for (final r in releves.reversed)
        if (r.aDesValeurs) r,
    ];
    final points = serieDesReleves(
      brew: brew,
      ascendants: ascendants,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(planReportsProvider),
    );
    final pointDe = {
      if (points != null)
        for (final (i, r) in ascendants.indexed) r.cle: points[i],
    };
    final brewedAt = brew.brewedAt;
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final visibles = _tout || !compact
        ? releves
        : releves.take(kRelevesVisibles).toList();
    final masques = releves.length - visibles.length;
    return [
      if (points == null)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: TexteAbsent(
            'Courbe indisponible : une valeur enregistrée est refusée.',
          ),
        )
      else if (brewedAt != null)
        CourbeFermentation(points: points),
      for (final r in visibles)
        _LigneReleve(
          releve: r,
          point: pointDe[r.cle],
          jour: brewedAt == null
              ? null
              : fermentationDayNumber(brewedAt: brewedAt, at: r.measuredAt),
          onTap: mine ? () => _corriger(r) : null,
        ),
      if (masques > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _tout = true),
            child: Text(
              'Voir ${masques == 1 ? 'le relevé plus ancien' : 'les $masques relevés plus anciens'}',
            ),
          ),
        ),
    ];
  }

  void _corriger(Releve releve) => ouvrirCorrectionReleve(
    context: context,
    ref: ref,
    brew: widget.brew,
    releve: releve,
  );
}

class _LigneReleve extends StatelessWidget {
  const _LigneReleve({
    required this.releve,
    required this.point,
    required this.jour,
    required this.onTap,
  });

  final Releve releve;
  final FermentationPoint? point;
  final int? jour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gravity = releve.gravityValue;
    final temperature = releve.temperatureValue;
    final ecart = point?.gravityChangePoints;
    final muted = theme.colorScheme.onSurfaceVariant;
    final valeurs = <String?>[
      gravity == null ? null : formatDensite(gravity),
      temperature == null ? null : formatCelsius(temperature),
      ecart == null ? null : formatEcart(ecart),
    ];
    final note = releve.note;
    final styleValeur = theme.textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: releveParle(releve: releve, jour: jour, ecart: ecart),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final minColonne =
                        kComparaisonValeurMinWidth *
                        MediaQuery.textScalerOf(context).scale(1);
                    if (constraints.maxWidth >= minColonne * 3) {
                      return Row(
                        children: [
                          for (final v in valeurs)
                            Expanded(child: Text(v ?? '', style: styleValeur)),
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 16,
                      children: [
                        for (final v in valeurs)
                          if (v != null) Text(v, style: styleValeur),
                      ],
                    );
                  },
                ),
                Text(
                  [
                    formatJourHeure(releve.measuredAt),
                    if (jour != null) 'J+$jour',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                if (note != null) Text(note, style: theme.textTheme.bodyMedium),
                if (releve.hasPendingWrites)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Etiquette(label: 'En attente du réseau'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ouvre le formulaire de relevé et écrit la saisie (FE1 à FE5).
void ouvrirAjoutReleve(BuildContext context, WidgetRef ref, Brew brew) {
  final repo = ref.read(brewsRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final offline = ref.read(grantedAccessProvider)?.offline ?? false;
  unawaited(
    // ticket: /brassins/:id/fenetre/releve
    showFeuilleOuDialogue<void>(
      context: context,
      fermetureProtegee: true,
      builder: (_) => FormulaireReleve(
        brewedAt: brew.brewedAt,
        bottledAt: brew.bottledAt,
        now: ref.read(horlogeProvider),
        onSubmit: (saisie) {
          final creation = repo.addReleve(
            brewId: brew.id,
            ownerUid: brew.ownerUid,
            releve: saisie,
          );
          unawaited(
            creation.written.catchError((Object _) {
              // Déjà rapportée par le dépôt de données.
              annoncerRefus(messenger, libelleReleve(saisie));
            }),
          );
          annoncerAvecAnnulation(
            messenger,
            offline
                ? 'Relevé enregistré sur l\'appareil. Il partira au retour du réseau.'
                : 'Relevé enregistré.',
            onAnnuler: () => unawaited(
              repo
                  .deleteEvents(brewId: brew.id, eventIds: creation.ids)
                  .catchError((Object _) {
                    annoncerRefus(
                      messenger,
                      'Annulation du ${formatJourCourtHeure(saisie.measuredAt)}',
                    );
                  }),
            ),
          );
        },
      ),
    ),
  );
}

/// Ouvre le formulaire prérempli, avec « Supprimer le relevé » (FE9, FE10).
void ouvrirCorrectionReleve({
  required BuildContext context,
  required WidgetRef ref,
  required Brew brew,
  required Releve releve,
}) {
  final repo = ref.read(brewsRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final offline = ref.read(grantedAccessProvider)?.offline ?? false;
  unawaited(
    // ticket: /brassins/:id/fenetre/releve
    showFeuilleOuDialogue<void>(
      context: context,
      fermetureProtegee: true,
      builder: (_) => FormulaireReleve(
        brewedAt: brew.brewedAt,
        bottledAt: brew.bottledAt,
        now: ref.read(horlogeProvider),
        correction: releve,
        onSubmit: (saisie) {
          unawaited(
            repo
                .correctReleve(
                  brewId: brew.id,
                  ownerUid: brew.ownerUid,
                  avant: releve,
                  releve: saisie,
                )
                .catchError((Object _) {
                  annoncerRefus(messenger, libelleReleve(saisie));
                }),
          );
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                offline
                    ? 'Relevé enregistré sur l\'appareil. Il partira au retour du réseau.'
                    : 'Relevé corrigé.',
              ),
            ),
          );
        },
        onDelete: () {
          final ids = [for (final e in releve.events) e.id];
          unawaited(
            repo.deleteEvents(brewId: brew.id, eventIds: ids).catchError((
              Object _,
            ) {
              annoncerRefus(
                messenger,
                'Suppression du ${formatJourCourtHeure(releve.measuredAt)}',
              );
            }),
          );
          annoncerAvecAnnulation(
            messenger,
            _messageSuppression(brew, ids),
            onAnnuler: () => unawaited(
              repo
                  .restoreEvents(brewId: brew.id, events: releve.events)
                  .catchError((Object _) {
                    annoncerRefus(
                      messenger,
                      'Annulation du ${formatJourCourtHeure(releve.measuredAt)}',
                    );
                  }),
            ),
          );
        },
      ),
    ),
  );
}

String _messageSuppression(Brew brew, List<String> ids) {
  if (ids.contains(brew.fgEventId)) {
    return 'Relevé supprimé. La densité finale revient à la dernière mesure.';
  }
  if (ids.contains(brew.ogEventId)) {
    return 'Relevé supprimé. La densité initiale revient à la dernière mesure.';
  }
  return 'Relevé supprimé.';
}

/// Formulaire d'un relevé : densité, température, date et heure, note repliée.
class FormulaireReleve extends StatefulWidget {
  const FormulaireReleve({
    super.key,
    required this.brewedAt,
    required this.bottledAt,
    required this.now,
    required this.onSubmit,
    this.correction,
    this.onDelete,
  });

  final DateTime? brewedAt;
  final DateTime? bottledAt;
  final DateTime Function() now;
  final ValueChanged<ReleveSaisi> onSubmit;
  final Releve? correction;
  final VoidCallback? onDelete;

  @override
  State<FormulaireReleve> createState() => _FormulaireReleveState();
}

class _FormulaireReleveState extends State<FormulaireReleve> {
  final _formKey = GlobalKey<FormState>();
  final _gravity = TextEditingController();
  final _temperature = TextEditingController();
  final _note = TextEditingController();
  final _gravityFocus = FocusNode();
  final _temperatureFocus = FocusNode();
  final _noteFocus = FocusNode();
  DateTime? _at;
  bool _noteOuverte = false;
  String? _message;
  bool _envoye = false;
  late final ({String gravity, String temperature, String note, DateTime? at})
  _initial;

  Releve? get _edit => widget.correction;

  /// Vrai si une saisie serait perdue en quittant le formulaire.
  bool get _saisieEnCours =>
      _gravity.text != _initial.gravity ||
      _temperature.text != _initial.temperature ||
      _note.text != _initial.note ||
      _at != _initial.at;

  void _changement() => setState(() {});

  Future<void> _quitter() async {
    final navigator = Navigator.of(context);
    if (!_saisieEnCours) {
      navigator.pop();
      return;
    }
    // ticket: aucun (confirmation)
    final abandon = await confirmerAbandon(
      context,
      'La saisie de ce relevé ne sera pas enregistrée.',
    );
    if (abandon && mounted) navigator.pop();
  }

  @override
  void initState() {
    super.initState();
    final edit = _edit;
    if (edit != null) {
      _at = edit.measuredAt;
      final g = edit.gravityValue;
      if (g != null) _gravity.text = formatDensite(g);
      final t = edit.temperatureValue;
      if (t != null) _temperature.text = texteSaisi(t, decimales: 1);
      final n = edit.note;
      if (n != null) {
        _note.text = n;
        _noteOuverte = true;
      }
    }
    _initial = (
      gravity: _gravity.text,
      temperature: _temperature.text,
      note: _note.text,
      at: _at,
    );
    _gravity.addListener(_changement);
    _temperature.addListener(_changement);
    _note.addListener(_changement);
  }

  @override
  void dispose() {
    _gravity.dispose();
    _temperature.dispose();
    _note.dispose();
    _gravityFocus.dispose();
    _temperatureFocus.dispose();
    _noteFocus.dispose();
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
    // ticket: aucun (sélecteur du système)
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
      _message = null;
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
    final gravity = _gravity.text.trim().isEmpty
        ? null
        : switch (readGravity(_gravity.text)) {
            GravityRead(:final sg) => sg,
            _ => null,
          };
    final temperature = lireNombre(_temperature.text).valeur;
    final note = _note.text.trim();
    if (gravity == null && temperature == null && note.isEmpty) {
      setState(() => _message = kReleveVide);
      return;
    }
    final now = widget.now();
    final at = _at ?? now;
    if (at.isAfter(now)) {
      setState(() => _message = kHeureFutureRefusee);
      return;
    }
    final brewedAt = widget.brewedAt;
    if (brewedAt != null && jourAvant(at, brewedAt)) {
      setState(() => _message = kReleveAvantBrassage);
      return;
    }
    _envoye = true;
    Navigator.of(context).pop();
    widget.onSubmit(
      ReleveSaisi(
        gravity: gravity,
        temperature: temperature,
        note: note.isEmpty ? null : note,
        measuredAt: at,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correcting = _edit != null;
    final at = _at;
    final bottled = widget.bottledAt;
    final apresEmbouteillage =
        bottled != null && jourAvant(bottled, at ?? widget.now());
    final densite = ChampDensite(
      controller: _gravity,
      focusNode: _gravityFocus,
      autofocus: !correcting,
      onSubmit: _temperatureFocus.requestFocus,
      textInputAction: TextInputAction.next,
      obligatoire: false,
    );
    final temperature = ChampNombre(
      controller: _temperature,
      focusNode: _temperatureFocus,
      label: 'Température (°C)',
      max: 110,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _soumettre(),
    );
    return PopScope(
      canPop: !_saisieEnCours,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_quitter());
      },
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                correcting ? 'Corriger le relevé' : 'Relevé',
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final minChamp =
                    kReleveChampMinWidth *
                    MediaQuery.textScalerOf(context).scale(1);
                if (constraints.maxWidth >= minChamp * 2 + 12) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: densite),
                      const SizedBox(width: 12),
                      Expanded(child: temperature),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [densite, const SizedBox(height: 12), temperature],
                );
              },
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
            if (_noteOuverte)
              TextFormField(
                controller: _note,
                focusNode: _noteFocus,
                maxLength: kEventNoteMaxLength,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setState(() => _noteOuverte = true);
                    _noteFocus.requestFocus();
                  },
                  child: const Text('Ajouter une note'),
                ),
              ),
            if (apresEmbouteillage)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(kReleveApresEmbouteillage),
              ),
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _message!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
              onPressed: _soumettre,
              child: Text(correcting ? 'Enregistrer' : 'Enregistrer le relevé'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(_quitter()),
              child: const Text('Annuler'),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onDelete!();
                },
                child: const Text('Supprimer le relevé'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
