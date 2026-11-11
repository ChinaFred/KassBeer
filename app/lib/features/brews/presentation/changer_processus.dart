import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../processes/presentation/processes_providers.dart';
import '../../recipes/domain/chronologie.dart';
import '../domain/assemblage_deroule.dart';
import '../domain/brew.dart';
import '../domain/deroule.dart';
import 'choix_processus.dart';
import 'libelles_deroule.dart';
import 'section_deroule.dart';

/// Feuille « Changer de processus » d'un brassin prévu (ADR-009) : les seuls
/// processus du lecteur et le déroulé prévu, puis « Appliquer », qui réécrit
/// `process` en entier depuis la recette figée du brassin. Réservée au
/// propriétaire tant que `brewed_at` est nul.
class FeuilleChangerProcessus extends ConsumerStatefulWidget {
  const FeuilleChangerProcessus({
    super.key,
    required this.brew,
    required this.tokenName,
  });

  final Brew brew;

  /// Nom du jeton, lu au premier affichage de la fiche.
  final Future<String?> tokenName;

  @override
  ConsumerState<FeuilleChangerProcessus> createState() =>
      _FeuilleChangerProcessusState();
}

class _FeuilleChangerProcessusState
    extends ConsumerState<FeuilleChangerProcessus> {
  String? _processId;
  bool _touched = false;
  String? _error;
  bool _saving = false;

  Brew get _brew => widget.brew;

  /// Valeur du déroulé actuel dans la liste : `null` sans processus, son modèle
  /// s'il est lu, sinon l'entrée « {nom} (actuel) » ([kProcessusActuel]). Le
  /// déroulé actuel ne se remplace jamais faute d'avoir lu la liste.
  String? _courant(ChoixProcessus choix) {
    final process = _brew.process;
    if (process == null) return null;
    return choix.valide(process.templateId) ?? kProcessusActuel;
  }

  /// Nom de l'entrée « {nom} (actuel) », ou `null` sans elle.
  String? _nomActuel(ChoixProcessus choix) {
    if (_courant(choix) != kProcessusActuel) return null;
    final process = _brew.process!;
    if (process.probleme != null) return 'Déroulé illisible';
    final name = process.templateName?.trim();
    return name == null || name.isEmpty ? 'Processus sans nom' : name;
  }

  /// Choix du brasseur s'il désigne encore une entrée de la liste, sinon le
  /// déroulé actuel.
  String? _selection(ChoixProcessus choix) {
    final courant = _courant(choix);
    if (!_touched) return courant;
    final id = _processId;
    if (id == null) return null;
    if (id == kProcessusActuel) {
      return courant == kProcessusActuel ? id : courant;
    }
    return choix.valide(id) ?? courant;
  }

  /// « Appliquer » n'écrit qu'un choix du brasseur différent du déroulé actuel :
  /// rien pendant la lecture, en panne ou hors ligne, sauf « Chronologie de la
  /// recette seule » choisie par lui.
  bool _change(ChoixProcessus choix) =>
      _touched && _selection(choix) != _courant(choix);

  Future<void> _apply(ChoixProcessus choix) async {
    if (_saving || !_change(choix)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final modele = choix.modele(_selection(choix));
    Deroule? deroule;
    if (modele != null) {
      final evalue = evaluerAssemblage(
        modele: modele,
        recipe: _brew.recipe,
        nouvelleCle: ref.read(processesRepositoryProvider).newKey,
        errors: ref.read(errorReportServiceProvider),
        reported: ref.read(derouleReportsProvider),
      );
      switch (evalue) {
        case AssemblageRefuse(:final cause):
          setState(() => _error = cause);
          return;
        case AssemblageObtenu(:final assemble):
          deroule = assemble.deroule;
      }
    }
    setState(() => _saving = true);
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final ownerName = await widget.tokenName;
    if (!mounted) return;
    suivreEcriture(
      messenger: messenger,
      written: ref
          .read(brewsRepositoryProvider)
          .setProcess(brewId: _brew.id, deroule: deroule, ownerName: ownerName),
      succes: offline ? TextesDeroule.changeHorsLigne : TextesDeroule.change,
      refus: 'L\'enregistrement de « ${_brew.name} » a échoué.',
    );
    navigator.pop();
  }

  void _ouvrir(String path) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push(path));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = ref.watch(grantedAccessProvider);
    final choix = lireChoixProcessus(
      ref,
      readerUid: access?.user.uid,
      offline: access?.offline ?? false,
    );
    final selection = _selection(choix);
    final modele = choix.modele(selection);
    final process = _brew.process;
    final AssemblageEvalue? apercu;
    if (selection == kProcessusActuel && process != null) {
      // Déroulé actuel du brassin, dates changées comprises.
      apercu = process.probleme != null
          ? const AssemblageRefuse(kDerouleIllisible)
          : AssemblageObtenu(
              DerouleAssemble(deroule: process, annonces: const []),
            );
    } else if (modele != null) {
      apercu = evaluerAssemblage(
        modele: modele,
        recipe: _brew.recipe,
        nouvelleCle: clesApercu(),
        errors: ref.read(errorReportServiceProvider),
        reported: ref.read(derouleReportsProvider),
      );
    } else {
      apercu = null;
    }
    final change = _change(choix);
    // Chronologie de la recette figée, lue comme un déroulé sans processus
    // (P37) ; illisible, la section du brassin affiche déjà la panne.
    final seule = Deroule.depuisRecette(_brew.recipe).brassage?.lignes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            TextesDeroule.changerProcessus,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 16),
        ChampProcessus(
          choix: choix,
          selection: selection,
          errorText: _error,
          actuel: _nomActuel(choix),
          surLaFiche: true,
          onChanged: (id) => setState(() {
            _processId = id;
            _touched = true;
            _error = null;
          }),
          onRetry: () => ref.invalidate(processTemplatesProvider),
          onGerer: () => _ouvrir(AppRoutes.processes),
          onCreer: () => _ouvrir(AppRoutes.newProcess),
        ),
        const SizedBox(height: 8),
        DerouleProcessusPrevu(
          evalue: apercu,
          depart: _brew.departDeroule,
          chronologieSeule: Text(
            seule == null || seule.isEmpty
                ? 'Cette recette figée n\'a pas de chronologie : le jour du '
                      'brassage n\'aura aucune étape à suivre.'
                : 'Chronologie : ${formatEtapes(seule.length)} · '
                      '${formatDuree(dureeChronologie(seule))}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 24),
        if (!change)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              TextesDeroule.choisirAutre,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
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
              onPressed: _saving || !change
                  ? null
                  : () => unawaited(_apply(choix)),
              child: _saving
                  ? const IndicateurBouton(label: 'Enregistrement')
                  : const Text('Appliquer'),
            ),
          ],
        ),
      ],
    );
  }
}
