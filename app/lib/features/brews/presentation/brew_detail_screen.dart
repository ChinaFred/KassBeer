import 'dart:async';

import 'package:brewing/brewing.dart' show fermentationDayNumber;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brew_day/presentation/chronologie_jour.dart';
import '../../brew_day/presentation/mesure_form.dart';
import '../../costs/data/figeage_embouteillage.dart';
import '../../costs/presentation/bloc_cout_brassin.dart';
import '../../costs/presentation/costs_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/contenu_recette.dart';
import '../../recipes/presentation/recipe_calculations_view.dart';
import '../../recipes/presentation/recipes_providers.dart';
import '../data/brews_repository.dart';
import '../domain/brew.dart';
import '../domain/brew_event.dart';
import '../domain/releves.dart';
import 'brews_providers.dart';
import 'embouteillage.dart';
import 'prevu_et_mesure.dart';
import 'releve_fermentation.dart';

/// Fiche d'un brassin : copie figée, calculs, chronologie et saisies.
class BrewDetailScreen extends ConsumerStatefulWidget {
  const BrewDetailScreen({super.key, required this.id});

  final String id;

  static String deleteTitle(String name) => 'Supprimer « $name » ?';
  static const deleteMessage =
      'Le brassin, ses étapes et ses mesures disparaissent pour tout le groupe.';
  static const deleted = 'Brassin supprimé.';
  static const deleteOffline =
      'Suppression impossible hors ligne : ce brassin a des saisies.';
  static String deleteRejected(String name) =>
      'La suppression de « $name » a échoué.';
  static const saved = 'Brassin enregistré.';
  static String abandonTitre(String name) => 'Abandonner « $name » ?';
  static const abandonMessage =
      'Le brassin reste visible du groupe, avec ses mesures. Vous pourrez le reprendre.';
  static String revenirTitre(BrewStatus statut) =>
      'Revenir à « ${statut.label} » ?';
  static const revenirMessage = 'Les mesures et l\'embouteillage sont gardés.';
  static const revenirEnCours =
      'L\'écran du jour s\'ouvrira de nouveau par Reprendre le brassage.';
  static const voirLeCout = 'Voir le coût';
  static const coutFige = 'Coût figé.';
  static const coutNonFige = 'Coût non figé.';
  static const embouteillageEnregistre =
      'Embouteillage enregistré. Brassin en conditionnement.';
  static const embouteillageHorsLigne =
      'Embouteillage enregistré sur l\'appareil. Il partira au retour du réseau.';
  static String recipeChanged(DateTime date) =>
      'La recette a changé depuis la création de ce brassin. Il garde la '
      'version du ${formatDateCourte(date)}.';

  @override
  ConsumerState<BrewDetailScreen> createState() => _BrewDetailScreenState();
}

class _BrewDetailScreenState extends ConsumerState<BrewDetailScreen> {
  /// Lu une fois au premier affichage pour le propriétaire (3 s au plus), réutilisé
  /// ensuite : aucune action ne relit le jeton (règle owner_name), comme sur l'écran
  /// du jour. Reste nul pour un autre membre : aucun rapport `auth.token_name`.
  Future<String?>? _tokenName;

  /// Vrai pendant une action : un second appui est ignoré.
  bool _actionEnCours = false;

  /// Défilement de la fiche, titre et focus du bloc Coût : « Voir le coût ».
  final _scroll = ScrollController();
  final _coutKey = GlobalKey();
  // Cible de « Voir le coût » seulement : hors du parcours de tabulation.
  final _coutFocus = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _scroll.dispose();
    _coutFocus.dispose();
    super.dispose();
  }

  /// Fait défiler la fiche jusqu'au bloc Coût et y place le focus. La liste ne
  /// construit que ce qui est près de l'écran : elle avance d'un écran à la fois
  /// jusqu'à ce que le bloc existe.
  Future<void> _voirLeCout() async {
    for (var i = 0; i < 50 && _coutKey.currentContext == null; i++) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) break;
      _scroll.jumpTo(
        (position.pixels + position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    final target = _coutKey.currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 250),
      alignment: 0.1,
    );
    if (mounted) _coutFocus.requestFocus();
  }

  Future<void> _uneAction(Future<void> Function() action) async {
    if (_actionEnCours) return;
    _actionEnCours = true;
    try {
      await action();
    } finally {
      _actionEnCours = false;
    }
  }

  void _suivre(Future<void> written, String libelle) => unawaited(
    written.catchError((Object _) {
      // Déjà rapportée par le dépôt de données.
      if (mounted) annoncerRefus(ScaffoldMessenger.of(context), libelle);
    }),
  );

  bool get _offline => ref.read(grantedAccessProvider)?.offline ?? false;

  Future<void> _delete(Brew brew, bool hasEvents) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_offline && hasEvents) {
      messenger.showSnackBar(
        const SnackBar(content: Text(BrewDetailScreen.deleteOffline)),
      );
      return;
    }
    final confirmed = await confirmerSuppression(
      context,
      titre: BrewDetailScreen.deleteTitle(brew.name),
      paragraphes: const [BrewDetailScreen.deleteMessage],
    );
    if (!confirmed || !mounted) return;
    final repo = ref.read(brewsRepositoryProvider);
    // BR7 : sans saisie, immédiat, même hors ligne ; avec saisies, réseau exigé.
    final written = hasEvents
        ? repo.deleteWithEvents(brew.id, ownerUid: brew.ownerUid)
        : repo.delete(brew.id, ownerUid: brew.ownerUid);
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: BrewDetailScreen.deleted,
      refus: BrewDetailScreen.deleteRejected(brew.name),
    );
    context.go(AppRoutes.brews);
  }

  void _edit(Brew brew) {
    unawaited(
      showFeuilleOuDialogue<void>(
        context: context,
        fermetureProtegee: true,
        builder: (_) => _FormulaireBrassin(brew: brew, tokenName: _tokenName!),
      ),
    );
  }

  Future<void> _recreate(Brew brew, Recipe recipe) async {
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await confirmerAction(
      context,
      titre: 'Recréer depuis la recette ?',
      paragraphes: const [
        'Ce brassin est remplacé par un nouveau, à partir de la recette '
            'actuelle. Sa version figée de la recette est perdue ; ses notes sont '
            'recopiées.',
      ],
      libelle: 'Recréer',
    );
    if (!confirmed || !mounted) return;
    final ownerName = await _tokenName!;
    if (!mounted) return;
    final repo = ref.read(brewsRepositoryProvider);
    final created = repo.create(
      recipe: recipe,
      equipment: brew.equipmentRead,
      name: brew.name,
      plannedFor: brew.plannedFor,
      ownerUid: access.user.uid,
      ownerName: ownerName,
      notes: brew.notes,
    );
    final removal = repo.delete(brew.id, ownerUid: brew.ownerUid);
    suivreEcriture(
      messenger: messenger,
      written: Future.wait([created.written, removal]),
      succes: 'Brassin recréé depuis la recette.',
      refus: 'La recréation de « ${brew.name} » a échoué.',
    );
    router.go(AppRoutes.brew(created.id));
  }

  /// Écrit un changement de statut et l'annonce.
  Future<void> _changerStatut({
    required Brew brew,
    required BrewStatus statut,
    required String annonce,
    BrewStatus? annulation,
  }) => _uneAction(
    () => _ecrireStatut(
      brew: brew,
      statut: statut,
      annonce: annonce,
      annulation: annulation,
    ),
  );

  Future<void> _ecrireStatut({
    required Brew brew,
    required BrewStatus statut,
    required String annonce,
    BrewStatus? annulation,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(brewsRepositoryProvider);
    final offline = _offline;
    final ownerName = await _tokenName!;
    final written = repo.setStatus(
      brewId: brew.id,
      status: statut,
      ownerName: ownerName,
    );
    final refus = 'L\'enregistrement de « ${brew.name} » a échoué.';
    final texte = offline
        ? 'Statut changé sur l\'appareil. Il partira au retour du réseau.'
        : annonce;
    if (annulation == null) {
      suivreEcriture(
        messenger: messenger,
        written: written,
        succes: texte,
        refus: refus,
      );
      return;
    }
    unawaited(
      written.catchError((Object _) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(refus)));
      }),
    );
    annoncerAvecAnnulation(
      messenger,
      texte,
      onAnnuler: () => suivreEcriture(
        messenger: messenger,
        written: repo.setStatus(
          brewId: brew.id,
          status: annulation,
          ownerName: ownerName,
        ),
        succes: 'Brassin revenu à ${annulation.label}.',
        refus: refus,
      ),
    );
  }

  Future<void> _revenir(Brew brew, BrewStatus statut) async {
    final confirmed = await confirmerAction(
      context,
      titre: BrewDetailScreen.revenirTitre(statut),
      paragraphes: [
        BrewDetailScreen.revenirMessage,
        if (statut == BrewStatus.brewing) BrewDetailScreen.revenirEnCours,
      ],
      libelle: 'Revenir',
    );
    if (!confirmed || !mounted) return;
    await _changerStatut(
      brew: brew,
      statut: statut,
      annonce: 'Brassin revenu à ${statut.label}.',
    );
  }

  Future<void> _abandonner(Brew brew) async {
    final confirmed = await confirmerAction(
      context,
      titre: BrewDetailScreen.abandonTitre(brew.name),
      paragraphes: const [BrewDetailScreen.abandonMessage],
      libelle: 'Abandonner',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _changerStatut(
      brew: brew,
      statut: BrewStatus.abandoned,
      annonce: 'Brassin abandonné.',
    );
  }

  void _embouteiller(Brew brew, {required bool modification}) {
    final messenger = ScaffoldMessenger.of(context);
    final events = ref.read(brewEventsProvider(brew.id)).value;
    unawaited(
      showFeuilleOuDialogue<void>(
        context: context,
        fermetureProtegee: true,
        builder: (_) => FormulaireEmbouteillage(
          brew: brew,
          modification: modification,
          fermentationMesuree: densiteDeFermentationMesuree([
            ...?events?.valides,
          ]),
          now: ref.read(horlogeProvider),
          onSubmit: (embouteillage, finalGravity) {
            unawaited(
              _enregistrerEmbouteillage(
                messenger: messenger,
                brew: brew,
                embouteillage: embouteillage,
                finalGravity: finalGravity,
                modification: modification,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Enregistre l'embouteillage et, au premier, fige le coût (CB3 à CB9). Prix,
  /// frais et coût lu sont ceux déjà chargés par la fiche, capturés avant
  /// l'attente du nom du jeton (CB5) : aucune lecture, aucune attente de plus.
  Future<void> _enregistrerEmbouteillage({
    required ScaffoldMessengerState messenger,
    required Brew brew,
    required Embouteillage embouteillage,
    required double? finalGravity,
    required bool modification,
  }) async {
    final brews = ref.read(brewsRepositoryProvider);
    final costs = ref.read(costsRepositoryProvider);
    final errors = ref.read(errorReportServiceProvider);
    final reported = ref.read(costReportsProvider);
    final horloge = ref.read(horlogeProvider);
    final uid = brew.ownerUid;
    final prices = ref.read(pricesProvider(uid)).value;
    final fees = ref.read(feesProvider(uid)).value;
    final coutLu = ref
        .read(brewCostProvider((uid: uid, brewId: brew.id)))
        .value;
    final offline = _offline;
    final ownerName = await _tokenName!;
    final envoi = enregistrerEmbouteillage(
      brews: brews,
      costs: costs,
      errors: errors,
      reported: reported,
      brew: brew,
      embouteillage: embouteillage,
      finalGravity: finalGravity,
      modification: modification,
      ownerName: ownerName,
      prices: prices,
      fees: fees,
      coutLu: coutLu,
      now: horloge(),
    );
    final refus = 'L\'enregistrement de « ${brew.name} » a échoué.';
    final cout = envoi.cout;
    if (cout is FigeageNonDemande) {
      suivreEcriture(
        messenger: messenger,
        written: envoi.embouteillage,
        succes: offline
            ? BrewDetailScreen.embouteillageHorsLigne
            : modification
            ? 'Embouteillage modifié.'
            : BrewDetailScreen.embouteillageEnregistre,
        refus: refus,
      );
      return;
    }
    // Aucun montant dans ces annonces (SE7).
    final debut = offline
        ? BrewDetailScreen.embouteillageHorsLigne
        : BrewDetailScreen.embouteillageEnregistre;
    final fige = cout is CoutFigeEnvoye;
    void voir() => unawaited(_voirLeCout());
    unawaited(
      envoi.embouteillage.catchError((Object _) {
        // Déjà rapportée par le dépôt de données.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(refus)));
      }),
    );
    if (cout is CoutFigeEnvoye) {
      unawaited(
        cout.written.catchError((Object _) {
          // Refus du seul coût (CB7), déjà rapporté `costs.freeze_rejected`.
          annoncerAvecAction(
            messenger,
            TextesCoutBrassin.figeRefuse,
            action: BrewDetailScreen.voirLeCout,
            onAction: voir,
          );
        }),
      );
    }
    annoncerAvecAction(
      messenger,
      '$debut ${fige ? BrewDetailScreen.coutFige : BrewDetailScreen.coutNonFige}',
      action: fige ? null : BrewDetailScreen.voirLeCout,
      onAction: fige ? null : voir,
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Brew>(
      async: ref.watch(brewsListProvider),
      id: widget.id,
      offline: access?.offline ?? false,
      textes: textesBrassin,
      onRetry: () => ref.invalidate(brewsListProvider),
      onBack: () => context.go(AppRoutes.brews),
      builder: (context, brew) => _fiche(context, brew, access?.user.uid),
    );
  }

  Widget _fiche(BuildContext context, Brew brew, String? readerUid) {
    final theme = Theme.of(context);
    final eventsAsync = ref.watch(brewEventsProvider(brew.id));
    final events = eventsAsync.value;
    final prepared = ref.watch(preparedBrewsProvider).contains(brew.id);
    final mine = brew.ownerUid == readerUid;
    if (mine) {
      _tokenName ??= ref.read(authRepositoryProvider).currentTokenName();
    }
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final content = brew.recipe;
    final equipement = EquipementConnu(brew.equipmentRead);
    final calculs = evaluerRecette(
      content,
      equipement,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(calculationReportsProvider),
      recipeKey: 'brew-${brew.id}',
    );
    final hopIbu = <int, double>{
      if (calculs case CalculsObtenus(:final calculation))
        for (final h in calculation.hopBitterness) h.hop.index: h.ibu,
    };
    final plan = evaluerPlan(
      brew: brew,
      events: [...?events?.valides],
      now: ref.read(horlogeProvider)(),
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(planReportsProvider),
    );

    final recipesList = ref.watch(recipesListProvider).value;
    final source = brew.recipeId == null
        ? null
        : switch (recipesList?.chercher(brew.recipeId!)) {
            DocumentTrouve<Recipe>(:final value) => value,
            _ => null,
          };
    final recipeChanged =
        brew.status == BrewStatus.planned &&
        source != null &&
        source.updatedAt != null &&
        brew.recipeUpdatedAt != null &&
        source.updatedAt != brew.recipeUpdatedAt;
    final noEvents = events != null && events.documents.isEmpty;

    // Prix, frais et coût figé du propriétaire, lus par la fiche : le bloc Coût
    // les affiche, l'embouteillage les capture (CB5). Rien pour un autre membre
    // (CB1).
    final Widget? cout = !mine
        ? null
        : BlocCoutBrassin(
            brew: brew,
            prices: ref.watch(pricesProvider(brew.ownerUid)),
            fees: ref.watch(feesProvider(brew.ownerUid)),
            cout: ref.watch(
              brewCostProvider((uid: brew.ownerUid, brewId: brew.id)),
            ),
            titreKey: _coutKey,
            titreFocus: _coutFocus,
            onModifierEmbouteillage:
                brew.status == BrewStatus.conditioning ||
                    brew.status == BrewStatus.done
                ? () => _embouteiller(brew, modification: true)
                : null,
          );

    final width = MediaQuery.sizeOf(context).width;
    final compact = width < kCompactMaxWidth;
    final primaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
    );
    final Widget? principal = !mine
        ? null
        : switch (brew.status) {
            BrewStatus.planned => FilledButton(
              style: primaryStyle,
              onPressed: () => context.go(AppRoutes.prepareBrew(brew.id)),
              child: const Text('Préparer le brassage'),
            ),
            BrewStatus.brewing => FilledButton(
              style: primaryStyle,
              onPressed: () => context.go(AppRoutes.brewDay(brew.id)),
              child: const Text('Reprendre le brassage'),
            ),
            BrewStatus.conditioning => FilledButton(
              style: primaryStyle,
              onPressed: () => unawaited(
                _changerStatut(
                  brew: brew,
                  statut: BrewStatus.done,
                  annonce: 'Brassin terminé.',
                  annulation: BrewStatus.conditioning,
                ),
              ),
              child: const Text('Marquer comme terminé'),
            ),
            BrewStatus.abandoned => OutlinedButton(
              style: outlinedStyle,
              onPressed: () => unawaited(
                _changerStatut(
                  brew: brew,
                  statut: brew.statutDeReprise,
                  annonce: 'Brassin repris : ${brew.statutDeReprise.label}.',
                ),
              ),
              child: const Text('Reprendre ce brassin'),
            ),
            _ => null,
          };
    final fermentationMine = mine && brew.status == BrewStatus.fermenting;
    void ajouterReleve() => ouvrirAjoutReleve(context, ref, brew);
    void embouteiller() => _embouteiller(brew, modification: false);
    final Widget? actionsFermentation = !fermentationMine
        ? null
        : compact
        ? OutlinedButton(
            style: outlinedStyle,
            onPressed: embouteiller,
            child: const Text('Embouteiller'),
          )
        : Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: primaryStyle,
                  onPressed: ajouterReleve,
                  child: const Text('Ajouter un relevé'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: outlinedStyle,
                  onPressed: embouteiller,
                  child: const Text('Embouteiller'),
                ),
              ),
            ],
          );
    final fab = fermentationMine && compact
        ? FloatingActionButton.extended(
            onPressed: ajouterReleve,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un relevé'),
          )
        : null;
    final apresBrassage = switch (brew.status) {
      BrewStatus.fermenting ||
      BrewStatus.conditioning ||
      BrewStatus.done ||
      BrewStatus.abandoned => true,
      BrewStatus.planned || BrewStatus.brewing => false,
    };

    final body = ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16, 16, 16, fab == null ? 32 : 96),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(brew.name, style: theme.textTheme.headlineSmall),
              ),
            ),
            if (mine && brew.status != BrewStatus.planned)
              _menuActions(brew, events == null || events.documents.isNotEmpty),
          ],
        ),
        Text(_ligneStatut(brew), style: muted),
        if (brew.recipeId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.recipe(brew.recipeId!)),
              child: Text('Recette : ${content.name} ›'),
            ),
          ),
        if (!mine)
          Text(
            'Brassin de ${libelleAuteur(ownerUid: brew.ownerUid, ownerName: brew.ownerName, readerUid: readerUid)}',
            style: muted,
          ),
        if (brew.hasPendingWrites) ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Etiquette(label: 'En attente du réseau'),
          ),
        ],
        if (recipeChanged) ...[
          const SizedBox(height: 8),
          Text(
            BrewDetailScreen.recipeChanged(
              brew.recipeUpdatedAt ?? brew.createdAt!,
            ),
          ),
          if (mine && noEvents)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => unawaited(_recreate(brew, source)),
                child: const Text('Recréer depuis la recette'),
              ),
            ),
        ],
        const SizedBox(height: 16),
        ?principal,
        if (actionsFermentation != null) ...[
          const SizedBox(height: 8),
          actionsFermentation,
        ],
        if (mine && brew.status == BrewStatus.planned) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(brew),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _delete(
                  brew,
                  events == null || events.documents.isNotEmpty,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
            ],
          ),
        ],
        // Connu seulement dans la session : rien à dire quand l'information manque.
        if (mine && brew.status == BrewStatus.planned && prepared)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Préparé sur cet appareil', style: muted),
          ),
        ..._blocs(
          brew: brew,
          mine: mine,
          compact: compact,
          apresBrassage: apresBrassage,
          eventsAsync: eventsAsync,
          calculs: calculs,
          cout: cout,
          chronologie: _chronologie(
            brew: brew,
            eventsAsync: eventsAsync,
            plan: plan,
            mine: mine,
          ),
          recette: [
            BlocCalculs(
              calculs: calculs,
              content: content,
              equipement: equipement,
            ),
            const SizedBox(height: 8),
            ContenuRecette(content: content, hopIbu: hopIbu),
          ],
          general: [
            const TitreSection('Général'),
            LigneFiche(
              label: 'Date prévue',
              value: brew.plannedFor == null
                  ? null
                  : formatDate(brew.plannedFor!),
            ),
            LigneFiche(
              label: 'Brassé le',
              value: brew.brewedAt == null
                  ? null
                  : formatDateCourte(brew.brewedAt!),
            ),
            LigneFiche(label: 'Équipement', value: brew.equipment.name),
          ],
          width: width,
        ),
      ],
    );
    return Scaffold(body: body, floatingActionButton: fab);
  }

  /// Bloc « Chronologie », lecture ou panne des saisies.
  Widget _chronologie({
    required Brew brew,
    required AsyncValue<ListeLue<BrewEvent>> eventsAsync,
    required PlanEvalue plan,
    required bool mine,
  }) {
    final probleme = brew.deroule.probleme;
    if (eventsAsync.value == null && eventsAsync.hasError) {
      return Row(
        children: [
          const Expanded(child: TexteAbsent('Impossible de lire les saisies.')),
          TextButton(
            onPressed: () => ref.invalidate(brewEventsProvider(brew.id)),
            child: const Text('Réessayer'),
          ),
        ],
      );
    }
    if (eventsAsync.value == null) {
      return const TexteAbsent('Chargement des saisies');
    }
    return switch (plan) {
      PlanImpossible() => const TexteAbsent(kCalculChronologieImpossible),
      PlanObtenu(:final plan) =>
        probleme != null
            ? TexteAbsent(messageChronologieIllisible(probleme))
            : plan.lignes.isEmpty && plan.mesuresSansEtape.isEmpty
            ? const TexteAbsent('Aucune étape.')
            : ChronologieJour(
                plan: plan,
                onTapSaisie: mine
                    ? (e) => ouvrirCorrection(
                        context: context,
                        ref: ref,
                        brew: brew,
                        event: e,
                        suivre: _suivre,
                      )
                    : null,
              ),
    };
  }

  /// Blocs du corps de la fiche, dans l'ordre de la proposition UX.
  List<Widget> _blocs({
    required Brew brew,
    required bool mine,
    required bool compact,
    required bool apresBrassage,
    required AsyncValue<ListeLue<BrewEvent>> eventsAsync,
    required CalculsRecette calculs,
    required Widget? cout,
    required Widget chronologie,
    required List<Widget> recette,
    required List<Widget> general,
    required double width,
  }) {
    final offline = _offline;
    final notes = brew.notes;
    final section = SectionReleve(
      brew: brew,
      eventsAsync: eventsAsync,
      mine: mine,
      offline: offline,
    );
    final comparaison = BlocPrevuEtMesure(
      brew: brew,
      eventsAsync: eventsAsync,
      mine: mine,
      offline: offline,
      calculs: calculs,
      tokenName: _tokenName,
      uneAction: _uneAction,
    );
    final embouteillage = SectionEmbouteillage(
      brew: brew,
      onModifier:
          mine &&
              (brew.status == BrewStatus.conditioning ||
                  brew.status == BrewStatus.done)
          ? () => _embouteiller(brew, modification: true)
          : null,
    );
    final notesTitre = <Widget>[
      if (notes != null) ...[
        const TitreSection('Notes'),
        Text(notes, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ];
    if (!apresBrassage) {
      final relevesExistent = relevesDe([
        ...?eventsAsync.value?.valides,
      ]).isNotEmpty;
      return [
        const TitreSection('Calculs'),
        ...recette.take(1),
        const TitreSection('Chronologie'),
        chronologie,
        if (relevesExistent) section,
        const TitreSection('Recette'),
        ...recette.skip(2),
        ...general,
        ?cout,
        ...notesTitre,
      ];
    }
    // Bloc Coût (propriétaire seul) : après l'embouteillage quand il existe,
    // sinon après la comparaison.
    final List<Widget> blocs = switch (brew.status) {
      BrewStatus.fermenting => [section, comparaison, ?cout, ...notesTitre],
      BrewStatus.conditioning => [
        comparaison,
        embouteillage,
        ?cout,
        section,
        ...notesTitre,
      ],
      BrewStatus.done => [
        comparaison,
        embouteillage,
        ?cout,
        ..._notesTermine(brew, mine),
        section,
      ],
      _ => [
        section,
        comparaison,
        if (brew.bottledAt != null) embouteillage,
        ?cout,
        ...notesTitre,
      ],
    };
    return [
      ...blocs,
      ...general,
      SectionRepliable(
        titre: 'Chronologie',
        storageKey: 'chronologie-${brew.id}',
        resume: formatEtapes(brew.deroule.lignes.length),
        children: [chronologie],
      ),
      SectionRepliable(
        titre: 'Recette et calculs prévus',
        storageKey: 'recette-${brew.id}',
        ouvert: width >= kExpandedMinWidth,
        children: recette,
      ),
    ];
  }

  /// Notes d'un brassin terminé : toujours affichées au propriétaire.
  List<Widget> _notesTermine(Brew brew, bool mine) {
    final notes = brew.notes;
    if (notes != null) {
      return [
        const TitreSection('Notes'),
        Text(notes, style: Theme.of(context).textTheme.bodyLarge),
      ];
    }
    if (!mine) return const [];
    return [
      const TitreSection('Notes'),
      const TexteAbsent('Aucune note. Ajoutez votre avis sur cette bière.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _edit(brew),
          child: const Text('Modifier les notes'),
        ),
      ),
    ];
  }

  /// Ligne de statut sous le nom.
  String _ligneStatut(Brew brew) {
    final brewed = brew.brewedAt;
    final bottled = brew.bottledAt;
    final now = ref.read(horlogeProvider)();
    return switch (brew.status) {
      BrewStatus.fermenting when brewed != null =>
        'En fermentation · J+${fermentationDayNumber(brewedAt: brewed, at: now)}',
      BrewStatus.conditioning when bottled != null =>
        'En conditionnement · Embouteillé le ${formatDateCourte(bottled)}',
      BrewStatus.done when bottled != null =>
        'Terminé · Embouteillé le ${formatDateCourte(bottled)}',
      _ => brew.status.label,
    };
  }

  Widget _menuActions(Brew brew, bool hasEvents) {
    final theme = Theme.of(context);
    final retour = switch (brew.status) {
      BrewStatus.fermenting => BrewStatus.brewing,
      BrewStatus.conditioning => BrewStatus.fermenting,
      BrewStatus.done => BrewStatus.conditioning,
      _ => null,
    };
    final peutAbandonner = switch (brew.status) {
      BrewStatus.brewing ||
      BrewStatus.fermenting ||
      BrewStatus.conditioning => true,
      _ => false,
    };
    return PopupMenuButton<VoidCallback>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Plus d\'actions',
      iconSize: 24,
      constraints: const BoxConstraints(minWidth: 180),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(value: () => _edit(brew), child: const Text('Modifier')),
        if (retour != null)
          PopupMenuItem(
            value: () => unawaited(_revenir(brew, retour)),
            child: Text('Revenir à ${retour.label}'),
          ),
        if (peutAbandonner)
          PopupMenuItem(
            value: () => unawaited(_abandonner(brew)),
            child: const Text('Abandonner ce brassin'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => unawaited(_delete(brew, hasEvents)),
          child: Text(
            'Supprimer',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

/// « Modifier » : nom, date prévue, notes. Réécrit `owner_name` (règle `ownerNameOk`).
class _FormulaireBrassin extends ConsumerStatefulWidget {
  const _FormulaireBrassin({required this.brew, required this.tokenName});

  final Brew brew;

  /// Nom du jeton, lu au premier affichage de la fiche.
  final Future<String?> tokenName;

  @override
  ConsumerState<_FormulaireBrassin> createState() => _FormulaireBrassinState();
}

class _FormulaireBrassinState extends ConsumerState<_FormulaireBrassin> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late DateTime? _plannedFor;
  bool _saving = false;
  String? _nameError;
  final _nameFocus = FocusNode();
  final _nameKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.brew.name);
    _notes = TextEditingController(text: widget.brew.notes ?? '');
    _plannedFor = widget.brew.plannedFor;
    _name.addListener(_changement);
    _notes.addListener(_changement);
  }

  void _changement() => setState(() {});

  /// Vrai si le formulaire diffère du brassin.
  bool get _modifie =>
      _name.text != widget.brew.name ||
      _notes.text != (widget.brew.notes ?? '') ||
      _plannedFor != widget.brew.plannedFor;

  Future<void> _quitter() async {
    final navigator = Navigator.of(context);
    if (!_modifie) {
      navigator.pop();
      return;
    }
    final abandon = await confirmerAbandon(
      context,
      'Les modifications de ce brassin ne seront pas enregistrées.',
    );
    if (abandon && mounted) navigator.pop();
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = ref.read(horlogeProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedFor ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _plannedFor = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Donnez un nom au brassin.');
      await montrerChamp(_nameKey.currentContext);
      if (mounted) _nameFocus.requestFocus();
      return;
    }
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final ownerName = await widget.tokenName;
    if (!mounted) return;
    final written = ref
        .read(brewsRepositoryProvider)
        .update(
          id: widget.brew.id,
          name: name,
          plannedFor: _plannedFor,
          notes: _notes.text,
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: BrewDetailScreen.saved,
      refus: 'L\'enregistrement de « $name » a échoué.',
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final planned = _plannedFor;
    return PopScope(
      canPop: !_modifie,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_quitter());
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Modifier le brassin',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: _nameKey,
            controller: _name,
            focusNode: _nameFocus,
            maxLength: kBrewNameMaxLength,
            decoration: InputDecoration(
              labelText: 'Nom du brassin',
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text(planned == null ? 'Aucune' : formatDate(planned)),
                ),
              ),
              if (planned != null)
                IconButton(
                  tooltip: 'Effacer la date',
                  onPressed: () => setState(() => _plannedFor = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notes,
            maxLength: kBrewNotesMaxLength,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Notes (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => unawaited(_quitter()),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const IndicateurBouton(label: 'Enregistrement')
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
