import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/services/error_report_service.dart';
import '../../equipment/domain/equipment.dart';
import '../domain/recipe.dart';

/// Équipement d'une recette tel que l'écran le connaît. Il donne le rendement
/// d'empâtage du calcul et le libellé de la donnée qui manque : `brewing/` dit
/// seulement que le rendement manque (`MissingInputKind.mashEfficiency`).
sealed class EquipementRecette {
  const EquipementRecette();

  /// Rendement d'empâtage passé à `computeRecipe`, ou `null` s'il est inconnu.
  double? get efficiency => null;
}

/// « Aucun équipement » choisi.
class SansEquipement extends EquipementRecette {
  const SansEquipement();
}

/// Absent d'une lecture du serveur : supprimé (E10).
class EquipementSupprime extends EquipementRecette {
  const EquipementSupprime();
}

/// Absent du cache, appareil hors ligne (H4) : jamais présenté comme supprimé.
class EquipementHorsLigne extends EquipementRecette {
  const EquipementHorsLigne();
}

/// Document de l'équipement illisible (déjà rapporté).
class EquipementIllisible extends EquipementRecette {
  const EquipementIllisible();
}

/// Lecture des équipements en cours.
class EquipementEnLecture extends EquipementRecette {
  const EquipementEnLecture();
}

/// Lecture des équipements impossible (déjà rapportée).
class EquipementLectureImpossible extends EquipementRecette {
  const EquipementLectureImpossible();
}

/// Équipement lu.
class EquipementConnu extends EquipementRecette {
  const EquipementConnu(this.equipment);

  final Equipment equipment;

  @override
  double? get efficiency => equipment.content.mashEfficiencyPct;
}

/// Équipement [equipmentId] dans la liste [equipment].
EquipementRecette equipementDe(
  String? equipmentId,
  AsyncValue<ListeLue<Equipment>> equipment, {
  required bool offline,
}) {
  if (equipmentId == null) return const SansEquipement();
  final list = equipment.value;
  if (list == null) {
    return equipment.hasError
        ? const EquipementLectureImpossible()
        : const EquipementEnLecture();
  }
  return switch (list.chercher(equipmentId)) {
    DocumentTrouve<Equipment>(:final value) => EquipementConnu(value),
    DocumentIllisibleTrouve<Equipment>() => const EquipementIllisible(),
    DocumentAbsent<Equipment>() => const EquipementSupprime(),
    DocumentAbsentDuCache<Equipment>() =>
      offline ? const EquipementHorsLigne() : const EquipementEnLecture(),
  };
}

/// Libellé court de l'équipement, pour la ligne d'hypothèses et l'éditeur.
String libelleEquipement(EquipementRecette equipement) => switch (equipement) {
  SansEquipement() => 'Aucun équipement',
  EquipementSupprime() => 'Équipement supprimé',
  EquipementHorsLigne() => 'Équipement indisponible hors ligne',
  EquipementIllisible() => 'Équipement illisible',
  EquipementEnLecture() => 'Équipement en cours de lecture',
  EquipementLectureImpossible() => 'Équipements illisibles',
  EquipementConnu(:final equipment) =>
    equipment.content.mashEfficiencyPct == null
        ? equipment.name
        : '${equipment.name} '
              '(${formatPourcent(equipment.content.mashEfficiencyPct!)})',
};

/// Résultat des calculs d'une recette, pour l'écran.
sealed class CalculsRecette {
  const CalculsRecette();
}

/// Calculs faits : chaque indicateur est une valeur ou ce qui lui manque.
class CalculsObtenus extends CalculsRecette {
  const CalculsObtenus(this.calculation);

  final RecipeCalculation calculation;
}

/// `brewing/` a refusé une valeur hors limites (`BrewingInputException`).
class CalculsImpossibles extends CalculsRecette {
  const CalculsImpossibles(this.field);

  /// Champ refusé, nom technique.
  final String field;
}

/// Calcule [content] avec le rendement de [equipement] (C1 à C9).
///
/// Une donnée manquante est un état normal, non rapporté. Une valeur hors limites
/// (`BrewingInputException`) rend [CalculsImpossibles] : l'écran affiche « Calcul
/// impossible », jamais une valeur par défaut. Elle est rapportée une seule fois par
/// recette ([recipeKey]) et par champ ; [reported] garde les rapports déjà faits.
CalculsRecette evaluerRecette(
  RecipeContent content,
  EquipementRecette equipement, {
  required ErrorReportService errors,
  required Set<String> reported,
  required String recipeKey,
}) {
  try {
    return CalculsObtenus(
      computeRecipe(
        recipe: content.toInput(),
        mashEfficiencyPercent: equipement.efficiency,
      ),
    );
  } on BrewingInputException catch (error, stackTrace) {
    // Une fois par recette et par champ : l'éditeur recalcule à chaque frappe
    // (« 2 » avant « 20 »), et la fiche à chaque lecture.
    if (reported.add('$recipeKey|${error.field}')) {
      errors.reportError(
        feature: 'recipes.calculation',
        error: error,
        stackTrace: stackTrace,
        context: 'valeur refusée par brewing : ${error.field}',
      );
    }
    return CalculsImpossibles(error.field);
  }
}

/// Nom affiché du champ refusé par `brewing/`.
String libelleChamp(String field) {
  final name = field.split('.').last.replaceAll(RegExp(r'\[\d+\]'), '');
  return switch (name) {
    'batchVolumeLitres' || 'volumeLitres' => 'volume',
    'originalGravity' => 'densité initiale',
    'finalGravity' => 'densité finale',
    'boilGravity' => 'densité d\'ébullition',
    'mashEfficiencyPercent' => 'rendement d\'empâtage',
    'massGrams' => 'quantité',
    'yieldPercent' => 'rendement d\'extrait',
    'colorEbc' => 'couleur',
    'alphaPercent' => 'acides alpha',
    'attenuationPercent' => 'atténuation',
    'minutes' || 'boilMinutes' => 'durée',
    _ => name,
  };
}

/// « Calcul impossible : densité initiale hors des limites. »
String messageCalculImpossible(String field) =>
    'Calcul impossible : ${libelleChamp(field)} hors des limites.';

String _names(MissingInput m) => {for (final i in m.items) i.name}.join(', ');

/// Libellé « À compléter » d'une donnée manquante.
String libelleManque(
  MissingInput missing,
  EquipementRecette equipement,
) => switch (missing.kind) {
  MissingInputKind.batchVolume => 'Volume en fermenteur non renseigné.',
  MissingInputKind.fermentables => 'Aucun malt ni sucre.',
  MissingInputKind.mashEfficiency => switch (equipement) {
    SansEquipement() => 'Aucun équipement choisi.',
    EquipementSupprime() => 'L\'équipement de cette recette n\'existe plus.',
    EquipementHorsLigne() => 'Équipement indisponible hors ligne.',
    EquipementIllisible() => 'L\'équipement de cette recette est illisible.',
    EquipementEnLecture() => 'Lecture de l\'équipement en cours.',
    EquipementLectureImpossible() => 'Lecture des équipements impossible.',
    EquipementConnu(:final equipment) =>
      'Rendement d\'empâtage non renseigné dans « ${equipment.name} ».',
  },
  MissingInputKind.extractYield =>
    'Rendement d\'extrait non renseigné : ${_names(missing)}.',
  MissingInputKind.color => 'Couleur non renseignée : ${_names(missing)}.',
  MissingInputKind.hopAlpha =>
    'Acides alpha non renseignés : ${_names(missing)}.',
  MissingInputKind.hopBoilTime => 'Durée non renseignée : ${_names(missing)}.',
  MissingInputKind.yeast => 'Aucune levure.',
  MissingInputKind.yeastAttenuation =>
    'Atténuation non renseignée : ${_names(missing)}.',
  MissingInputKind.originalGravity => 'Dépend de la densité initiale.',
};

/// Un indicateur : libellé, abréviation de la barre, mise en forme.
typedef _Indicateur = ({
  String label,
  String short,
  CalculationResult result,
  String Function(double) format,
});

List<_Indicateur> _indicateurs(RecipeCalculation c) => [
  (
    label: 'Densité initiale',
    short: 'DI',
    result: c.originalGravity,
    format: formatDensite,
  ),
  (
    label: 'Densité finale',
    short: 'DF',
    result: c.finalGravity,
    format: formatDensite,
  ),
  (label: 'Degré', short: '%', result: c.alcoholByVolume, format: formatDegre),
  (label: 'Amertume', short: 'IBU', result: c.bitternessIbu, format: formatIbu),
  (label: 'Couleur', short: 'EBC', result: c.colorEbc, format: formatEbc),
];

/// Ligne d'hypothèses : « Pour 20 L · Grainfather (72 %) · US-05 78 % ».
String ligneHypotheses(RecipeContent content, EquipementRecette equipement) {
  final volume = content.batchVolumeL;
  final yeast = content.yeasts.isEmpty ? null : content.yeasts.first;
  final attenuation = yeast?.attenuationPct;
  return [
    if (volume != null) 'Pour ${formatLitres(volume)}',
    libelleEquipement(equipement),
    if (yeast != null)
      attenuation == null
          ? yeast.name
          : '${yeast.name} ${formatPourcent(attenuation)}',
  ].join(' · ');
}

/// Bloc des calculs du détail et du panneau de l'éditeur : cinq tuiles, ligne
/// d'hypothèses, « À compléter », « Détail des calculs ».
class BlocCalculs extends StatelessWidget {
  const BlocCalculs({
    super.key,
    required this.calculs,
    required this.content,
    required this.equipement,
    this.onComplete,
  });

  final CalculsRecette calculs;
  final RecipeContent content;
  final EquipementRecette equipement;

  /// « Compléter la recette », pour l'auteur seul.
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calculs = this.calculs;
    if (calculs is CalculsImpossibles) {
      return Semantics(
        liveRegion: true,
        child: Material(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    messageCalculImpossible(calculs.field),
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final c = (calculs as CalculsObtenus).calculation;
    final missing = c.missingInputs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final width = constraints.maxWidth;
            // La largeur minimale suit l'échelle du texte : à 200 %, « 1057,9 » ne
            // se coupe pas, et les tuiles passent sur moins de colonnes.
            final minTile =
                kCalculationTileMinWidth *
                MediaQuery.textScalerOf(context).scale(1);
            final maxColumns = width < kCompactMaxWidth ? 2 : 5;
            final columns = ((width + spacing) / (minTile + spacing))
                .floor()
                .clamp(1, maxColumns);
            final tileWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final i in _indicateurs(c))
                  SizedBox(
                    width: tileWidth,
                    child: _Tuile(indicateur: i),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          ligneHypotheses(content, equipement),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text('À compléter', style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: 4),
          for (final m in missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: Text('•  ')),
                  Expanded(child: Text(libelleManque(m, equipement))),
                ],
              ),
            ),
          if (onComplete != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: onComplete,
                child: const Text('Compléter la recette'),
              ),
            ),
          ],
        ],
        const SizedBox(height: 8),
        _DetailCalculs(calculation: c, content: content),
      ],
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({required this.indicateur});

  final _Indicateur indicateur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = indicateur.result;
    final String value;
    String? note;
    switch (result) {
      case CalculationComputed(:final value):
        final text = indicateur.format(value);
        return _frame(
          context,
          '${indicateur.label}, $text',
          Text(text, style: theme.textTheme.headlineSmall),
        );
      case CalculationUnavailable(:final missing):
        value = 'Indisponible';
        if (missing.every((m) => m.kind == MissingInputKind.originalGravity)) {
          note = 'Dépend de la densité initiale.';
        }
    }
    final muted = theme.colorScheme.onSurfaceVariant;
    return _frame(
      context,
      '${indicateur.label}, indisponible${note == null ? '' : '. $note'}',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          if (note != null)
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }

  Widget _frame(BuildContext context, String semantics, Widget value) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(indicateur.label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                value,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailCalculs extends StatelessWidget {
  const _DetailCalculs({required this.calculation, required this.content});

  final RecipeCalculation calculation;
  final RecipeContent content;

  @override
  Widget build(BuildContext context) {
    final boil = calculation.boilGravity;
    final hops = calculation.hopBitterness;
    return ExpansionTile(
      title: const Text('Détail des calculs'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          boil == null
              ? 'Densité d\'ébullition retenue pour l\'amertume : indisponible.'
              : 'Densité d\'ébullition retenue pour l\'amertume : '
                    '${formatDensite(boil)} (densité initiale prévue).',
        ),
        if (hops.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Amertume par houblon :'),
          for (final h in hops)
            Text('${h.hop.name} : ${formatIbu(h.ibu)}${_hopNote(h)}'),
        ],
        const SizedBox(height: 8),
        const Text(
          'Méthodes : amertume de Tinseth, couleur de Morey, densité finale par '
          'l\'atténuation de la levure. Aucune valeur n\'est enregistrée : tout '
          'est recalculé à l\'affichage.',
        ),
      ],
    );
  }

  String _hopNote(HopBitterness h) {
    final index = h.hop.index;
    if (index >= content.hops.length) return '';
    final hop = content.hops[index];
    final minutes = hop.timeMin;
    return switch (hop.use) {
      HopUse.boil =>
        minutes == null ? '' : ' (ébullition ${formatMinutes(minutes)})',
      HopUse.afterBoil => ' (whirlpool, hors ébullition)',
      HopUse.dryHop => ' (à cru, hors ébullition)',
    };
  }
}

/// Barre des calculs de l'éditeur sous 840 px : « DI 1057,9 · DF 1012,0 · 5,9 %
/// · 32 IBU · 18 EBC ». Un appui ouvre le bloc complet.
class BarreCalculs extends StatelessWidget {
  const BarreCalculs({super.key, required this.calculs, required this.onTap});

  final CalculsRecette calculs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calculs = this.calculs;
    final String text;
    final String semantics;
    switch (calculs) {
      case CalculsImpossibles(:final field):
        text = messageCalculImpossible(field);
        semantics = text;
      case CalculsObtenus(:final calculation):
        final parts = <String>[];
        final spoken = <String>[];
        for (final i in _indicateurs(calculation)) {
          final r = i.result;
          if (r is CalculationComputed) {
            final v = i.format(r.value);
            parts.add(i.short == 'DI' || i.short == 'DF' ? '${i.short} $v' : v);
            spoken.add('${i.label} $v');
          } else {
            parts.add('${i.short} —');
            spoken.add('${i.label} indisponible');
          }
        }
        text = parts.join(' · ');
        semantics = '${spoken.join(', ')}. Ouvrir le détail des calculs.';
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        // Un seul nœud, lu d'un bloc, qui porte l'action : le double appui du
        // lecteur d'écran ouvre le détail.
        child: Semantics(
          button: true,
          label: semantics,
          onTap: onTap,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(text, style: theme.textTheme.titleSmall),
                    ),
                    const Icon(Icons.expand_less),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
