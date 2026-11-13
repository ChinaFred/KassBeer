import 'dart:async';

import 'package:brewing/brewing.dart' show BrewingInputException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/etats.dart';
import '../../../core/services/error_report_service.dart';
import '../../processes/domain/modele_processus.dart';
import '../../processes/domain/preference_processus.dart';
import '../../processes/presentation/libelles_processus.dart';
import '../../processes/presentation/processes_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/assemblage_deroule.dart';
import 'libelles_deroule.dart';

/// Choix du processus d'un brassin (ADR-010, lot D3) : « Nouveau brassin » et
/// « Changer de processus » sur la fiche d'un brassin prévu. Seuls les modèles
/// du lecteur sont proposés ; aucun modèle d'un autre membre n'est présélectionné.

/// Valeur de « Chronologie de la recette seule » dans la liste déroulante.
const kSansProcessus = '';

/// Valeur de l'entrée « {nom} (actuel) » de « Changer de processus ».
const kProcessusActuel = '#actuel';

/// Libellé de « Chronologie de la recette seule ».
const kChronologieSeule = 'Chronologie de la recette seule';

/// Textes de l'écran de choix.
abstract final class TextesChoixProcessus {
  static const aide =
      'Ajoute les étapes de préparation et les journées après le brassage.';
  static const lecture = 'Lecture des processus';
  static const erreur = 'Impossible de lire les processus.';
  static const aucun = 'Aucun processus.';
  static const defautSupprime = 'Votre processus par défaut a été supprimé.';
  static const horsLigne =
      'Processus indisponibles hors ligne. Créez le brassin avec la '
      'chronologie de la recette seule, puis choisissez son processus sur sa '
      'fiche au retour du réseau.';

  /// Hors ligne, sur la fiche d'un brassin qui existe déjà.
  static const horsLigneFiche =
      'Processus indisponibles hors ligne. Changez de processus au retour du '
      'réseau.';
  static const modeleInvalide =
      'Ce processus est invalide : corrigez-le dans Mes processus.';
  static const jourHorsLimites =
      'Un houblon à cru de cette recette a un jour d\'ajout hors de 0 à 365 '
      'jours.';
  static const recetteRefusee =
      'Une valeur de cette recette empêche d\'appliquer ce processus.';

  /// « Déroulé prévu : Mon processus, 3 journées. » : le nom distingue deux
  /// processus de même nombre de journées dans la région live.
  static String annonceDeroule(String? processus, int journees) {
    final nom = processus?.trim();
    return 'Déroulé prévu : '
        '${nom == null || nom.isEmpty ? '' : '$nom, '}'
        '${formatJournees(journees)}.';
  }
}

/// État de la lecture des modèles du lecteur.
enum EtatChoixProcessus {
  /// Première lecture en cours ; la création reste possible sans processus.
  lecture,

  /// Lecture en échec, sans liste lue.
  erreur,

  /// Lu du serveur : le lecteur n'a aucun modèle.
  aucun,

  /// Hors ligne, aucun modèle du lecteur dans le cache.
  horsLigne,

  /// Au moins un modèle du lecteur.
  pret,
}

/// Modèles du lecteur, triés par nom, et présélection.
@immutable
class ChoixProcessus {
  const ChoixProcessus({
    required this.etat,
    required this.miens,
    required this.defaut,
    required this.defautSupprime,
  });

  final EtatChoixProcessus etat;
  final List<ModeleProcessus> miens;

  /// Présélection : le choix par défaut du lecteur s'il est un de ses modèles,
  /// sinon `null` (« Chronologie de la recette seule »).
  final String? defaut;

  /// Le choix par défaut désigne un modèle absent du serveur.
  final bool defautSupprime;

  /// Modèle [id] du lecteur, ou `null`.
  ModeleProcessus? modele(String? id) =>
      id == null ? null : miens.where((m) => m.id == id).firstOrNull;

  /// [id] s'il désigne encore un modèle du lecteur, sinon `null`.
  String? valide(String? id) => modele(id)?.id;
}

/// Lit les modèles et le choix par défaut de [readerUid]. Les modèles se lisent
/// à l'ouverture de l'écran, pas au lancement de l'application.
ChoixProcessus lireChoixProcessus(
  WidgetRef ref, {
  required String? readerUid,
  required bool offline,
}) {
  final async = ref.watch(processTemplatesProvider);
  final preference = readerUid == null
      ? null
      : ref.watch(processPreferenceProvider(readerUid)).value;
  final list = async.value;
  final miens =
      [
        for (final m in [...?list?.valides])
          if (m.ownerUid == readerUid) m,
      ]..sort(
        (a, b) => a.content.name.toLowerCase().compareTo(
          b.content.name.toLowerCase(),
        ),
      );
  final prefere = idModeleParDefaut(preference);
  final defaut = miens.any((m) => m.id == prefere) ? prefere : null;
  final EtatChoixProcessus etat;
  if (list == null) {
    etat = async.hasError
        ? EtatChoixProcessus.erreur
        : (offline ? EtatChoixProcessus.horsLigne : EtatChoixProcessus.lecture);
  } else if (miens.isNotEmpty) {
    etat = EtatChoixProcessus.pret;
  } else if (list.fromCache) {
    etat = offline ? EtatChoixProcessus.horsLigne : EtatChoixProcessus.lecture;
  } else {
    etat = EtatChoixProcessus.aucun;
  }
  return ChoixProcessus(
    etat: etat,
    miens: List.unmodifiable(miens),
    defaut: defaut,
    defautSupprime:
        prefere != null && defaut == null && list != null && !list.fromCache,
  );
}

/// Résultat de l'assemblage du déroulé pour un modèle.
sealed class AssemblageEvalue {
  const AssemblageEvalue();
}

class AssemblageObtenu extends AssemblageEvalue {
  const AssemblageObtenu(this.assemble);

  final DerouleAssemble assemble;
}

/// `brewing/` ou [erreurDeroule] refuse le déroulé : rapporté, jamais remplacé.
class AssemblageRefuse extends AssemblageEvalue {
  const AssemblageRefuse(this.cause);

  /// Cause affichée au brasseur.
  final String cause;
}

/// Assemble le déroulé de [modele] avec [recipe]. Un refus est rapporté une fois
/// par modèle et par raison ([reported]) et rend [AssemblageRefuse] : l'écran
/// affiche la panne.
AssemblageEvalue evaluerAssemblage({
  required ModeleProcessus modele,
  required RecipeContent recipe,
  required String Function() nouvelleCle,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  try {
    return AssemblageObtenu(
      assemblerDeroule(
        templateId: modele.id,
        modele: modele.content,
        recipe: recipe,
        nouvelleCle: nouvelleCle,
      ),
    );
  } on AssemblageImpossible catch (error, stackTrace) {
    if (reported.add('${modele.id}|${error.raison}')) {
      errors.reportError(
        feature: 'brews.process_assembly',
        error: error,
        stackTrace: stackTrace,
        context: 'process_templates/${modele.id} : déroulé refusé',
      );
    }
    return AssemblageRefuse(error.cause);
  } on BrewingInputException catch (error, stackTrace) {
    if (reported.add('${modele.id}|${error.field}')) {
      errors.reportError(
        feature: 'brews.process_assembly',
        error: error,
        stackTrace: stackTrace,
        context:
            'process_templates/${modele.id} : résolution refusée '
            '${error.field}',
      );
    }
    return AssemblageRefuse(switch (error.field) {
      'template' => TextesChoixProcessus.modeleInvalide,
      'dayMinutes' || 'dryHopDay' => TextesChoixProcessus.jourHorsLimites,
      _ => TextesChoixProcessus.recetteRefusee,
    });
  }
}

/// Refus d'assemblage déjà rapportés pendant la session : un rapport par modèle
/// et par raison, pas un par affichage.
final derouleReportsProvider = Provider<Set<String>>((ref) => <String>{});

/// Clés de l'aperçu : il ne s'écrit pas, ses clés ne servent qu'à l'affichage.
String Function() clesApercu() {
  var n = 0;
  return () => 'apercu-${n++}';
}

/// Champ « Processus », son état de lecture et le lien « Gérer mes processus ».
class ChampProcessus extends StatelessWidget {
  const ChampProcessus({
    super.key,
    required this.choix,
    required this.selection,
    required this.onChanged,
    required this.onRetry,
    required this.onGerer,
    required this.onCreer,
    this.errorText,
    this.actuel,
    this.surLaFiche = false,
  });

  final ChoixProcessus choix;

  /// Nom du processus actuel d'un brassin quand il n'est pas dans la liste lue
  /// (modèle supprimé, liste en lecture, hors ligne) : entrée
  /// « {nom} (actuel) », de valeur [kProcessusActuel].
  final String? actuel;

  /// Feuille « Changer de processus » d'un brassin qui existe : texte hors ligne
  /// propre, et aucun rappel du processus par défaut (« Nouveau brassin »
  /// seulement).
  final bool surLaFiche;

  /// Modèle choisi, ou `null` : « Chronologie de la recette seule ».
  final String? selection;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRetry;

  /// Ferme le formulaire et ouvre « Mes processus ».
  final VoidCallback onGerer;

  /// Ferme le formulaire et ouvre « Nouveau processus ».
  final VoidCallback onCreer;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = TextStyle(color: theme.colorScheme.error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('processus-$selection-${choix.miens.length}'),
          initialValue: selection ?? kSansProcessus,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Processus',
            helperText: TextesChoixProcessus.aide,
            helperMaxLines: 3,
            errorText: errorText,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(
              value: kSansProcessus,
              child: Text(kChronologieSeule, overflow: TextOverflow.ellipsis),
            ),
            if (actuel case final String nom)
              DropdownMenuItem(
                value: kProcessusActuel,
                child: Text('$nom (actuel)', overflow: TextOverflow.ellipsis),
              ),
            for (final m in choix.miens)
              DropdownMenuItem(
                value: m.id,
                child: Text(m.content.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => onChanged(
            value == null || value == kSansProcessus ? null : value,
          ),
        ),
        switch (choix.etat) {
          EtatChoixProcessus.lecture => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: IndicateurBouton(label: TextesChoixProcessus.lecture),
          ),
          EtatChoixProcessus.erreur => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(TextesChoixProcessus.erreur, style: error),
                ),
                TextButton(onPressed: onRetry, child: const Text('Réessayer')),
              ],
            ),
          ),
          EtatChoixProcessus.aucun => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Expanded(child: Text(TextesChoixProcessus.aucun)),
                TextButton(
                  onPressed: onCreer,
                  child: const Text('Créer un processus'),
                ),
              ],
            ),
          ),
          EtatChoixProcessus.horsLigne => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              surLaFiche
                  ? TextesChoixProcessus.horsLigneFiche
                  : TextesChoixProcessus.horsLigne,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          EtatChoixProcessus.pret => const SizedBox.shrink(),
        },
        if (choix.defautSupprime && !surLaFiche)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(TextesChoixProcessus.defautSupprime),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onGerer,
            child: const Text('Gérer mes processus'),
          ),
        ),
      ],
    );
  }
}

/// Bloc « Déroulé prévu » : les journées du processus choisi et leurs dates
/// depuis [depart], puis les annonces ; [chronologieSeule] sans processus.
class DerouleProcessusPrevu extends StatelessWidget {
  const DerouleProcessusPrevu({
    super.key,
    required this.evalue,
    required this.depart,
    required this.chronologieSeule,
  });

  /// Assemblage du processus choisi, ou `null` : « Chronologie de la recette
  /// seule ».
  final AssemblageEvalue? evalue;
  final DateTime? depart;
  final Widget chronologieSeule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = evalue;
    final Widget contenu = switch (e) {
      null => chronologieSeule,
      AssemblageRefuse(:final cause) => Semantics(
        liveRegion: true,
        child: Text(cause, style: TextStyle(color: theme.colorScheme.error)),
      ),
      // Lignes lues telles quelles ; la région live ne porte que la synthèse et
      // les annonces, relues à chaque changement de processus ou de date.
      AssemblageObtenu(:final assemble) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final j in assemble.deroule.journees)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                ligneDeroulePrevu(j, depart),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final a in assemble.annonces)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  a,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    };
    final synthese = switch (e) {
      AssemblageObtenu(:final assemble) => TextesChoixProcessus.annonceDeroule(
        assemble.deroule.templateName,
        assemble.deroule.journees.length,
      ),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: synthese != null,
          label: synthese,
          excludeSemantics: synthese != null,
          child: Text('Déroulé prévu', style: theme.textTheme.labelLarge),
        ),
        const SizedBox(height: 4),
        contenu,
      ],
    );
  }
}

/// Annonce le refus du seul déroulé [written], écrit juste après la création
/// [creation]. Un brassin refusé à la création rend aussi son déroulé refusé :
/// seul le refus de la création s'annonce alors (`suivreEcriture`).
void suivreDeroule({
  required ScaffoldMessengerState messenger,
  required Future<void> creation,
  required Future<void> written,
  required String refus,
}) {
  unawaited(
    written.catchError((Object _) async {
      // Les deux refus sont déjà rapportés par le dépôt de données.
      final cree = await creation.then(
        (_) => true,
        onError: (Object _) => false,
      );
      if (!cree) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(refus)));
    }),
  );
}
