import 'dart:async';

import 'package:exchange/exchange.dart';
import 'package:exchange/fiches.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/fichiers/echange_fichiers.dart';
import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/presentation/zone_capture.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../library/domain/referentiel.dart';
import '../../recipes/domain/import_recettes.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/libelles_echange.dart';
import '../../recipes/presentation/recipes_providers.dart';
import '../data/execution_import.dart';
import '../domain/fiches_a_importer.dart';
import 'libelles_import_fiches.dart';

/// Une fiche de l'aperçu : préparée, son état, ses rubriques.
class _Ligne {
  _Ligne(this.fiche, this.etat, this.refus, this.rubriques);

  final FicheAImporter fiche;
  final EtatFiche etat;
  final RefusImport? refus;
  final List<Rubrique> rubriques;

  String get nom =>
      fiche.fiche?.brassin.name ?? 'Fiche n° ${fiche.source.numero}';
  String get ficheId => fiche.source.ficheId ?? '';
}

/// Analyse d'un fichier : fiches, état du serveur, comptes.
class _Analyse {
  _Analyse(this.lignes, this.etat);

  final List<_Ligne> lignes;
  final EtatServeur etat;
}

sealed class _Etape {
  const _Etape();
}

class _Accueil extends _Etape {
  const _Accueil({this.erreur, this.reessayer = false});

  final String? erreur;
  final bool reessayer;
}

class _Lecture extends _Etape {
  const _Lecture(this.label);

  final String label;
}

class _Vide extends _Etape {
  const _Vide();
}

class _ErreurServeur extends _Etape {
  const _ErreurServeur(this.lu);

  final FichierFiches lu;
}

class _Apercu extends _Etape {
  const _Apercu(this.analyse);

  final _Analyse analyse;
}

class _Ecriture extends _Etape {
  const _Ecriture(this.progression);

  final ProgressionImport progression;
}

class _Termine extends _Etape {
  const _Termine(this.analyse, this.choisies, this.issues);

  final _Analyse analyse;
  final List<_Ligne> choisies;
  final List<IssueFiche> issues;
}

/// Admin › Import (v0.6) : choix du fichier préparé, analyse sans écriture,
/// écriture des fiches cochées sous le compte de l'administrateur, compte
/// rendu chiffré. Seul écran d'écriture de masse sur les données (CLAUDE.md).
/// Rien n'est lu depuis le réseau ni depuis un asset, hors Firestore (P12).
class ImportFichesScreen extends ConsumerStatefulWidget {
  const ImportFichesScreen({super.key});

  @override
  ConsumerState<ImportFichesScreen> createState() => _ImportFichesScreenState();
}

class _ImportFichesScreenState extends ConsumerState<ImportFichesScreen> {
  _Etape _etape = const _Accueil();
  final _coches = <int>{};
  bool _choixEnCours = false;
  bool _arret = false;
  Completer<void>? _horsLigne;
  final _titreBilan = FocusNode();

  @override
  void dispose() {
    _arret = true;
    _titreBilan.dispose();
    super.dispose();
  }

  bool get _ecriture => _etape is _Ecriture;

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
      case FichierTropGros():
        setState(
          () => _etape = const _Accueil(erreur: TextesImportFiches.tropGros),
        );
      case ChoixImpossible():
        setState(
          () => _etape = const _Accueil(
            erreur: TextesImport.ouvertureImpossible,
            reessayer: true,
          ),
        );
      case FichierChoisi(:final octets):
        setState(() => _etape = const _Lecture(TextesImportFiches.lecture));
        // L'indicateur s'affiche avant la lecture, qui occupe le fil.
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
        final lu = _lire(octets);
        if (lu != null) await _comparer(lu);
    }
  }

  /// Lecture du fichier, sans écriture ; `null` si le fichier est refusé.
  FichierFiches? _lire(List<int> octets) {
    final LectureFiches lecture;
    try {
      lecture = lireFichierFiches(
        octets,
        maintenant: ref.read(horlogeProvider)(),
      );
    } on FormatException catch (error, stackTrace) {
      // Le message cite le contenu du fichier : seul l'emplacement part.
      _refuser(
        'json illisible, taille ${octets.length} octets, '
        'position ${error.offset ?? 'inconnue'}',
        stackTrace,
      );
      return null;
    } catch (error, stackTrace) {
      _refuser(
        'taille ${octets.length} octets, erreur ${error.runtimeType}',
        stackTrace,
      );
      return null;
    }
    switch (lecture) {
      case FichierFichesRefuse(:final raison, :final ficheId):
        setState(
          () => _etape = _Accueil(
            erreur: switch (raison) {
              RaisonFichierFiches.tropGros => TextesImportFiches.tropGros,
              RaisonFichierFiches.pasUnFichierDeFiches =>
                TextesImportFiches.pasUnFichier,
              RaisonFichierFiches.versionInconnue =>
                TextesImportFiches.versionInconnue,
              RaisonFichierFiches.tropDeFiches =>
                TextesImportFiches.tropDeFiches,
              RaisonFichierFiches.identifiantEnDouble =>
                TextesImportFiches.identifiantEnDouble(ficheId ?? ''),
            },
          ),
        );
        return null;
      case final FichierFiches lu:
        if (lu.fiches.isEmpty) {
          setState(() => _etape = const _Vide());
          return null;
        }
        return lu;
    }
  }

  void _refuser(String context, StackTrace stackTrace) {
    ref
        .read(errorReportServiceProvider)
        .reportError(
          feature: 'import.fiches',
          error: 'fichier illisible',
          stackTrace: stackTrace,
          context: context,
        );
    setState(
      () => _etape = const _Accueil(erreur: TextesImportFiches.pasUnFichier),
    );
  }

  /// Index de la Bibliothèque et documents aux identifiants du fichier, lus
  /// sur le serveur (EC3). Un index absent du serveur laisse sa liste sans
  /// complément ; une panne arrête l'analyse.
  Future<void> _comparer(FichierFiches lu) async {
    final access = ref.read(grantedAccessProvider);
    if (access == null) {
      // Accès en cours de relecture : retour au choix, jamais un indicateur
      // sans fin (U8).
      setState(() => _etape = const _Accueil());
      return;
    }
    setState(() => _etape = const _Lecture(TextesImportFiches.comparaison));
    final uid = access.user.uid;
    final errors = ref.read(errorReportServiceProvider);
    final IndexImport index;
    final EtatServeur etat;
    try {
      index = await _lireIndex();
      final brutes = [
        for (final f in lu.fiches)
          if (f.resultat case FicheAcceptee(:final fiche)) fiche,
      ];
      etat = await ref
          .read(importFichesRepositoryProvider)
          .lireExistant(
            uid: uid,
            recipeIds: {for (final f in brutes) f.recipeDocId},
            brewIds: {for (final f in brutes) brewIdDeFiche(f.ficheId)},
          );
    } catch (error, stackTrace) {
      errors.reportError(
        feature: 'import.fiches',
        error: error,
        stackTrace: stackTrace,
        context: 'lecture du serveur, ${lu.fiches.length} fiches',
      );
      if (mounted) setState(() => _etape = _ErreurServeur(lu));
      return;
    }
    if (!mounted) return;
    final reported = ref.read(calculationReportsProvider);
    final fiches = preparerFiches(
      lu,
      uid: uid,
      index: index,
      errors: errors,
      reported: reported,
    );
    final miennes = [
      for (final r
          in ref.read(recipesListProvider).value?.valides ?? const <Recipe>[])
        if (r.ownerUid == uid) r,
    ];
    final lignes = <_Ligne>[];
    for (final f in fiches) {
      final (etat: etatFiche, :refus) = etatDe(f, etat, uid: uid);
      final recette = f.recette;
      final nomEnDouble =
          recette != null &&
          miennes.any(
            (r) =>
                r.id != f.fiche?.recipeDocId &&
                r.name.trim().toLowerCase() ==
                    recette.name.trim().toLowerCase(),
          );
      lignes.add(
        _Ligne(
          f,
          etatFiche,
          refus,
          rubriquesDe(
            f,
            nomEnDouble: nomEnDouble,
            errors: errors,
            reported: reported,
          ),
        ),
      );
    }
    setState(() {
      _coches
        ..clear()
        ..addAll([
          for (final (i, l) in lignes.indexed)
            if (cochable(l.etat)) i,
        ]);
      _etape = _Apercu(_Analyse(lignes, etat));
    });
  }

  Future<IndexImport> _lireIndex() async {
    final repository = ref.read(libraryRepositoryProvider);
    Future<IndexBibliotheque?> lire(NatureReferentiel nature) async =>
        switch (await repository.lireIndex(nature)) {
          DocumentTrouve(:final value) => indexBibliotheque(value),
          // Absent du serveur : Bibliothèque pas encore remplie.
          _ => null,
        };
    final lus = await Future.wait([
      lire(NatureReferentiel.fermentables),
      lire(NatureReferentiel.hops),
      lire(NatureReferentiel.miscs),
      lire(NatureReferentiel.cultures),
    ]);
    return IndexImport(
      malts: lus[0],
      houblons: lus[1],
      ajouts: lus[2],
      levures: lus[3],
    );
  }

  Future<void> _importer(_Analyse analyse) async {
    final access = ref.read(grantedAccessProvider);
    if (access == null || _coches.isEmpty) return;
    final choisies = [
      for (final i in _coches.toList()..sort()) analyse.lignes[i],
    ];
    final recettes = {
      for (final l in choisies)
        if (!analyse.etat.recettes.containsKey(l.fiche.fiche!.recipeDocId))
          l.fiche.fiche!.recipeDocId,
    };
    // ticket: aucun (confirmation)
    final ok = await confirmerAction(
      context,
      titre: TextesImportFiches.confirmationTitre(choisies.length),
      paragraphes: [
        TextesImportFiches.confirmation(choisies.length, recettes.length),
      ],
      libelle: 'Importer',
    );
    if (!ok || !mounted) return;
    final horsLigne = Completer<void>();
    _horsLigne = horsLigne;
    if (access.offline) horsLigne.complete();
    _arret = false;
    setState(
      () => _etape = _Ecriture((
        fiche: 1,
        fiches: choisies.length,
        nom: choisies.first.nom,
        ecritures: 0,
        total: 0,
      )),
    );
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    var annoncee = 0;
    final issues = await executerImport(
      fiches: [for (final l in choisies) l.fiche],
      etat: analyse.etat,
      uid: access.user.uid,
      ownerName: ownerName,
      depot: ref.read(importFichesRepositoryProvider),
      couts: ref.read(costsRepositoryProvider),
      errors: ref.read(errorReportServiceProvider),
      perteConnexion: horsLigne.future,
      arret: () => _arret,
      surProgression: (p) {
        if (!mounted) return;
        setState(() => _etape = _Ecriture(p));
        if (p.fiche != annoncee && p.nom.isNotEmpty) {
          annoncee = p.fiche;
          _annoncer(TextesImportFiches.progression(p.fiche, p.fiches, p.nom));
        }
      },
    );
    _horsLigne = null;
    if (!mounted) return;
    final termine = _Termine(analyse, choisies, issues);
    setState(() => _etape = termine);
    final (:creees, :ignorees, :erreurs) = _comptes(termine);
    _annoncer(
      TextesImportFiches.bilanParle(
        creees,
        ignorees,
        erreurs,
        arret: _arrete(termine),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titreBilan.requestFocus();
    });
  }

  ({int creees, int ignorees, int erreurs}) _comptes(_Termine t) {
    final creees = t.issues.whereType<FicheEcrite>().length;
    final erreurs = t.issues
        .where((i) => i is FicheEnErreur || i is FicheInterrompue)
        .length;
    return (
      creees: creees,
      ignorees: t.analyse.lignes.length - creees - erreurs,
      erreurs: erreurs,
    );
  }

  /// Vrai si une perte de connexion ou un accusé absent a arrêté l'import (U1).
  bool _arrete(_Termine t) => t.issues.any((i) => i is FicheInterrompue);

  void _annoncer(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      ),
    );
  }

  /// Vrai si rien ne s'écrit, ou si l'utilisateur arrête l'import : la fiche
  /// en cours s'arrête alors.
  Future<bool> _peutQuitter() async {
    if (!_ecriture) return true;
    // ticket: aucun (confirmation)
    final arreter = await confirmerAbandon(
      context,
      TextesImportFiches.arreterTexte,
      titre: TextesImportFiches.arreterTitre,
      continuer: TextesImportFiches.continuer,
      abandonner: TextesImportFiches.arreter,
    );
    if (arreter) _arret = true;
    return arreter;
  }

  Future<void> _quitter() async {
    if (!await _peutQuitter() || !mounted) return;
    _retour();
  }

  void _retour() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.admin);

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    final offline = access?.offline ?? false;
    // Écoute de la connexion pendant l'écriture : un accusé ne revient jamais
    // hors ligne (EC9).
    ref.listen<AccessGranted?>(grantedAccessProvider, (_, next) {
      final h = _horsLigne;
      if ((next?.offline ?? true) && h != null && !h.isCompleted) h.complete();
    });
    // La liste des recettes donne l'avertissement de nom en double.
    ref.watch(recipesListProvider);
    final etape = _etape;
    final body = switch (etape) {
      _Accueil() => _accueil(etape, offline),
      _Lecture(:final label) => EtatChargement(label: label),
      _Vide() => EtatVide(
        icon: Icons.inbox_outlined,
        message: TextesImportFiches.vide,
        action: _boutonChoisir(TextesImportFiches.choisirAutre, offline),
      ),
      _ErreurServeur(:final lu) => EtatErreur(
        message: TextesImportFiches.erreurServeur,
        onRetry: () => unawaited(_comparer(lu)),
      ),
      _Apercu(:final analyse) => _apercu(analyse, offline),
      _Ecriture(:final progression) => _progression(progression),
      _Termine() => _bilan(etape),
    };
    return PopScope(
      canPop: !_ecriture,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_quitter());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(TextesImportFiches.titre),
          leading: BackButton(onPressed: () => unawaited(_quitter())),
          actions: [
            // Pendant l'écriture : même confirmation que le retour.
            MenuCompte(avantDeQuitter: _ecriture ? _peutQuitter : null),
            const SizedBox(width: 8),
          ],
        ),
        body: ZoneCapture(
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                if (offline) const BandeauHorsLigne(),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centre(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
      child: child,
    ),
  );

  Widget _colonne(List<Widget> children) =>
      _centre(ListView(padding: const EdgeInsets.all(16), children: children));

  /// Bouton de choix, ou le message hors ligne à sa place (EC9).
  Widget _boutonChoisir(String libelle, bool offline, {bool plein = true}) {
    if (offline) return const Text(TextesImportFiches.horsLigne);
    final onPressed = _choixEnCours ? null : () => unawaited(_choisir());
    return plein
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.upload_file),
            label: Text(libelle),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.upload_file),
            label: Text(libelle),
          );
  }

  Widget _accueil(_Accueil etape, bool offline) {
    final theme = Theme.of(context);
    final erreur = etape.erreur;
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
        const Text(TextesImportFiches.aide),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerLeft,
        child: etape.reessayer && !offline
            ? FilledButton(
                onPressed: _choixEnCours ? null : () => unawaited(_choisir()),
                child: const Text(TextesImportFiches.reessayer),
              )
            : _boutonChoisir(
                erreur == null
                    ? TextesImportFiches.choisir
                    : TextesImportFiches.choisirAutre,
                offline,
              ),
      ),
    ]);
  }

  Widget _apercu(_Analyse analyse, bool offline) {
    final theme = Theme.of(context);
    final lignes = analyse.lignes;
    final lues = [
      for (final l in lignes)
        if (l.fiche.fiche != null && l.refus == null) l,
    ];
    final resume = TextesImportFiches.resume(
      fiches: lignes.length,
      recettes: {for (final l in lues) l.fiche.fiche!.recipeDocId}.length,
      brassins: lues.length,
      mesures: lues.fold(0, (n, l) => n + l.fiche.evenements.length),
      couts: lues.where((l) => l.fiche.cout is CoutCalcule).length,
    );
    final comptes = <EtatFiche, int>{};
    for (final l in lignes) {
      comptes[l.etat] = (comptes[l.etat] ?? 0) + 1;
    }
    final cochables = [
      for (final (i, l) in lignes.indexed)
        if (cochable(l.etat)) i,
    ];
    final entete = <Widget>[
      if (!offline) ...[
        _boutonChoisir(TextesImportFiches.choisirAutre, offline, plein: false),
        const SizedBox(height: 8),
      ],
      MergeSemantics(child: Text(resume, style: theme.textTheme.titleMedium)),
      const SizedBox(height: 4),
      Text(TextesImportFiches.comptes(comptes)),
      const SizedBox(height: 8),
    ];
    final liste = _centre(
      ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: entete.length + lignes.length,
        itemBuilder: (context, n) {
          if (n < entete.length) return entete[n];
          final i = n - entete.length;
          return _LigneFiche(
            ligne: lignes[i],
            cochee: _coches.contains(i),
            onChanged: cochable(lignes[i].etat)
                ? (v) => setState(() => v ? _coches.add(i) : _coches.remove(i))
                : null,
          );
        },
      ),
    );
    final n = _coches.length;
    final Widget barre;
    if (cochables.isEmpty) {
      barre = Semantics(
        liveRegion: true,
        child: Text(
          TextesImportFiches.rienAEcrire,
          style: theme.textTheme.titleSmall,
        ),
      );
    } else if (offline) {
      barre = const Text(TextesImportFiches.horsLigneImport);
    } else {
      barre = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n == 0) ...[
            Semantics(
              liveRegion: true,
              child: const Text(TextesImportFiches.aucuneCochee),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: n == 0 ? null : () => unawaited(_importer(analyse)),
            child: Text(TextesImportFiches.importer(n)),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: liste),
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: _centre(
            Padding(padding: const EdgeInsets.all(16), child: barre),
          ),
        ),
      ],
    );
  }

  Widget _progression(ProgressionImport p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(TextesImportFiches.progression(p.fiche, p.fiches, p.nom)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: p.total == 0 ? null : p.ecritures / p.total,
                semanticsLabel: p.total == 0
                    ? TextesImportFiches.enCours
                    : TextesImportFiches.ecritures(p.ecritures, p.total),
              ),
              if (p.total > 0) ...[
                const SizedBox(height: 8),
                ExcludeSemantics(
                  child: Text(
                    TextesImportFiches.ecritures(p.ecritures, p.total),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const FilledButton(
                onPressed: null,
                child: IndicateurBouton(label: TextesImportFiches.enCours),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bilan(_Termine t) {
    final theme = Theme.of(context);
    final (:creees, :ignorees, :erreurs) = _comptes(t);
    final aRevoir = <_Ligne>[];
    final enErreur = <String>[];
    final ignores = <String>[];
    int? interrompue;
    final choisies = {for (final l in t.choisies) l};
    for (final (i, l) in t.choisies.indexed) {
      switch (t.issues[i]) {
        case FicheEcrite():
          if (l.rubriques.isNotEmpty) aRevoir.add(l);
        case final FicheEnErreur e:
          enErreur.add(TextesImportFiches.erreur(l.nom, l.ficheId, e));
        case FicheInterrompue():
          interrompue ??= i + 1;
          enErreur.add(TextesImportFiches.interrompue(l.nom, l.ficheId));
        case FicheNonTraitee():
          ignores.add(
            TextesImport.ignoree(l.nom, TextesImportFiches.nonTraitee),
          );
      }
    }
    for (final l in t.analyse.lignes) {
      if (choisies.contains(l)) continue;
      ignores.add(
        TextesImport.ignoree(l.nom, switch (l.etat) {
          EtatFiche.refusee => TextesImport.refusee(
            l.refus == null ? '' : libelleRefusImport(l.refus!),
          ),
          EtatFiche.nouvelle || EtatFiche.aCompleter => TextesImport.nonCochee,
          final e => TextesImportFiches.etat(e),
        }),
      );
    }
    return _colonne([
      Focus(
        focusNode: _titreBilan,
        child: Semantics(
          header: true,
          child: Text(
            TextesImportFiches.bilan(
              creees,
              ignorees,
              erreurs,
              arret: _arrete(t),
            ),
            style: theme.textTheme.headlineSmall,
          ),
        ),
      ),
      if (interrompue != null) ...[
        const SizedBox(height: 8),
        Text(
          TextesImportFiches.connexionPerdue(interrompue, t.choisies.length),
        ),
      ],
      if (aRevoir.isNotEmpty) ...[
        const TitreSection(TextesImportFiches.aRevoir),
        for (final l in aRevoir)
          SectionRepliable(
            titre: '${l.nom} (${l.ficheId})',
            storageKey: 'bilan-${l.ficheId}',
            children: [_Rubriques(l.rubriques)],
          ),
      ],
      if (ignores.isNotEmpty) ...[
        const TitreSection(TextesImportFiches.ignorees),
        for (final i in ignores)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(i),
          ),
      ],
      if (enErreur.isNotEmpty) ...[
        const TitreSection(TextesImportFiches.enErreur),
        for (final e in enErreur)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(e),
          ),
      ],
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: () => context.go(AppRoutes.brews),
            child: const Text(TextesImportFiches.voirBrassins),
          ),
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.admin),
            child: const Text(TextesImportFiches.revenir),
          ),
        ],
      ),
    ]);
  }
}

/// Ligne d'une fiche : case, nom et date, identifiant, état, points à revoir,
/// détail dépliable.
class _LigneFiche extends StatelessWidget {
  const _LigneFiche({
    required this.ligne,
    required this.cochee,
    required this.onChanged,
  });

  final _Ligne ligne;
  final bool cochee;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fiche = ligne.fiche.fiche;
    final etat = ligne.etat;
    final refus = ligne.refus;
    final libelleEtat = etat == EtatFiche.refusee && refus != null
        ? TextesImport.refusee(libelleRefusImport(refus))
        : TextesImportFiches.etat(etat);
    final points = pointsARevoir(ligne.fiche, ligne.rubriques);
    final nombre = nombrePointsARevoir(ligne.fiche, ligne.rubriques);
    final titre = fiche == null
        ? ligne.nom
        : '${ligne.nom} · ${dateDeFiche(fiche)}';
    final explication = TextesImportFiches.explication(etat);
    final parle = [
      ligne.nom,
      if (fiche != null) dateDeFicheParlee(fiche),
      libelleEtat.toLowerCase(),
      if (nombre > 0) '$nombre point${nombre > 1 ? 's' : ''} à revoir',
      ?explication,
    ].join(', ');
    final sousTitre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ligne.ficheId.isNotEmpty)
          Text(ligne.ficheId, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Etiquette(
          label: libelleEtat,
          ton: switch (etat) {
            EtatFiche.nouvelle => TonEtiquette.primaire,
            EtatFiche.aCompleter => TonEtiquette.tertiaire,
            EtatFiche.dejaImportee => TonEtiquette.neutre,
            EtatFiche.contenuDifferent => TonEtiquette.neutre,
            EtatFiche.refusee => TonEtiquette.erreur,
          },
        ),
        if (explication != null) ...[
          const SizedBox(height: 4),
          Text(explication, style: theme.textTheme.bodySmall),
        ],
        if (points.isNotEmpty) ...[const SizedBox(height: 4), Text(points)],
      ],
    );
    final onChanged = this.onChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: parle,
          excludeSemantics: true,
          checked: onChanged == null ? null : cochee,
          enabled: onChanged != null,
          onTap: onChanged == null ? null : () => onChanged(!cochee),
          child: onChanged == null
              ? ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    etat == EtatFiche.refusee
                        ? Icons.block
                        : Icons.check_circle_outline,
                    color: etat == EtatFiche.refusee
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(titre),
                  subtitle: sousTitre,
                )
              : CheckboxListTile(
                  value: cochee,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(titre),
                  subtitle: sousTitre,
                  onChanged: (v) => onChanged(v ?? false),
                ),
        ),
        if (ligne.rubriques.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: SectionRepliable(
              titre: TextesImportFiches.detail,
              storageKey: 'detail-${ligne.fiche.source.numero}',
              children: [_Rubriques(ligne.rubriques)],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Rubriques du détail, dans l'ordre (EC5).
class _Rubriques extends StatelessWidget {
  const _Rubriques(this.rubriques);

  final List<Rubrique> rubriques;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rubriques) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(r.titre, style: theme.textTheme.titleSmall),
            ),
          ),
          for (final l in r.lignes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: Text('•  ')),
                  Expanded(child: Text(l)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
