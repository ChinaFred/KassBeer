import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/presentation/zone_capture.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/modele_processus.dart';
import '../domain/preference_processus.dart';
import 'libelles_processus.dart';
import 'processes_providers.dart';

/// Textes des états de la fiche et de l'éditeur d'un processus.
const textesProcessus = TextesDocument(
  chargement: 'Chargement du processus',
  lectureImpossible: 'Impossible de lire les processus.',
  absent: 'Ce processus n\'existe pas ou a été supprimé.',
  horsLigne: 'Processus indisponible hors ligne.',
  illisible:
      'Processus illisible. Mettez l\'application à jour, ou prévenez '
      'l\'administrateur.',
  retour: 'Revenir à mes processus',
);

/// Fiche d'un processus : lecture pour tous, « Modifier », choix par défaut,
/// « Supprimer » et « Dupliquer » pour l'auteur, « Copier dans mes processus »
/// pour les autres membres.
class ProcessDetailScreen extends ConsumerStatefulWidget {
  const ProcessDetailScreen({super.key, required this.id});

  final String id;

  static const titre = 'Processus';
  static const copier = 'Copier dans mes processus';
  static const proposerParDefaut = 'Proposer par défaut dans Nouveau brassin';
  static const choixPersonnel = 'Ce choix ne concerne que vous.';
  static String deleteTitle(String name) => 'Supprimer « $name » ?';
  static const deleteGroup =
      'Le processus disparaît pour tout le groupe. Les brassins déjà créés '
      'gardent leur déroulé.';
  static const deleteDefault =
      'C\'est votre processus par défaut : Nouveau brassin proposera la '
      'chronologie de la recette seule.';
  static const deleted = 'Processus supprimé.';
  static const copied = 'Processus copié dans vos processus.';
  static const copiedOffline =
      'Processus copié sur l\'appareil. Il partira au retour du réseau.';
  static const duplicated = 'Processus dupliqué.';
  static const duplicatedOffline =
      'Processus dupliqué sur l\'appareil. Il partira au retour du réseau.';
  static const defaultRejected =
      'L\'enregistrement du choix par défaut a échoué.';
  static String defaultOn(String name) => '« $name » sera proposé par défaut.';
  static const defaultOff = 'Aucun processus proposé par défaut.';
  static const lectureDefaut = 'Lecture du choix par défaut';
  static const defaultUnreadable = 'Impossible de lire votre choix par défaut.';

  @override
  ConsumerState<ProcessDetailScreen> createState() =>
      _ProcessDetailScreenState();
}

class _ProcessDetailScreenState extends ConsumerState<ProcessDetailScreen> {
  bool _duplicating = false;

  String get id => widget.id;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    final offline = access?.offline ?? false;
    final listAsync = ref.watch(processTemplatesProvider);
    final found = listAsync.value?.chercher(id);
    final mine = found is DocumentTrouve<ModeleProcessus>
        ? found.value.ownerUid == access?.user.uid
        : false;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.processes),
        ),
        title: const Text(ProcessDetailScreen.titre),
        actions: [
          if (found is DocumentTrouve<ModeleProcessus> && mine)
            _duplicating
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: IndicateurBouton(label: 'Duplication'),
                    ),
                  )
                // ticket: /processus/:id/menu/actions
                : PopupMenuButton<void>(
                    tooltip: 'Plus d\'actions',
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        onTap: () => _dupliquer(found.value),
                        child: const Text('Dupliquer'),
                      ),
                    ],
                  ),
          const MenuCompte(),
          const SizedBox(width: 8),
        ],
      ),
      body: ZoneCapture(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offline) const BandeauHorsLigne(),
            Expanded(
              child: PageDocument<ModeleProcessus>(
                async: listAsync,
                id: id,
                offline: offline,
                textes: textesProcessus,
                onRetry: () => ref.invalidate(processTemplatesProvider),
                onBack: () => context.go(AppRoutes.processes),
                builder: (context, modele) =>
                    _Fiche(key: ValueKey(modele.id), modele: modele),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dupliquer(ModeleProcessus modele) async {
    if (_duplicating) return;
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _duplicating = true);
    // Nom du jeton, 3 s au plus : hors ligne, la copie part sans lui.
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final created = ref
        .read(processesRepositoryProvider)
        .duplicate(
          source: modele,
          ownerUid: access.user.uid,
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: created.written,
      succes: access.offline
          ? ProcessDetailScreen.duplicatedOffline
          : ProcessDetailScreen.duplicated,
      refus: 'La duplication de « ${modele.content.name} » a échoué.',
    );
    setState(() => _duplicating = false);
    context.go(AppRoutes.process(created.id));
  }
}

class _Fiche extends ConsumerStatefulWidget {
  const _Fiche({super.key, required this.modele});

  final ModeleProcessus modele;

  @override
  ConsumerState<_Fiche> createState() => _FicheState();
}

class _FicheState extends ConsumerState<_Fiche> {
  bool _copying = false;

  ModeleProcessus get _modele => widget.modele;

  Future<void> _copier() async {
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _copying = true);
    // Nom du jeton, 3 s au plus : hors ligne, la copie part sans lui.
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final created = ref
        .read(processesRepositoryProvider)
        .copy(source: _modele, ownerUid: access.user.uid, ownerName: ownerName);
    suivreEcriture(
      messenger: messenger,
      written: created.written,
      succes: access.offline
          ? ProcessDetailScreen.copiedOffline
          : ProcessDetailScreen.copied,
      refus: 'La copie de « ${_modele.content.name} » a échoué.',
    );
    setState(() => _copying = false);
    context.go(AppRoutes.process(created.id));
  }

  Future<void> _supprimer({required bool parDefaut}) async {
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final name = _modele.content.name;
    // ticket: aucun (confirmation)
    final confirmed = await confirmerSuppression(
      context,
      titre: ProcessDetailScreen.deleteTitle(name),
      paragraphes: [
        ProcessDetailScreen.deleteGroup,
        if (parDefaut) ProcessDetailScreen.deleteDefault,
      ],
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // L'écriture locale est faite à l'appel : la fiche se ferme sans attendre le
    // serveur. Aucun brassin n'est écrit.
    final write = ref.read(processesRepositoryProvider).delete(_modele.id);
    if (parDefaut) {
      // Le choix ne désigne plus un modèle supprimé : Nouveau brassin propose
      // la chronologie de la recette seule. Il n'est remis à nul qu'une fois la
      // suppression acceptée par le serveur : refusée, le défaut reste. Hors
      // ligne, il attend le retour du réseau ; si l'application se ferme
      // avant, le choix désigne un modèle supprimé, lu comme aucun défaut
      // (ADR-010).
      final preferences = ref.read(preferencesProcessusRepositoryProvider);
      final uid = access.user.uid;
      unawaited(
        write.then(
          (_) => preferences.saveDefault(uid: uid, templateId: null).catchError(
            (Object _) {
              // Déjà rapportée par le dépôt ; le refus s'affiche.
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(ProcessDetailScreen.defaultRejected),
                ),
              );
            },
          ),
          // Suppression refusée : déjà rapportée par le dépôt et annoncée
          // ci-dessous ; le choix par défaut ne change pas.
          onError: (Object _) {},
        ),
      );
    }
    suivreEcriture(
      messenger: messenger,
      written: write,
      succes: ProcessDetailScreen.deleted,
      refus: 'La suppression de « $name » a échoué.',
    );
    context.go(AppRoutes.processes);
  }

  void _choisirParDefaut(bool value) {
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final written = ref
        .read(preferencesProcessusRepositoryProvider)
        .saveDefault(
          uid: access.user.uid,
          templateId: value ? _modele.id : null,
        );
    suivreEcriture(
      messenger: ScaffoldMessenger.of(context),
      written: written,
      succes: value
          ? ProcessDetailScreen.defaultOn(_modele.content.name)
          : ProcessDetailScreen.defaultOff,
      refus: ProcessDetailScreen.defaultRejected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = ref.watch(grantedAccessProvider);
    final uid = access?.user.uid;
    final modele = _modele;
    final c = modele.content;
    final mine = modele.ownerUid == uid;
    final prefAsync = uid == null || !mine
        ? null
        : ref.watch(processPreferenceProvider(uid));
    final prefLue = prefAsync?.value;
    final prefEnPanne =
        prefAsync != null && prefLue == null && prefAsync.hasError;
    final parDefaut = idModeleParDefaut(prefLue) == modele.id;
    const bouton = Size(0, 56);
    final notes = c.notes;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Semantics(
              header: true,
              child: Text(c.name, style: theme.textTheme.headlineSmall),
            ),
            if (!mine) ...[
              const SizedBox(height: 4),
              Text(
                'Processus de ${libelleAuteur(ownerUid: modele.ownerUid, ownerName: modele.ownerName, readerUid: uid)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (modele.hasPendingWrites) ...[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Etiquette(label: 'En attente du réseau'),
              ),
            ],
            if (notes != null) ...[
              const SizedBox(height: 12),
              Text(notes, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 16),
            if (mine) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(ProcessDetailScreen.proposerParDefaut),
                subtitle: Text(
                  prefLue != null
                      ? ProcessDetailScreen.choixPersonnel
                      : prefEnPanne
                      ? ProcessDetailScreen.defaultUnreadable
                      : ProcessDetailScreen.lectureDefaut,
                ),
                value: parDefaut,
                onChanged: prefLue == null ? null : _choisirParDefaut,
              ),
              if (prefEnPanne)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: prefAsync.isLoading
                        ? null
                        : () => ref.invalidate(processPreferenceProvider(uid!)),
                    child: prefAsync.isLoading
                        ? const IndicateurBouton(label: 'Lecture en cours')
                        : const Text('Réessayer'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: bouton),
                    onPressed: () =>
                        context.push(AppRoutes.editProcess(modele.id)),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: bouton,
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => _supprimer(parDefaut: parDefaut),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: bouton),
                  onPressed: _copying ? null : _copier,
                  child: _copying
                      ? const IndicateurBouton(label: 'Copie')
                      : const Text(ProcessDetailScreen.copier),
                ),
              ),
            for (final (i, j) in c.journees.indexed) ...[
              TitreSection('${i + 1}. ${j.name} · J+${j.offsetDays}'),
              if (mentionCondition(j) case final mention?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    mention,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
              Text(
                resumeJournee(j),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final e in j.elements)
                e.estBloc ? _LigneBloc(nature: e.nature) : _LigneEtape(e),
            ],
          ],
        ),
      ),
    );
  }
}

class _LigneEtape extends StatelessWidget {
  const _LigneEtape(this.etape);

  final ElementModele etape;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        [etape.name!, ...detailsEtape(etape)].join(' · '),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _LigneBloc extends StatelessWidget {
  const _LigneBloc({required this.nature});

  final NatureElement nature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: blocParle(nature),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(iconeBloc, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nomBloc(nature),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
