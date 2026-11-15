import 'dart:async';

import 'package:brewing/brewing.dart'
    show
        BrewingInputException,
        DensiteRetenue,
        EtatDensite,
        GravityRead,
        InstrumentDensite,
        LectureDensite,
        densiteRetenue,
        gravityGapPoints,
        kBrixMax,
        kCorrectionApprocheeMaxC,
        kCorrectionExacteMaxC,
        kFacteurRefractometreMax,
        kFacteurRefractometreMin,
        kTemperatureEchantillonMaxC,
        maxGravity,
        minGravity,
        readGravity;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brew_day/presentation/mesure_form.dart' show ChampDensite;
import '../domain/brew_event.dart';
import '../domain/preference_mesure.dart';
import 'brews_providers.dart';

/// Nom d'un instrument de densité.
String libelleInstrument(InstrumentDensite i) => switch (i) {
  InstrumentDensite.flottant20 => 'Densimètre flottant, étalonné à 20$nbsp°C',
  InstrumentDensite.flottant15v6 =>
    'Densimètre flottant, étalonné à 15,6$nbsp°C',
  InstrumentDensite.refractometre => 'Réfractomètre',
  InstrumentDensite.electronique => 'Densimètre électronique',
  InstrumentDensite.autre => 'Autre instrument, sans correction',
};

/// Ce que l'instrument demande à la saisie.
String besoinInstrument(InstrumentDensite i) => switch (i) {
  InstrumentDensite.flottant20 || InstrumentDensite.flottant15v6 =>
    'Densité lue et température de l\'échantillon.',
  InstrumentDensite.refractometre =>
    'Lecture en °Brix et facteur de correction du moût.',
  InstrumentDensite.electronique ||
  InstrumentDensite.autre => 'Densité seule, sans correction.',
};

/// Instrument choisi, sur une ligne : « Réfractomètre, facteur 1,04 »,
/// « À choisir ».
String resumeInstrument(PreferenceMesure? p) {
  if (p == null) return 'À choisir';
  final nom = libelleInstrument(p.instrument);
  if (!p.instrument.lectureBrix) return nom;
  final f = p.facteur;
  return f == null
      ? '$nom, facteur à renseigner'
      : '$nom, facteur ${formatNombre(f, decimales: 3)}';
}

/// Message d'une correction en température approchée.
String get kCorrectionApprochee =>
    'Correction approchée au-delà de ${formatCelsius(kCorrectionExacteMaxC)}. '
    'Refroidissez l\'échantillon vers 20$nbsp°C pour une mesure fiable.';

/// Message d'une température hors de la plage de correction. La saisie et les
/// règles bornent la température à 0 °C au moins : seul le dépassement de
/// [kCorrectionApprocheeMaxC] peut s'afficher.
String get kCorrectionHorsPlage =>
    'Correction impossible au-delà de '
    '${formatCelsius(kCorrectionApprocheeMaxC)}.';

const kChoisirInstrument = 'Choisissez un instrument.';

const kFacteurARenseigner =
    'Facteur à renseigner : aucune conversion en densité. Appuyez sur Changer.';
const kDensiteInitialeASaisir =
    'Densité initiale à saisir : la lecture n\'est pas corrigée de l\'alcool.';
const kCorrectionRefusee =
    'Correction impossible : le calcul est refusé. La lecture est retenue.';

/// Complément d'une densité retenue, après sa valeur : « corrigée, lue 1050,0 à
/// 68 °C », « lue 12,4 °Brix », « facteur à renseigner ». `null` pour une mesure
/// sans instrument. [avecEtiquette] : l'écran pose l'étiquette « corrigée » à
/// côté ; le complément commence alors par « lue … ».
String? complementDensite(
  BrewEvent e,
  DensiteRetenue d, {
  bool avecEtiquette = false,
}) {
  final detail = e.densite;
  if (detail == null) return null;
  final brix = detail.brix;
  final t = detail.temperatureEchantillon;
  final lue = d.lueSg;
  final lecture = brix != null
      ? 'lue ${formatNombre(brix, decimales: 1, fixe: true)}$nbsp°Brix'
      : lue == null
      ? 'lue'
      : 'lue ${formatDensite(lue)}';
  final a = t == null ? '' : ' à ${formatCelsius(t)}';
  return switch (d.etat) {
    EtatDensite.lue => null,
    EtatDensite.corrigee || EtatDensite.approchee =>
      avecEtiquette ? '$lecture$a' : 'corrigée, $lecture$a',
    EtatDensite.convertie => lecture,
    EtatDensite.nonCorrigee =>
      brix != null ? '$lecture, sans correction' : 'lue$a, sans correction',
    EtatDensite.sansTemperature => 'lue, sans température',
    EtatDensite.horsPlage => 'lue$a, sans correction',
    EtatDensite.facteurManquant => 'facteur à renseigner',
    EtatDensite.densiteInitialeManquante =>
      '$lecture, densité initiale à saisir',
    EtatDensite.horsBornes =>
      brix != null ? 'densité hors bornes' : 'lue$a, sans correction',
  };
}

/// Densité retenue à l'écran : « 1070,7 », « ≈ 1070,7 », « 12,4 °Brix » sans
/// densité (réfractomètre sans facteur).
String valeurDensite(BrewEvent e, DensiteRetenue d) {
  final sg = d.sg;
  if (sg == null) {
    final brix = e.densite?.brix;
    return brix == null
        ? '—'
        : '${formatNombre(brix, decimales: 1, fixe: true)}$nbsp°Brix';
  }
  return d.etat == EtatDensite.approchee
      ? '≈$nbsp${formatDensite(sg)}'
      : formatDensite(sg);
}

/// « Densité 1070,7 · corrigée, lue 1050,0 à 68 °C » ; une mesure sans
/// instrument garde son libellé : « 1057,9 ».
String libelleDensiteMesure(BrewEvent e, DensiteRetenue d) {
  final complement = complementDensite(e, d);
  if (e.densite == null) return valeurDensite(e, d);
  return ['Densité ${valeurDensite(e, d)}', ?complement].join(' · ');
}

/// Feuille de choix de l'instrument : une ligne par instrument, et le facteur
/// du réfractomètre. Rend le choix, ou `null` si le brasseur annule.
Future<PreferenceMesure?> choisirInstrument(
  BuildContext context, {
  required PreferenceMesure? actuelle,
}) =>
    // ticket: /brassins/:id/fenetre/densimetre, /brassins/:id/preparer/fenetre/densimetre, /brassins/:id/jour/fenetre/densimetre, /brassins/:id/jour/:journee/fenetre/densimetre, /brassins/:id/jour/:journee/preparer/fenetre/densimetre
    showFeuilleOuDialogue<PreferenceMesure>(
      context: context,
      builder: (_) => _ChoixInstrument(actuelle: actuelle),
    );

/// Écrit [preference] pour le compte connecté : écriture simple, sans
/// transaction, faite dans le cache dès l'appel (P2). Un refus du serveur est
/// rapporté par le dépôt et annoncé.
void enregistrerPreferenceMesure(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  PreferenceMesure preference,
) {
  final uid = ref.read(grantedAccessProvider)?.user.uid;
  if (uid == null) return;
  unawaited(
    ref
        .read(preferenceMesureRepositoryProvider)
        .save(uid: uid, preference: preference)
        .catchError((Object _) {
          // Déjà rapportée par le dépôt de données.
          annoncerRefus(messenger, 'choix du densimètre');
        }),
  );
}

class _ChoixInstrument extends StatefulWidget {
  const _ChoixInstrument({required this.actuelle});

  final PreferenceMesure? actuelle;

  @override
  State<_ChoixInstrument> createState() => _ChoixInstrumentState();
}

class _ChoixInstrumentState extends State<_ChoixInstrument> {
  final _formKey = GlobalKey<FormState>();
  final _facteur = TextEditingController();
  InstrumentDensite? _instrument;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _instrument = widget.actuelle?.instrument;
    final f = widget.actuelle?.facteur;
    if (f != null) _facteur.text = texteSaisi(f);
  }

  @override
  void dispose() {
    _facteur.dispose();
    super.dispose();
  }

  void _valider() {
    final instrument = _instrument;
    if (instrument == null) {
      setState(() => _erreur = kChoisirInstrument);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      PreferenceMesure(
        instrument: instrument,
        facteur: lireNombre(_facteur.text).valeur,
      ),
    );
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
            child: Text('Densimètre', style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 8),
          RadioGroup<InstrumentDensite>(
            groupValue: _instrument,
            onChanged: (i) => setState(() {
              _instrument = i;
              _erreur = null;
            }),
            child: Column(
              children: [
                for (final i in InstrumentDensite.values)
                  RadioListTile<InstrumentDensite>(
                    value: i,
                    contentPadding: EdgeInsets.zero,
                    title: Text(libelleInstrument(i)),
                    subtitle: Text(besoinInstrument(i)),
                  ),
              ],
            ),
          ),
          if (_instrument == InstrumentDensite.refractometre) ...[
            const SizedBox(height: 8),
            ChampNombre(
              controller: _facteur,
              label: 'Facteur de correction du moût',
              aide:
                  'Lecture du moût divisée par sa densité en °Plato. Sans '
                  'facteur, aucune conversion en densité.',
              min: kFacteurRefractometreMin,
              max: kFacteurRefractometreMax,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _valider(),
            ),
          ],
          if (_erreur != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _erreur!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

/// État d'une saisie de densité : instrument, lecture, température de
/// l'échantillon, case « Corriger ». Créé et libéré par le formulaire qui la
/// porte.
class SaisieDensiteControleur extends ChangeNotifier {
  SaisieDensiteControleur();

  /// Lecture déjà saisie : mesure corrigée (ME5) ou saisie refusée reprise.
  /// [sg] : lecture en SG ; [detail] : instrument et lecture brute, nul sans
  /// instrument.
  SaisieDensiteControleur.depuis(double? sg, DetailDensite? detail) {
    _instrument = detail?.instrument;
    _facteur = detail?.facteur;
    _corriger = detail?.corriger ?? true;
    _instrumentFixe = true;
    final brix = detail?.brix;
    if (brix != null) {
      lecture.text = texteSaisi(brix, decimales: 1);
    } else if (sg != null) {
      lecture.text = formatDensite(sg);
    }
    final t = detail?.temperatureEchantillon;
    if (t != null) temperature.text = texteSaisi(t, decimales: 1);
  }

  final lecture = TextEditingController();
  final temperature = TextEditingController();
  InstrumentDensite? _instrument;
  double? _facteur;
  bool _corriger = true;

  /// Vrai dès que l'instrument vient de la mesure corrigée ou du brasseur : la
  /// préférence ne le remplace plus.
  bool _instrumentFixe = false;

  InstrumentDensite? get instrument => _instrument;
  double? get facteur => _facteur;
  bool get corriger => _corriger;

  set corriger(bool value) {
    _corriger = value;
    notifyListeners();
  }

  /// Reprend la préférence lue tant que rien n'a fixé l'instrument.
  void suivrePreference(PreferenceMesure? p) {
    if (_instrumentFixe || p == null) return;
    _instrument = p.instrument;
    _facteur = p.facteur;
  }

  /// Instrument choisi dans le formulaire ; une lecture d'une autre unité
  /// (°Brix ou densité) est effacée.
  void choisir(PreferenceMesure p) {
    final avant = _instrument?.lectureBrix ?? false;
    _instrument = p.instrument;
    _facteur = p.facteur;
    _instrumentFixe = true;
    if (avant != p.instrument.lectureBrix) lecture.clear();
    if (!p.instrument.flottant) temperature.clear();
    notifyListeners();
  }

  bool get vide => lecture.text.trim().isEmpty;

  /// Densité saisie, ou `null` si la lecture est vide ou illisible.
  DensiteSaisie? saisie() {
    final instrument = _instrument;
    if (instrument != null && instrument.lectureBrix) {
      final brix = lireNombre(lecture.text).valeur;
      if (brix == null) return null;
      return DensiteSaisie(
        detail: DetailDensite(
          instrument: instrument,
          brix: brix,
          facteur: _facteur,
          corriger: _corriger,
        ),
      );
    }
    final sg = switch (readGravity(lecture.text)) {
      GravityRead(:final sg) => sg,
      _ => null,
    };
    if (sg == null) return null;
    if (instrument == null) return DensiteSaisie(sg: sg);
    return DensiteSaisie(
      sg: sg,
      detail: DetailDensite(
        instrument: instrument,
        temperatureEchantillon: instrument.flottant
            ? lireNombre(temperature.text).valeur
            : null,
        corriger: instrument.corrige ? _corriger : null,
      ),
    );
  }

  @override
  void dispose() {
    lecture.dispose();
    temperature.dispose();
    super.dispose();
  }
}

/// Saisie d'une densité selon l'instrument du brasseur : ligne « Densimètre :
/// … · Changer », lecture, température de l'échantillon (flottant), et la
/// valeur retenue calculée par `brewing/` avec la case « Corriger ».
///
/// Sans instrument choisi (« À choisir »), une densité simple, comme une mesure
/// ancienne. Changer d'instrument vaut pour cette mesure et devient la
/// préférence du brasseur.
class BlocDensite extends ConsumerStatefulWidget {
  const BlocDensite({
    super.key,
    required this.controleur,
    required this.focusNode,
    required this.onSubmit,
    this.enFermentation = false,
    this.densiteInitiale,
    this.autofocus = false,
    this.obligatoire = true,
    this.grand = true,
    this.prefixeLibelle,
    this.suffixeLibelle = '',
    this.textInputAction = TextInputAction.done,
    this.onTemperatureModifiee,
  });

  final SaisieDensiteControleur controleur;
  final FocusNode focusNode;

  /// Appelé par la touche de validation du dernier champ.
  final VoidCallback onSubmit;

  /// Mesure en fermentation : un réfractomètre se corrige de l'alcool.
  final bool enFermentation;

  /// Densité initiale retenue du brassin (SG), pour cette correction.
  final double? densiteInitiale;
  final bool autofocus;

  /// Faux : une lecture vide est acceptée (relevé, embouteillage).
  final bool obligatoire;
  final bool grand;

  /// Début des libellés de la lecture (« Densité finale ») ; `null` :
  /// « Densité », « Densité lue », « Lecture (°Brix) ».
  final String? prefixeLibelle;

  /// Fin des libellés de la lecture (« (facultatif) » avec son espace).
  final String suffixeLibelle;
  final TextInputAction textInputAction;

  /// Appelé quand le brasseur modifie la température de l'échantillon.
  final VoidCallback? onTemperatureModifiee;

  @override
  ConsumerState<BlocDensite> createState() => _BlocDensiteState();
}

class _BlocDensiteState extends ConsumerState<BlocDensite> {
  final _temperatureFocus = FocusNode();
  bool _refusRapporte = false;

  SaisieDensiteControleur get _c => widget.controleur;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changement);
    _c.lecture.addListener(_changement);
    _c.temperature.addListener(_changement);
  }

  @override
  void dispose() {
    _c.removeListener(_changement);
    _c.lecture.removeListener(_changement);
    _c.temperature.removeListener(_changement);
    _temperatureFocus.dispose();
    super.dispose();
  }

  void _changement() {
    if (mounted) setState(() {});
  }

  Future<void> _changer() async {
    final messenger = ScaffoldMessenger.of(context);
    final instrument = _c.instrument;
    final choix = await choisirInstrument(
      context,
      actuelle: instrument == null
          ? null
          : PreferenceMesure(instrument: instrument, facteur: _c.facteur),
    );
    if (choix == null || !mounted) return;
    _c.choisir(choix);
    enregistrerPreferenceMesure(ref, messenger, choix);
  }

  /// Valeur retenue de la saisie, ou `null` sans lecture lisible. Un refus de
  /// `brewing/` est rapporté une fois et rend `null` avec [_refuse].
  DensiteRetenue? _retenue() {
    final saisie = _c.saisie();
    final detail = saisie?.detail;
    if (saisie == null || detail == null) return null;
    try {
      return densiteRetenue(
        LectureDensite(
          instrument: detail.instrument,
          sg: saisie.sg,
          brix: detail.brix,
          temperatureEchantillonC: detail.temperatureEchantillon,
          facteur: detail.facteur,
          corriger: detail.corriger ?? true,
          enFermentation: widget.enFermentation,
        ),
        densiteInitialeSg: widget.densiteInitiale,
      );
    } on BrewingInputException catch (error, stackTrace) {
      if (!_refusRapporte) {
        _refusRapporte = true;
        ref
            .read(errorReportServiceProvider)
            .reportError(
              feature: 'brews.gravity_correction',
              error: error,
              stackTrace: stackTrace,
              context: 'saisie de densité : valeur refusée ${error.field}',
            );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(grantedAccessProvider)?.user.uid;
    if (uid != null) {
      _c.suivrePreference(
        preferenceMesureDe(ref.watch(preferenceMesureProvider(uid)).value),
      );
    }
    final theme = Theme.of(context);
    final instrument = _c.instrument;
    final grand = widget.grand
        ? TextStyle(fontSize: StylesJourDeBrassage.of(context).saisie)
        : null;
    final ligne = Row(
      children: [
        Expanded(
          child: Text(
            'Densimètre : ${resumeInstrument(instrument == null ? null : PreferenceMesure(instrument: instrument, facteur: _c.facteur))}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        BoutonChangerDensimetre(onPressed: () => unawaited(_changer())),
      ],
    );
    final prefixe = widget.prefixeLibelle;
    final suffixe = widget.suffixeLibelle;
    final flottant = instrument?.flottant ?? false;
    final brix = instrument?.lectureBrix ?? false;
    final champLecture = brix
        ? ChampNombre(
            controller: _c.lecture,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            label: prefixe == null
                ? 'Lecture (°Brix)$suffixe'
                : '$prefixe, lecture (°Brix)$suffixe',
            obligatoire: widget.obligatoire,
            max: kBrixMax,
            style: grand,
            textInputAction: widget.textInputAction,
            onSubmitted: (_) => widget.onSubmit(),
          )
        : ChampDensite(
            controller: _c.lecture,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            label: flottant
                ? '${prefixe ?? 'Densité'} lue$suffixe'
                : '${prefixe ?? 'Densité'}$suffixe',
            obligatoire: widget.obligatoire,
            grand: widget.grand,
            textInputAction: flottant
                ? TextInputAction.next
                : widget.textInputAction,
            onSubmit: flottant
                ? _temperatureFocus.requestFocus
                : widget.onSubmit,
          );
    final apercu = instrument == null || !instrument.corrige
        ? null
        : _apercu(context, instrument);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ligne,
        champLecture,
        if (flottant) ...[
          const SizedBox(height: 12),
          ChampNombre(
            controller: _c.temperature,
            focusNode: _temperatureFocus,
            label: 'Température de l\'échantillon (°C)',
            aide: 'Pour proposer la densité corrigée.',
            max: kTemperatureEchantillonMaxC,
            style: grand,
            textInputAction: widget.textInputAction,
            onChanged: (_) => widget.onTemperatureModifiee?.call(),
            onSubmitted: (_) => widget.onSubmit(),
          ),
        ],
        if (apercu != null) ...[const SizedBox(height: 12), apercu],
      ],
    );
  }

  Widget? _apercu(BuildContext context, InstrumentDensite instrument) {
    if (instrument.lectureBrix && _c.facteur == null) {
      return const Encadre(
        ton: TonEncadre.avertissement,
        child: _Annonce(kFacteurARenseigner),
      );
    }
    if (_c.vide) return null;
    final saisie = _c.saisie();
    if (saisie == null) return null;
    final d = _retenue();
    if (d == null) {
      return const Encadre(
        ton: TonEncadre.erreur,
        child: _Annonce(kCorrectionRefusee),
      );
    }
    final t = saisie.detail?.temperatureEchantillon;
    final lue = d.lueSg;
    final corrigee = d.corrigee;
    final lignes = <Widget>[];
    var ton = TonEncadre.information;
    var interrupteur = false;
    switch (d.etat) {
      case EtatDensite.facteurManquant:
        ton = TonEncadre.avertissement;
        lignes.add(const _Annonce(kFacteurARenseigner));
      case EtatDensite.horsBornes:
        ton = TonEncadre.avertissement;
        lignes.add(
          _Annonce(
            'Densité hors de ${formatDensite(minGravity)} à '
            '${formatDensite(maxGravity)} : '
            '${instrument.lectureBrix ? 'aucune valeur retenue.' : 'la lecture est retenue.'}',
          ),
        );
      case EtatDensite.sansTemperature:
        lignes.add(const Text('Sans température, la densité lue est retenue.'));
      case EtatDensite.horsPlage:
        ton = TonEncadre.avertissement;
        lignes.add(_Annonce(kCorrectionHorsPlage));
      case EtatDensite.densiteInitialeManquante:
        ton = TonEncadre.avertissement;
        lignes.add(const _Annonce(kDensiteInitialeASaisir));
      case EtatDensite.convertie:
        break;
      case EtatDensite.lue:
        return null;
      case EtatDensite.corrigee ||
          EtatDensite.approchee ||
          EtatDensite.nonCorrigee:
        interrupteur = true;
        final approchee = d.correctionApprochee;
        if (approchee) ton = TonEncadre.avertissement;
        final c = corrigee!;
        final ecart = gravityGapPoints(measured: c, planned: lue!);
        final titre = instrument.flottant
            ? 'Densité corrigée à '
                  '${formatCelsius(instrument.temperatureEtalonnageC!)}'
            : 'Densité corrigée de l\'alcool';
        lignes.add(
          Text(
            '$titre : ${approchee ? '≈$nbsp' : ''}${formatDensite(c)} '
            '(${formatEcart(ecart)})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
        if (approchee) lignes.add(_Annonce(kCorrectionApprochee));
    }
    final sg = d.sg;
    // Seuls les messages d'état (_Annonce) sont annoncés, pas chaque valeur.
    return Encadre(
      ton: ton,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...lignes,
          if (interrupteur)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Corriger'),
              value: _c.corriger,
              onChanged: (v) => _c.corriger = v,
            ),
          if (sg != null)
            Text(
              'Valeur retenue : ${_retenueTexte(d, sg, t, saisie.detail?.brix)}',
            ),
        ],
      ),
    );
  }

  String _retenueTexte(DensiteRetenue d, double sg, double? t, double? brix) {
    final valeur = formatDensite(sg);
    if (d.estCorrigee) return '$valeur, corrigée';
    if (brix != null) {
      final lecture =
          '${formatNombre(brix, decimales: 1, fixe: true)}$nbsp°Brix';
      return d.etat == EtatDensite.convertie
          ? '$valeur, lue $lecture'
          : '$valeur, lue $lecture, sans correction de l\'alcool';
    }
    return t == null ? '$valeur, lue' : '$valeur, lue à ${formatCelsius(t)}';
  }
}

/// Message d'état de l'encadré, annoncé au lecteur d'écran quand il paraît ou
/// change (approchée, impossible, refusée, facteur, densité initiale).
class _Annonce extends StatelessWidget {
  const _Annonce(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) =>
      Semantics(liveRegion: true, child: Text(texte));
}

/// « Changer » de la ligne « Densimètre », lu « Changer le densimètre ».
class BoutonChangerDensimetre extends StatelessWidget {
  const BoutonChangerDensimetre({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Changer le densimètre',
    button: true,
    excludeSemantics: true,
    onTap: onPressed,
    child: TextButton(onPressed: onPressed, child: const Text('Changer')),
  );
}
