import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/presentation/page_secondaire.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/modele_processus.dart';
import '../domain/modeles_a_copier.dart';
import '../domain/preference_processus.dart';
import 'libelles_processus.dart';
import 'processes_providers.dart';

/// « Mes processus » (ADR-010) : les modèles du lecteur, puis ceux du groupe.
/// Page pleine hors de la coquille, ouverte depuis le menu du compte.
class ProcessListScreen extends ConsumerWidget {
  const ProcessListScreen({super.key});

  static const titre = 'Mes processus';
  static const chargement = 'Chargement des processus';
  static const lectureImpossible = 'Impossible de lire les processus.';
  static const horsLigne = 'Processus indisponibles hors ligne.';
  static const aucun =
      'Aucun processus. Un processus ajoute à vos brassins les étapes de '
      'préparation et de nettoyage, et les journées après le brassage.';
  static const modelesACopier = 'Modèles à copier';
  static const nouveau = 'Nouveau processus';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    final uid = access?.user.uid;
    final offline = access?.offline ?? false;
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final listAsync = ref.watch(processTemplatesProvider);
    final list = listAsync.value;
    final defaultId = uid == null
        ? null
        : idModeleParDefaut(ref.watch(processPreferenceProvider(uid)).value);
    void retry() => ref.invalidate(processTemplatesProvider);
    void create() => context.push(AppRoutes.newProcess);

    final mine = list == null
        ? const <ModeleProcessus>[]
        : _parNom([
            for (final m in list.valides)
              if (m.ownerUid == uid) m,
          ]);
    // Lu du cache seul et vide : rien ne prouve qu'il n'y a aucun processus.
    final sansCache = list != null && list.fromCache && list.documents.isEmpty;

    final Widget body;
    if (list == null) {
      body = listAsync.hasError
          ? EtatErreur(
              message: lectureImpossible,
              retrying: listAsync.isLoading,
              retryingLabel: 'Lecture en cours',
              onRetry: retry,
              secondaryAction: _CreationSansListe(onCreate: create),
            )
          : const EtatChargement(label: chargement);
    } else if (sansCache) {
      body = offline
          ? EtatVide(
              icon: Icons.cloud_off,
              message: horsLigne,
              action: _CreationSansListe(onCreate: create),
            )
          : const EtatChargement(label: chargement);
    } else {
      body = _Liste(
        list: list,
        mine: mine,
        readerUid: uid,
        defaultId: defaultId,
        compact: compact,
        stale: listAsync.hasError,
        retrying: listAsync.isLoading,
        onRetry: retry,
        onCreate: create,
      );
    }
    // Sans processus à soi, l'état vide porte le bouton de création.
    final canCreate = list != null && !sansCache && mine.isNotEmpty;

    return PageSecondaire(
      titre: titre,
      horsLigne: offline,
      body: body,
      floatingActionButton: compact && canCreate
          ? FloatingActionButton.extended(
              onPressed: create,
              icon: const Icon(Icons.add),
              label: const Text(nouveau),
            )
          : null,
    );
  }
}

List<ModeleProcessus> _parNom(List<ModeleProcessus> items) => items
  ..sort(
    (a, b) =>
        a.content.name.toLowerCase().compareTo(b.content.name.toLowerCase()),
  );

class _Liste extends StatelessWidget {
  const _Liste({
    required this.list,
    required this.mine,
    required this.readerUid,
    required this.defaultId,
    required this.compact,
    required this.stale,
    required this.retrying,
    required this.onRetry,
    required this.onCreate,
  });

  final ListeLue<ModeleProcessus> list;
  final List<ModeleProcessus> mine;
  final String? readerUid;
  final String? defaultId;
  final bool compact;
  final bool stale;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = _parNom([
      for (final m in list.valides)
        if (m.ownerUid != readerUid) m,
    ]);
    final invalid = list.documents
        .whereType<DocumentInvalide<ModeleProcessus>>();
    return ListView(
      padding: PageSecondaire.marges(
        context,
        EdgeInsets.only(top: 8, bottom: compact ? kMargeBoutonFlottant : 24),
      ),
      children: [
        if (stale) BandeauListePerimee(retrying: retrying, onRetry: onRetry),
        if (!compact && mine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text(ProcessListScreen.nouveau),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: TitreSection('Mes processus'),
        ),
        if (mine.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ProcessListScreen.aucun, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: onCreate,
                  child: const Text(ProcessListScreen.nouveau),
                ),
              ],
            ),
          ),
        for (final m in mine)
          _Ligne(modele: m, auteur: null, parDefaut: m.id == defaultId),
        // Toujours affichée, hors ligne compris : les modèles sont dans
        // l'application, rien ne s'écrit avant « Enregistrer ».
        const _ModelesACopier(),
        if (group.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: TitreSection('Processus du groupe'),
          ),
          for (final m in group)
            _Ligne(
              modele: m,
              auteur: libelleAuteur(
                ownerUid: m.ownerUid,
                ownerName: m.ownerName,
                readerUid: readerUid,
              ),
              parDefaut: false,
            ),
        ],
        for (final d in invalid)
          LigneListe(
            icone: Icons.error_outline,
            erreur: true,
            titre: 'Processus illisible',
            details: const [Text(kDetailLigneIllisible)],
            onTap: () => context.push(AppRoutes.process(d.id)),
          ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.modele,
    required this.auteur,
    required this.parDefaut,
  });

  final ModeleProcessus modele;

  /// Auteur d'un processus du groupe ; `null` pour les siens.
  final String? auteur;
  final bool parDefaut;

  @override
  Widget build(BuildContext context) {
    final c = modele.content;
    final a = auteur;
    // Un seul nœud qui porte l'action : le double appui du lecteur d'écran
    // ouvre la fiche.
    return LigneListe(
      icone: Icons.checklist_outlined,
      titre: c.name,
      details: [Text(resumeModele(c)), if (a != null) Text(a)],
      etiquettes: [
        if (parDefaut) const Etiquette(label: 'Par défaut'),
        if (modele.hasPendingWrites)
          const Etiquette(label: 'En attente du réseau'),
      ],
      semanticsLabel: [
        c.name,
        formatJournees(c.journees.length),
        if (a != null) 'de $a',
        if (parDefaut) 'par défaut',
        if (modele.hasPendingWrites) 'en attente du réseau',
      ].join(', '),
      onTap: () => context.push(AppRoutes.process(modele.id)),
    );
  }
}

/// Section « Modèles à copier » : son titre et une ligne par modèle.
class _ModelesACopier extends StatelessWidget {
  const _ModelesACopier();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: TitreSection(ProcessListScreen.modelesACopier),
      ),
      for (final m in ModeleACopier.values) _LigneModeleACopier(modele: m),
    ],
  );
}

/// Ligne de « Modèles à copier » : l'appui ouvre « Nouveau processus »
/// prérempli, rien n'est écrit avant « Enregistrer ».
class _LigneModeleACopier extends StatelessWidget {
  const _LigneModeleACopier({required this.modele});

  final ModeleACopier modele;

  /// Libellé lu par le lecteur d'écran : « Modèle à copier : {nom}, 3 journées ».
  static String parle(ModeleACopier modele, ContenuModele contenu) =>
      'Modèle à copier : ${modele.nom}, '
      '${formatJournees(contenu.journees.length)}';

  @override
  Widget build(BuildContext context) {
    // Clés factices : la copie ne sert qu'au résumé ; l'éditeur crée les siennes.
    var n = 0;
    final contenu = modele.copie(() => 'apercu-${n++}');
    return LigneListe(
      icone: Icons.content_copy_outlined,
      titre: modele.nom,
      details: [Text(resumeModele(contenu)), Text(modele.note)],
      etiquettes: const [Etiquette(label: 'Modèle')],
      semanticsLabel: parle(modele, contenu),
      onTap: () => context.push(AppRoutes.newProcessFrom(modele.parametre)),
    );
  }
}

/// Sous un état qui remplace la liste (panne de lecture, hors ligne sans
/// copie) : « Nouveau processus » et « Modèles à copier », qui sont dans
/// l'application et ne dépendent pas de la lecture des processus.
class _CreationSansListe extends StatelessWidget {
  const _CreationSansListe({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(child: _BoutonNouveau(onPressed: onCreate)),
      const SizedBox(height: 16),
      const _ModelesACopier(),
    ],
  );
}

/// « Nouveau processus » en contour, sous un état qui remplace la liste : la
/// création ne dépend pas de la lecture des processus.
class _BoutonNouveau extends StatelessWidget {
  const _BoutonNouveau({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
    onPressed: onPressed,
    child: const Text(ProcessListScreen.nouveau),
  );
}
