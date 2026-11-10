import 'dart:async';

import 'package:exchange/exchange.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/fichiers/echange_fichiers.dart';
import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/services/error_report_service.dart';
import '../../auth/presentation/access_providers.dart';
import '../../equipment/domain/equipment.dart';
import '../../equipment/presentation/equipment_providers.dart';
import '../domain/import_recettes.dart';
import '../domain/recipe.dart';
import 'libelles_echange.dart';
import 'recipe_calculations_view.dart';
import 'recipes_list_screen.dart';
import 'recipes_providers.dart';

/// Statut d'une recette de l'aperçu, écrit en toutes lettres.
enum StatutImport {
  prete('Prête'),
  incomplete('Incomplète'),
  dejaImportee('Déjà importée'),
  enDouble('En double dans le fichier'),
  refusee('Refusée');

  const StatutImport(this.libelle);

  final String libelle;
}

/// Filtre de l'aperçu, état de l'écran.
enum _Filtre {
  toutes('Toutes'),
  pretes('Prêtes'),
  incompletes('Incomplètes'),
  deja('Déjà importées ou en double'),
  refusees('Refusées');

  const _Filtre(this.libelle);

  final String libelle;

  bool garde(StatutImport s) => switch (this) {
    _Filtre.toutes => true,
    _Filtre.pretes => s == StatutImport.prete,
    _Filtre.incompletes => s == StatutImport.incomplete,
    _Filtre.deja =>
      s == StatutImport.dejaImportee || s == StatutImport.enDouble,
    _Filtre.refusees => s == StatutImport.refusee,
  };
}

/// Statut d'une recette de l'aperçu et ses valeurs à compléter.
typedef StatutLu = ({StatutImport statut, List<String> aCompleter});

/// Statut de [r] et ses valeurs à compléter, avec l'équipement [equipement]
/// choisi dans l'aperçu : « Prête » quand rien ne manque ni au calcul ni à
/// l'export BeerJSON. [ownerName] : auteur retenu à l'export à défaut de
/// `recipe.author` (l'importateur est le propriétaire).
StatutLu statutImport(
  RecetteAImporter r,
  EquipementRecette equipement, {
  required String? ownerName,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  final content = r.content;
  final resultat = r.source.resultat;
  if (content == null || resultat is! RecetteLue) {
    return (statut: StatutImport.refusee, aCompleter: const []);
  }
  final export = manquesExportBeerJson(
    recipe: resultat.recipe,
    auteur: content.author ?? ownerName,
    rendementEmpatage: equipement.efficiency,
  );
  final calculs = evaluerRecette(
    content,
    equipement,
    errors: errors,
    reported: reported,
    recipeKey: 'import:${r.source.empreinte}',
  );
  final couverts = {
    for (final m in export)
      if (m is ManqueDeCalcul) m.manque.kind,
  };
  final labels = <String>{
    for (final m in export) libelleManqueExport(m, equipement),
    if (calculs case CalculsObtenus(:final calculation))
      for (final m in calculation.missingInputs)
        if (!couverts.contains(m.kind)) libelleManque(m, equipement),
    if (calculs case CalculsImpossibles(:final field))
      messageCalculImpossible(field),
  };
  final StatutImport statut;
  if (r.source.enDouble) {
    statut = StatutImport.enDouble;
  } else if (r.dejaImportee) {
    statut = StatutImport.dejaImportee;
  } else {
    statut = labels.isEmpty ? StatutImport.prete : StatutImport.incomplete;
  }
  return (statut: statut, aCompleter: labels.toList());
}

/// Étape de l'écran.
sealed class _Etape {
  const _Etape();
}

class _Accueil extends _Etape {
  const _Accueil({this.erreur, this.reessayer = false});

  /// Message d'un fichier refusé, ou `null`.
  final String? erreur;

  /// « Réessayer » après une ouverture impossible.
  final bool reessayer;
}

class _Lecture extends _Etape {
  const _Lecture();
}

class _Apercu extends _Etape {
  const _Apercu(this.lu, this.recettes);

  final FichierLu lu;
  final List<RecetteAImporter> recettes;
}

class _Ecriture extends _Etape {
  const _Ecriture(this.faites, this.total);

  final int faites;
  final int total;
}

class _Termine extends _Etape {
  const _Termine();
}

/// Recette créée par l'import, suivie jusqu'à la réponse du serveur.
class _Creee {
  _Creee(this.id, this.nom);

  final String id;
  final String nom;
  bool confirmee = false;
  bool refusee = false;

  /// Refus déjà montré par le compte rendu : le message groupé ne le répète pas.
  bool annonce = false;
}

/// Suivi des écritures, qui survit à la fermeture de l'écran : un refus arrivé
/// après la sortie s'annonce en un seul message groupé (décision 9).
class _Suivi {
  _Suivi(this.messenger);

  final ScaffoldMessengerState messenger;
  final creees = <_Creee>[];
  bool ecranFerme = false;
  VoidCallback? surChangement;

  /// Refus reçu pendant que le compte rendu est affiché.
  void Function(String nom)? surRefus;

  void suivre(_Creee c, Future<void> written) {
    creees.add(c);
    unawaited(
      written.then(
        (_) => _fin(c, refus: false),
        // Déjà rapportée par le dépôt de données (`_guard`).
        onError: (Object _) => _fin(c, refus: true),
      ),
    );
  }

  /// L'écran est quitté ou passe à un autre fichier.
  void fermer() {
    ecranFerme = true;
    surChangement = null;
    surRefus = null;
    _annoncerGroupe();
  }

  void _fin(_Creee c, {required bool refus}) {
    c.confirmee = !refus;
    c.refusee = refus;
    if (refus && !ecranFerme) {
      c.annonce = true;
      surRefus?.call(c.nom);
    }
    surChangement?.call();
    _annoncerGroupe();
  }

  void _annoncerGroupe() {
    if (!ecranFerme || creees.any((x) => !x.confirmee && !x.refusee)) return;
    final refusees = [
      for (final x in creees)
        if (x.refusee && !x.annonce) x,
    ];
    if (refusees.isEmpty) return;
    for (final x in refusees) {
      x.annonce = true;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(
          TextesImport.refusGroupe([for (final x in refusees) x.nom]),
        ),
      ),
    );
  }
}

/// Recettes › Importer : choix d'un fichier BeerJSON, aperçu sans écriture,
/// écriture d'une recette à la fois sous le compte de l'importateur, compte
/// rendu (ADR-005, L2). Rien n'est lu depuis le réseau ni depuis un asset (P12).
class ImportRecipesScreen extends ConsumerStatefulWidget {
  const ImportRecipesScreen({super.key});

  @override
  ConsumerState<ImportRecipesScreen> createState() =>
      _ImportRecipesScreenState();
}

class _ImportRecipesScreenState extends ConsumerState<ImportRecipesScreen> {
  _Etape _etape = const _Accueil();
  final _coches = <int>{};
  String? _equipmentId;
  bool _equipmentTouched = false;
  _Filtre _filtre = _Filtre.toutes;
  _Suivi? _suivi;
  var _ignorees = <({String nom, String raison})>[];
  bool _horsLigneALaFin = false;

  /// Statuts de l'aperçu par équipement : un appui sur une case ne les
  /// recalcule pas (500 recettes au plus).
  final _statuts = <String, List<StatutLu>>{};

  @override
  void dispose() {
    _suivi?.fermer();
    super.dispose();
  }

  void _retour() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.recipes);

  /// Choix en cours sur Android : les boutons de choix ne répondent pas, le
  /// canal refuserait un second appel (`ALREADY_ACTIVE`). Sur le web, un
  /// nouveau choix clôt le précédent (l'événement `cancel` n'est pas toujours
  /// émis) : ils restent actifs.
  bool _choixEnCours = false;

  /// Nom du jeton de l'importateur, celui qu'écrit l'import : lu une fois,
  /// avant le premier aperçu, pour le statut « Prête ».
  String? _nomJeton;
  bool _nomJetonLu = false;

  VoidCallback? get _surChoisir => _choixEnCours ? null : _choisir;

  Future<void> _choisir() async {
    if (_choixEnCours) return;
    if (!kIsWeb) setState(() => _choixEnCours = true);
    final resultat = await ref
        .read(echangeFichiersProvider)
        .choisir(maxOctets: kMaxOctetsParFichier);
    if (!mounted) return;
    setState(() => _choixEnCours = false);
    switch (resultat) {
      case ChoixAnnule():
        return;
      case FichierTropGros(:final taille):
        setState(
          () => _etape = _Accueil(
            erreur: libelleFichierRefuse(
              FichierRefuse(RaisonFichier.tropGros, taille: taille),
              '',
            ),
          ),
        );
      case ChoixImpossible():
        setState(
          () => _etape = const _Accueil(
            erreur: TextesImport.ouvertureImpossible,
            reessayer: true,
          ),
        );
      case FichierChoisi(:final nom, :final octets):
        setState(() => _etape = const _Lecture());
        // L'indicateur s'affiche avant l'analyse, qui occupe le fil.
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        if (!_nomJetonLu) {
          // 3 s au plus hors ligne (`kTokenNameWait`), une fois par écran.
          _nomJeton = await ref.read(authRepositoryProvider).currentTokenName();
          _nomJetonLu = true;
          if (!mounted) return;
        }
        _analyser(nom, octets);
    }
  }

  void _illisible(String nom, String context, StackTrace stackTrace) {
    // Ni nom ni contenu du fichier dans le rapport : le texte d'une exception
    // de décodage cite le fichier, il n'est pas transmis.
    ref
        .read(errorReportServiceProvider)
        .reportError(
          feature: 'exchange.read',
          error: 'fichier illisible',
          stackTrace: stackTrace,
          context: context,
        );
    setState(() => _etape = _Accueil(erreur: fichierIllisible(nom)));
  }

  void _analyser(String nom, List<int> octets) {
    final FichierLu lu;
    final List<RecetteAImporter> recettes;
    try {
      final analyse = ref.read(analyseurFichierProvider)(octets);
      if (analyse is! FichierLu) {
        setState(
          () => _etape = _Accueil(
            erreur: libelleFichierRefuse(analyse as FichierRefuse, nom),
          ),
        );
        return;
      }
      lu = analyse;
      final uid = ref.read(grantedAccessProvider)?.user.uid;
      final miennes = [
        for (final r
            in ref.read(recipesListProvider).value?.valides ?? const <Recipe>[])
          if (r.ownerUid == uid) r,
      ];
      recettes = preparerImport(
        lu,
        miennes: miennes,
        errors: ref.read(errorReportServiceProvider),
      );
    } on FormatException catch (error, stackTrace) {
      // JSON ou XML mal formé, ou UTF-8 invalide.
      _illisible(
        nom,
        'format ${formatPresume(octets)}, taille ${octets.length} octets, '
        'code illisible, position ${error.offset ?? 'inconnue'}',
        stackTrace,
      );
      return;
    } catch (error, stackTrace) {
      // Toute autre panne de l'analyse : le type de l'erreur seul.
      _illisible(
        nom,
        'taille ${octets.length} octets, erreur ${error.runtimeType}',
        stackTrace,
      );
      return;
    }
    setState(() {
      _coches
        ..clear()
        ..addAll([
          for (final (i, r) in recettes.indexed)
            if (r.cocheeParDefaut) i,
        ]);
      _statuts.clear();
      _filtre = _Filtre.toutes;
      _etape = _Apercu(lu, recettes);
    });
  }

  Future<void> _importer(
    List<RecetteAImporter> recettes,
    String? equipmentId,
  ) async {
    final access = ref.read(grantedAccessProvider);
    if (access == null || _coches.isEmpty || _etape is! _Apercu) return;
    final choisies = (_coches.toList()..sort());
    final total = choisies.length;
    _ignorees = [
      for (final (i, r) in recettes.indexed)
        if (!_coches.contains(i))
          (
            nom: r.nom,
            raison: r.refus != null
                ? TextesImport.refusee(libelleRefus(r.refus!))
                : TextesImport.nonCochee,
          ),
    ];
    final suivi = _Suivi(ScaffoldMessenger.of(context))
      ..surChangement = () {
        if (mounted) setState(() {});
      }
      ..surRefus = (nom) {
        if (mounted && _etape is _Termine) {
          _annoncer(TextesImport.refusServeur(nom));
        }
      };
    _suivi = suivi;
    _horsLigneALaFin = access.offline;
    setState(() => _etape = _Ecriture(0, total));
    _annoncer(TextesImport.enCours(0, total));
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final repository = ref.read(recipesRepositoryProvider);
    for (final (n, i) in choisies.indexed) {
      final r = recettes[i];
      final created = repository.create(
        content: avecEquipement(r.content!, equipmentId),
        ownerUid: access.user.uid,
        ownerName: ownerName,
      );
      suivi.suivre(_Creee(created.id, r.nom), created.written);
      setState(() => _etape = _Ecriture(n + 1, total));
      // Une écriture par recette ; l'écran affiche la progression entre deux.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
    setState(() => _etape = const _Termine());
    // Une annonce : la fin et le bilan, refus reçus pendant l'écriture compris.
    final refusees = suivi.creees.where((c) => c.refusee).length;
    _annoncer(
      '${TextesImport.termine}. '
      '${TextesImport.bilan(suivi.creees.length - refusees, _ignorees.length, refusees)}',
    );
  }

  void _annoncer(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      ),
    );
  }

  /// « Importer un autre fichier » : l'ancien suivi continue, et son refus
  /// éventuel s'annonce en un message groupé.
  void _recommencer() => setState(() {
    _suivi?.fermer();
    _suivi = null;
    _etape = const _Accueil();
  });

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    final recipesAsync = ref.watch(recipesListProvider);
    final equipmentAsync = ref.watch(equipmentListProvider);
    final etape = _etape;
    final ecriture = etape is _Ecriture;

    final Widget body;
    if (recipesAsync.value == null) {
      // La liste des recettes donne « Déjà importée » : elle est lue d'abord.
      body = recipesAsync.hasError
          ? EtatErreur(
              message: RecipesListScreen.loadError,
              retrying: recipesAsync.isLoading,
              retryingLabel: 'Lecture en cours',
              onRetry: () => ref.invalidate(recipesListProvider),
            )
          : const EtatChargement(label: 'Chargement des recettes');
    } else {
      body = switch (etape) {
        _Accueil() => _accueil(etape),
        _Lecture() => const EtatChargement(label: TextesImport.lecture),
        _Apercu() => _apercu(etape, access, equipmentAsync),
        _Ecriture(:final faites, :final total) => _progression(faites, total),
        _Termine() => _bilan(),
      };
    }

    return PopScope(
      canPop: !ecriture,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(TextesImport.titre),
          leading: BackButton(onPressed: ecriture ? null : _retour),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (access?.offline ?? false) const BandeauHorsLigne(),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  /// Colonne centrée, bornée par [kContentMaxWidth].
  Widget _centre(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
      child: child,
    ),
  );

  Widget _colonne(List<Widget> children) =>
      _centre(ListView(padding: const EdgeInsets.all(16), children: children));

  Widget _accueil(_Accueil etape) {
    final theme = Theme.of(context);
    final erreur = etape.erreur;
    final Widget bouton;
    if (etape.reessayer) {
      bouton = FilledButton(
        onPressed: _surChoisir,
        child: const Text('Réessayer'),
      );
    } else {
      bouton = FilledButton.icon(
        onPressed: _surChoisir,
        icon: const Icon(Icons.upload_file),
        label: Text(
          erreur == null ? TextesImport.choisir : TextesImport.choisirAutre,
        ),
      );
    }
    return _colonne([
      if (erreur != null)
        Semantics(
          liveRegion: true,
          child: Material(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                erreur,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        )
      else
        const Text(TextesImport.aide),
      const SizedBox(height: 24),
      Align(alignment: Alignment.centerLeft, child: bouton),
    ]);
  }

  List<StatutLu> _statutsPour(
    List<RecetteAImporter> recettes,
    String? equipmentId,
    EquipementRecette equipement,
    String? ownerName,
  ) {
    final cle =
        '$equipmentId|${equipement.runtimeType}|${equipement.efficiency}'
        '|$ownerName';
    return _statuts.putIfAbsent(cle, () {
      final errors = ref.read(errorReportServiceProvider);
      final reported = ref.read(calculationReportsProvider);
      return [
        for (final r in recettes)
          statutImport(
            r,
            equipement,
            ownerName: ownerName,
            errors: errors,
            reported: reported,
          ),
      ];
    });
  }

  Widget _apercu(
    _Apercu etape,
    AccessGranted? access,
    AsyncValue<ListeLue<Equipment>> equipmentAsync,
  ) {
    final theme = Theme.of(context);
    final readerUid = access?.user.uid;
    final equipment = (equipmentAsync.value?.valides ?? <Equipment>[])
      ..sort(compareEquipment(readerUid));
    final mine = [
      for (final e in equipment)
        if (e.ownerUid == readerUid) e,
    ];
    final preselection = mine.length == 1 ? mine.single.id : null;
    final equipmentId = _equipmentTouched ? _equipmentId : preselection;
    final equipement = equipementDe(
      equipmentId,
      equipmentAsync,
      offline: access?.offline ?? false,
    );
    final recettes = etape.recettes;
    final statuts = _statutsPour(recettes, equipmentId, equipement, _nomJeton);
    int compte(StatutImport s) => statuts.where((x) => x.statut == s).length;
    int compteFiltre(_Filtre f) =>
        statuts.where((x) => f.garde(x.statut)).length;
    final cochables = [
      for (final (i, r) in recettes.indexed)
        if (!r.refusee) i,
    ];
    final visibles = [
      for (final (i, s) in statuts.indexed)
        if (_filtre.garde(s.statut)) i,
    ];
    final visiblesCochables = [
      for (final i in visibles)
        if (!recettes[i].refusee) i,
    ];
    final nbCoches = visiblesCochables.where(_coches.contains).length;
    final bool? toutCoche = visiblesCochables.isEmpty || nbCoches == 0
        ? false
        : nbCoches == visiblesCochables.length
        ? true
        : null;
    final resume = TextesImport.resume(
      pretes: compte(StatutImport.prete),
      incompletes: compte(StatutImport.incomplete),
      refusees: compte(StatutImport.refusee),
      deja: compte(StatutImport.dejaImportee),
      enDouble: compte(StatutImport.enDouble),
    );

    final entete = <Widget>[
      if (etape.lu.tronque) ...[
        Semantics(liveRegion: true, child: const Text(TextesImport.tronque)),
        const SizedBox(height: 8),
      ],
      MergeSemantics(child: Text(resume, style: theme.textTheme.titleMedium)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _surChoisir,
          icon: const Icon(Icons.upload_file),
          label: const Text(TextesImport.choisirAutre),
        ),
      ),
      const Text(TextesImport.sansPrix),
      if (cochables.isEmpty) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            TextesImport.aucuneAImporter,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ] else ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          // Clé de la seule présélection : un choix garde le menu et son focus.
          key: ValueKey('equipement-import-$preselection'),
          initialValue: equipmentId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: TextesImport.equipement,
            helperText: TextesImport.equipementAide,
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Aucun équipement'),
            ),
            for (final e in equipment)
              DropdownMenuItem(
                value: e.id,
                child: Text(
                  e.ownerUid == readerUid
                      ? e.name
                      : '${e.name} (${libelleAuteur(ownerUid: e.ownerUid, ownerName: e.ownerName, readerUid: readerUid)})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() {
            _equipmentId = id;
            _equipmentTouched = true;
          }),
        ),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in _Filtre.values)
            ChoiceChip(
              label: Text('${f.libelle} (${compteFiltre(f)})'),
              selected: _filtre == f,
              onSelected: (_) => setState(() => _filtre = f),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (visibles.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(TextesImport.aucunePourFiltre),
        ),
      if (visiblesCochables.isNotEmpty)
        CheckboxListTile(
          tristate: true,
          value: toutCoche,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            _filtre == _Filtre.toutes
                ? TextesImport.toutes(visiblesCochables.length)
                : TextesImport.toutesAffichees(visiblesCochables.length),
          ),
          onChanged: (_) => setState(() {
            if (toutCoche == true) {
              _coches.removeAll(visiblesCochables);
            } else {
              _coches.addAll(visiblesCochables);
            }
          }),
        ),
    ];

    // Une ligne construite à l'écran seulement : 500 recettes au plus.
    final liste = _centre(
      ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: entete.length + visibles.length,
        itemBuilder: (context, n) {
          if (n < entete.length) return entete[n];
          final i = visibles[n - entete.length];
          return _LigneApercu(
            recette: recettes[i],
            statut: statuts[i].statut,
            aCompleter: statuts[i].aCompleter,
            cochee: _coches.contains(i),
            onChanged: (v) => setState(() {
              if (v) {
                _coches.add(i);
              } else {
                _coches.remove(i);
              }
            }),
          );
        },
      ),
    );

    if (cochables.isEmpty) return liste;
    final n = _coches.length;
    return Column(
      children: [
        Expanded(child: liste),
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: _centre(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (n == 0) ...[
                    Semantics(
                      liveRegion: true,
                      child: const Text(TextesImport.aucuneCochee),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: n == 0
                        ? null
                        : () => _importer(recettes, equipmentId),
                    child: Text(TextesImport.importer(n)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _progression(int faites, int total) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(TextesImport.enCours(faites, total)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: total == 0 ? null : faites / total,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bilan() {
    final theme = Theme.of(context);
    final suivi = _suivi;
    final creees = suivi?.creees ?? const <_Creee>[];
    final refusees = [
      for (final c in creees)
        if (c.refusee) c,
    ];
    final acceptees = [
      for (final c in creees)
        if (!c.refusee) c,
    ];
    return _colonne([
      // Annoncé une fois, par `_annoncer` à la fin des écritures.
      Semantics(
        header: true,
        child: Text(TextesImport.termine, style: theme.textTheme.headlineSmall),
      ),
      const SizedBox(height: 8),
      MergeSemantics(
        child: Text(
          TextesImport.bilan(
            acceptees.length,
            _ignorees.length,
            refusees.length,
          ),
          style: theme.textTheme.titleMedium,
        ),
      ),
      if (_horsLigneALaFin && acceptees.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(TextesImport.horsLigne(acceptees.length)),
      ],
      if (acceptees.isNotEmpty) ...[
        const TitreSection('Créées'),
        for (final c in acceptees)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.nom),
            subtitle: c.confirmee
                ? null
                : const Align(
                    alignment: Alignment.centerLeft,
                    child: Etiquette(label: TextesImport.enAttente),
                  ),
            trailing: const Icon(Icons.chevron_right),
            // `push` : le retour ramène au compte rendu.
            onTap: () => context.push(AppRoutes.recipe(c.id)),
          ),
      ],
      if (_ignorees.isNotEmpty) ...[
        const TitreSection('Ignorées'),
        for (final i in _ignorees)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(TextesImport.ignoree(i.nom, i.raison)),
          ),
      ],
      if (refusees.isNotEmpty) ...[
        const TitreSection('En erreur'),
        for (final c in refusees)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(TextesImport.refusServeur(c.nom)),
          ),
      ],
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: () => context.go(AppRoutes.recipes),
            child: const Text(TextesImport.revenir),
          ),
          OutlinedButton(
            onPressed: _recommencer,
            child: const Text(TextesImport.autreFichier),
          ),
        ],
      ),
    ]);
  }
}

/// Une recette de l'aperçu : case (sauf refusée), nom, « style · volume ·
/// statut », et « Détails (n) » dépliable.
class _LigneApercu extends StatelessWidget {
  const _LigneApercu({
    required this.recette,
    required this.statut,
    required this.aCompleter,
    required this.cochee,
    required this.onChanged,
  });

  final RecetteAImporter recette;
  final StatutImport statut;
  final List<String> aCompleter;
  final bool cochee;
  final ValueChanged<bool> onChanged;

  String _statut() => switch (statut) {
    StatutImport.dejaImportee when recette.importeeLe != null =>
      'Déjà importée le ${formatDateCourte(recette.importeeLe!)}',
    StatutImport.refusee => TextesImport.refusee(libelleRefus(recette.refus!)),
    _ => statut.libelle,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = recette.content;
    final volume = c?.batchVolumeL;
    final sousTitre = [
      ?c?.style,
      if (volume != null) formatLitres(volume),
      _statut(),
    ].join(' · ');
    final modifications = [
      for (final m in recette.modifications) libelleModification(m),
    ];
    final n = aCompleter.length + modifications.length;
    final titre = Text(recette.nom);
    final sous = Text(
      sousTitre,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: statut == StatutImport.refusee
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recette.refusee)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block, color: theme.colorScheme.error),
            title: titre,
            subtitle: sous,
          )
        else
          CheckboxListTile(
            value: cochee,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: titre,
            subtitle: sous,
            onChanged: (v) => onChanged(v ?? false),
          ),
        if (n > 0)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              // Le lecteur d'écran nomme la recette : « Détails de IPA (3) ».
              title: Semantics(
                label: TextesImport.detailsDe(recette.nom, n),
                excludeSemantics: true,
                child: Text(TextesImport.details(n)),
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                if (aCompleter.isNotEmpty) ...[
                  const _Sous(TextesImport.aCompleter),
                  for (final l in aCompleter) _Puce(l),
                ],
                if (modifications.isNotEmpty) ...[
                  const _Sous(TextesImport.modifie),
                  for (final l in modifications) _Puce(l),
                ],
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _Sous extends StatelessWidget {
  const _Sous(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(texte, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _Puce extends StatelessWidget {
  const _Puce(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(child: Text('•  ')),
        Expanded(child: Text(texte)),
      ],
    ),
  );
}
