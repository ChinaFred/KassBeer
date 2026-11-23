import 'dart:convert';

import 'package:brewing/brewing.dart';
import 'package:exchange/exchange.dart';
import 'package:flutter/material.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/beerjson.dart';
import '../domain/recipe.dart';
import 'assistant_controleur.dart';
import 'contenu_recette.dart';
import 'recipe_calculations_view.dart';

/// Carte « Proposition de l'assistant » (ADR-015, section 6, lot A2 ;
/// proposition de `ux-designer` validée le 2026-11-21). L'aperçu se calcule
/// sur le brouillon actuel de l'éditeur : `appliquerProposition` (`exchange/`)
/// avec la Bibliothèque entière, puis `computeRecipe` avant et après (P3, P61).
/// « Appliquer au brouillon » n'appelle pas le modèle et marche hors ligne ;
/// rien n'est écrit avant « Enregistrer ».

/// Libellés de la carte.
abstract final class TextesProposition {
  static const titre = 'Proposition de l\'assistant';
  static const appliquer = 'Appliquer au brouillon';
  static const voirDetail = 'Voir le détail';
  static const masquerDetail = 'Masquer le détail';
  static const annuler = 'Annuler la proposition';
  static const preparation = 'Préparation de l\'aperçu…';
  static const bibliothequeIllisible =
      'Aperçu impossible : la Bibliothèque n\'a pas pu être lue.';
  static const reessayer = 'Réessayer';
  static const invalide =
      'Cette proposition donne une recette invalide. Elle ne peut pas '
      's\'appliquer.';
  static const aucunChangement =
      'Aucun changement de cette proposition ne peut s\'appliquer.';
  static const perimee =
      'La recette a changé depuis cette proposition. Vérifiez le détail avant '
      'd\'appliquer.';
  static const appliquee =
      'Appliquée au brouillon. Rien n\'est enregistré avant « Enregistrer ».';
  static const annulee =
      'Proposition annulée. Le brouillon d\'avant est revenu.';
  static const remplacee = 'Une autre proposition a été appliquée depuis.';
  static const ecartee =
      'L\'assistant a rendu une proposition illisible. Elle ne peut pas '
      's\'appliquer : reformulez votre demande.';
  static const changements = 'Changements';
  static const calculs = 'Calculs avant et après';
  static const refuses = 'Changements refusés';
  static const annonceAppliquee =
      'Proposition appliquée au brouillon. Rien n\'est enregistré.';
  static const confirmerAnnulation = 'Annuler la proposition ?';
  static const confirmerAnnulationTexte =
      'Le brouillon revient à son état d\'avant la proposition. Les '
      'modifications faites depuis seront perdues.';

  static String compte({
    required int changements,
    required int valeursIa,
    required int refuses,
  }) => [
    changements == 1 ? '1 changement' : '$changements changements',
    if (valeursIa > 0)
      valeursIa == 1
          ? '1 valeur proposée par l\'IA'
          : '$valeursIa valeurs proposées par l\'IA',
    if (refuses > 0) refuses == 1 ? '1 refusé' : '$refuses refusés',
  ].join(' · ');
}

/// Ce que l'éditeur a fait de la proposition d'une réponse.
enum EtatApplication {
  /// Appliquée, la dernière : « Annuler la proposition » est proposé.
  appliquee,

  /// Annulée : le brouillon d'avant est revenu.
  annulee,

  /// Une autre proposition a été appliquée depuis : plus d'annulation.
  remplacee,
}

/// Empreinte du sous-arbre `recipe` d'un brouillon, pour dire qu'il a changé
/// (proposition périmée, modification à la main après « Appliquer »).
/// `null` si le brouillon ne s'écrit pas (ligne refusée) : rapporté.
String? empreinteBrouillon(RecipeContent content, ErrorReportService errors) {
  try {
    return jsonEncode(content.toFirestore(creation: true)['recipe']);
  } catch (error, stackTrace) {
    // Aucun texte de la recette (P13).
    errors.reportError(
      feature: 'recipes.assistant_proposition',
      error: error,
      stackTrace: stackTrace,
      context: 'brouillon illisible : ${error.runtimeType}',
    );
    return null;
  }
}

// --- Aperçu ------------------------------------------------------------------

/// Ligne de l'aperçu : texte affiché et texte lu (sans flèche).
typedef LigneApercu = ({String texte, String lecture});

/// Aperçu d'une proposition sur un brouillon.
sealed class Apercu {
  const Apercu();
}

/// La recette relue est refusée : la proposition ne s'applique pas.
class ApercuInvalide extends Apercu {
  const ApercuInvalide(this.refus);

  final List<LigneApercu> refus;
}

/// Aperçu prêt : [apres] remplace le brouillon à « Appliquer ».
class ApercuPret extends Apercu {
  const ApercuPret({
    required this.resultat,
    required this.apres,
    required this.changements,
    required this.calculs,
    required this.refus,
    required this.valeursIa,
  });

  final PropositionAppliquee resultat;
  final RecipeContent apres;
  final List<LigneApercu> changements;

  /// Les cinq chiffres, avant et après ; `change` : la valeur affichée change.
  final List<({LigneApercu ligne, bool change})> calculs;
  final List<LigneApercu> refus;

  /// Valeurs que cette proposition marque « proposée par l'IA ».
  final int valeursIa;
}

String _sansFleche(String texte) => texte.replaceAll(' → ', ', devient ');

LigneApercu _ligne(String texte) => (texte: texte, lecture: _sansFleche(texte));

/// Nom de la ligne visée par un changement de liste, au singulier.
String _nomListe(String op) => switch (op.split('_').last) {
  'fermentable' => 'malt',
  'hop' => 'houblon',
  'misc' => 'ingrédient',
  'step' => 'palier',
  _ => 'élément',
};

String _demonstratif(String nom) =>
    nom.startsWith(RegExp('[aeiouéè]')) ? 'cet $nom' : 'ce $nom';

/// Champ nommé dans un refus.
String _libelleChamp(String? champ) => switch (champ) {
  'amount_g' || 'amount_l' => 'quantité',
  'name' => 'nom',
  'color_ebc' => 'couleur',
  'yield_pct' => 'rendement',
  'alpha_acid_pct' => 'acides alpha',
  'attenuation_pct' => 'atténuation',
  'time_min' || 'days' => 'durée',
  'temperature_c' => 'température',
  'index' => 'rang',
  _ => 'valeur',
};

/// Phrase d'un changement refusé : « Modification du houblon n° 4 : ce houblon
/// n'est plus dans la recette. »
String texteRefus(OperationProposee o, RefusOperation r) {
  final nom = _nomListe(o.op);
  final index = o.champs['index'];
  final rang = index is num ? ' n° ${index.toInt() + 1}' : '';
  final deLa = nom.startsWith(RegExp('[aeiouéè]')) ? 'de l\'$nom' : 'du $nom';
  final nomOp = o.champs['name'];
  final unNom = 'd\'un $nom';
  final sujet = switch (o.op) {
    'set_name' => 'Nom de la recette',
    'set_type' => 'Type de recette',
    'set_style_name' => 'Style',
    'set_batch_size_l' => 'Volume',
    'set_boil_time_min' => 'Durée d\'ébullition',
    'set_culture' => nomOp is String ? 'Levure $nomOp' : 'Levure',
    final op when op.startsWith('add_') =>
      nomOp is String ? 'Ajout de $nomOp' : 'Ajout $unNom',
    final op when op.startsWith('update_') => 'Modification $deLa$rang',
    _ => 'Retrait $deLa$rang',
  };
  final champ = _libelleChamp(r.champ);
  final raison = switch (r.raison) {
    RaisonRefusOperation.indexAbsent =>
      '${_demonstratif(nom)} n\'est plus dans la recette.',
    RaisonRefusOperation.elementChange =>
      '${_demonstratif(nom)} a changé depuis la proposition.',
    RaisonRefusOperation.horsBornes =>
      'valeur hors des limites acceptées ($champ).',
    RaisonRefusOperation.valeurManquante => 'valeur manquante ($champ).',
    RaisonRefusOperation.champIncompatible =>
      'valeur incompatible avec le reste de la recette ($champ).',
    RaisonRefusOperation.listePleine => 'la liste est pleine.',
  };
  return '$sujet : $raison';
}

T? _parNom<T>(List<T> lignes, String Function(T) nom, Object? cherche) {
  if (cherche is! String) return null;
  final cle = normalizeName(cherche);
  for (final l in lignes.reversed) {
    if (normalizeName(nom(l)) == cle) return l;
  }
  return null;
}

String _avantApres(String quoi, String? avant, String apres) =>
    '$quoi : ${avant ?? 'non renseigné'} → $apres';

/// Une ligne par changement appliqué, verbe en tête.
List<LigneApercu> lignesChangements({
  required List<OperationProposee> operations,
  required Set<int> refusees,
  required RecipeContent avant,
  required RecipeContent apres,
}) {
  final marques = apres.aiProposed;
  final lignes = <LigneApercu>[];
  for (final (i, o) in operations.indexed) {
    if (refusees.contains(i)) continue;
    final c = o.champs;
    final verbe = o.op.startsWith('add_')
        ? 'Ajout'
        : o.op.startsWith('update_')
        ? 'Modification'
        : 'Retrait';
    String ligne(String nom, List<String> details) =>
        ['$verbe · $nom', ...details].join(' · ');
    final texte = switch (o.op) {
      'set_name' => _avantApres('Nom', avant.name, apres.name),
      'set_type' => _avantApres(
        'Type',
        avant.type == null ? null : typesRecette.libelle(avant.type!),
        typesRecette.libelle(apres.type ?? ''),
      ),
      'set_style_name' => _avantApres('Style', avant.style, apres.style ?? ''),
      'set_batch_size_l' => _avantApres(
        'Volume',
        avant.batchVolumeL == null ? null : formatLitres(avant.batchVolumeL!),
        formatLitres(apres.batchVolumeL ?? 0),
      ),
      'set_boil_time_min' => _avantApres(
        'Ébullition',
        avant.boilTimeMin == null ? null : formatMinutes(avant.boilTimeMin!),
        formatMinutes(apres.boilTimeMin ?? 0),
      ),
      'set_culture' => [
        '${avant.yeasts.isEmpty ? 'Ajout' : 'Modification'} · ${c['name']}',
        if (_parNom(apres.yeasts, (y) => y.name, c['name']) case final y?)
          ...detailsLevure(y, fiche: false, marques: marques),
      ].join(' · '),
      'add_fermentable' || 'update_fermentable' => ligne('${c['name']}', [
        if (_parNom(apres.fermentables, (f) => f.name, c['name']) case final f?)
          ...detailsFermentescible(f, fiche: false, marques: marques),
      ]),
      'add_hop' || 'update_hop' => ligne('${c['name']}', [
        if (_parNom(apres.hops, (h) => h.name, c['name']) case final h?)
          ...detailsHoublon(h, fiche: false, marques: marques),
      ]),
      'add_misc' || 'update_misc' => ligne('${c['name']}', [
        if (_parNom(apres.others, (o) => o.name, c['name']) case final a?)
          ...detailsAjout(a),
      ]),
      'add_mash_step' || 'update_mash_step' => ligne('Palier ${c['name']}', [
        if (_parNom(apres.mashSteps, (s) => s.name, c['name']) case final s?)
          ...detailsPalier(s),
      ]),
      'remove_mash_step' => ligne('Palier ${c['name']}', const []),
      _ => ligne('${c['name']}', const []),
    };
    lignes.add(_ligne(texte));
  }
  return lignes;
}

/// Les cinq chiffres avant et après, calculés par `computeRecipe`.
List<({LigneApercu ligne, bool change})> lignesCalculs(
  CalculsRecette avant,
  CalculsRecette apres,
) {
  // Formats de l'application (`formats.dart`), unité écrite une fois en fin
  // de ligne : « Degré : 5,2 → 5,6 % vol », « IBU : 28 → 35 IBU ».
  String? valeur(
    CalculationResult? r,
    String Function(double) f,
    String unite,
  ) {
    if (r is! CalculationComputed) return null;
    final texte = f(r.value);
    return unite.isEmpty ? texte : texte.replaceAll(unite, '');
  }

  final a = avant.calculOuNul;
  final b = apres.calculOuNul;
  final indicateurs =
      <
        (
          String,
          CalculationResult?,
          CalculationResult?,
          String Function(double),
          String,
        )
      >[
        (
          'Densité initiale',
          a?.originalGravity,
          b?.originalGravity,
          formatDensite,
          '',
        ),
        ('Densité finale', a?.finalGravity, b?.finalGravity, formatDensite, ''),
        (
          'Degré',
          a?.alcoholByVolume,
          b?.alcoholByVolume,
          formatDegre,
          '$nbsp%${nbsp}vol',
        ),
        ('IBU', a?.bitternessIbu, b?.bitternessIbu, formatIbu, '${nbsp}IBU'),
        ('Couleur', a?.colorEbc, b?.colorEbc, formatEbc, '${nbsp}EBC'),
      ];
  return [
    for (final (label, ra, rb, f, unite) in indicateurs)
      () {
        final va = valeur(ra, f, unite);
        final vb = valeur(rb, f, unite);
        return (
          ligne: (
            texte: '$label : ${va ?? '—'} → ${vb ?? '—'}$unite',
            lecture:
                '$label, avant ${va == null ? 'indisponible' : '$va$unite'}, '
                'après ${vb == null ? 'indisponible' : '$vb$unite'}',
          ),
          change: va != vb,
        );
      }(),
  ];
}

/// Aperçu de [proposition] sur [brouillon] avec la Bibliothèque [index].
/// [calculer] : `computeRecipe` par `evaluerRecette`, avec l'équipement de
/// l'éditeur.
Apercu calculerApercu({
  required RecipeContent brouillon,
  required Proposition proposition,
  required IndexImport index,
  required CalculsRecette Function(RecipeContent) calculer,
  required ErrorReportService errors,
}) {
  final operations = proposition.operations;
  List<LigneApercu> refus(List<RefusOperation> r) => [
    for (final f in r) _ligne(texteRefus(operations[f.index], f)),
  ];
  final Map<String, Object?> recipe;
  try {
    recipe = (brouillon.toFirestore(creation: true)['recipe']! as Map)
        .cast<String, Object?>();
  } catch (error, stackTrace) {
    errors.reportError(
      feature: 'recipes.assistant_proposition',
      error: error,
      stackTrace: stackTrace,
      context: 'brouillon illisible pour l\'aperçu : ${error.runtimeType}',
    );
    return const ApercuInvalide([]);
  }
  final r = appliquerProposition(
    recipe,
    brouillon.aiProposed,
    operations,
    bibliotheque: index,
  );
  switch (r) {
    case PropositionRefusee(:final refusOperations):
      return ApercuInvalide(refus(refusOperations));
    case PropositionAppliquee():
      final RecipeContent apres;
      try {
        apres = brouillon.avecProposition(r);
      } on DocumentIllisible catch (error, stackTrace) {
        // Recette relue par exchange/ mais hors de ce que lit l'éditeur.
        errors.reportError(
          feature: 'recipes.assistant_proposition',
          error: error,
          stackTrace: stackTrace,
          context: 'recette proposée illisible : ${error.field}',
        );
        return ApercuInvalide(refus(r.refusOperations));
      }
      final refusees = {for (final f in r.refusOperations) f.index};
      return ApercuPret(
        resultat: r,
        apres: apres,
        changements: lignesChangements(
          operations: operations,
          refusees: refusees,
          avant: brouillon,
          apres: apres,
        ),
        calculs: lignesCalculs(calculer(brouillon), calculer(apres)),
        refus: refus(r.refusOperations),
        valeursIa: r.marques
            .where((m) => !brouillon.aiProposed.contains(m))
            .length,
      );
  }
}

// --- Carte -------------------------------------------------------------------

/// Carte d'une proposition, sous la réponse qui la porte.
class CarteProposition extends StatefulWidget {
  const CarteProposition({
    super.key,
    required this.recue,
    required this.brouillon,
    required this.index,
    required this.calculer,
    required this.errors,
    required this.etat,
    required this.onAppliquer,
    required this.onAnnuler,
  });

  final PropositionRecue recue;

  /// Brouillon actuel de l'éditeur, lu à chaque construction.
  final RecipeContent? Function() brouillon;

  /// Bibliothèque entière (malts, houblons, ajouts, levures) ; `null` : une
  /// liste n'a pas pu être lue. [relire] : « Réessayer ».
  final Future<IndexImport?> Function({bool relire}) index;
  final CalculsRecette Function(RecipeContent) calculer;
  final ErrorReportService errors;
  final EtatApplication? etat;
  final void Function(ApercuPret apercu) onAppliquer;
  final VoidCallback onAnnuler;

  @override
  State<CarteProposition> createState() => _CartePropositionState();
}

class _CartePropositionState extends State<CarteProposition> {
  late Future<IndexImport?> _index = widget.index();
  bool? _deplie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final proposition = widget.recue.proposition;
    return SelectionContainer.disabled(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextesProposition.titre,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            if (proposition == null)
              const Encadre(
                ton: TonEncadre.avertissement,
                icone: Icons.warning_amber_outlined,
                child: Text(TextesProposition.ecartee),
              )
            else
              ..._corps(context, proposition),
          ],
        ),
      ),
    );
  }

  List<Widget> _corps(BuildContext context, Proposition proposition) {
    final theme = Theme.of(context);
    // Deux lignes au plus, sauf détail déplié.
    Text resumeDe({required bool entier}) => Text(
      proposition.resume,
      maxLines: entier ? null : 2,
      overflow: entier ? null : TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium,
    );
    final resume = resumeDe(entier: false);
    switch (widget.etat) {
      case EtatApplication.appliquee:
        return [
          resume,
          const SizedBox(height: 8),
          const Text(TextesProposition.appliquee),
          const SizedBox(height: 8),
          _boutons([
            OutlinedButton(
              onPressed: widget.onAnnuler,
              child: const Text(TextesProposition.annuler),
            ),
          ]),
        ];
      case EtatApplication.remplacee:
        return [
          resume,
          const SizedBox(height: 8),
          const Text(TextesProposition.remplacee),
        ];
      case EtatApplication.annulee || null:
        break;
    }
    Widget avecResume(Widget corps) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [resume, const SizedBox(height: 8), corps],
    );
    const preparation = Row(
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Flexible(child: Text(TextesProposition.preparation)),
      ],
    );
    return [
      FutureBuilder<IndexImport?>(
        future: _index,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return avecResume(preparation);
          }
          final index = snapshot.data;
          if (index == null) {
            return avecResume(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Encadre(
                    ton: TonEncadre.erreur,
                    icone: Icons.error_outline,
                    liveRegion: true,
                    child: Text(TextesProposition.bibliothequeIllisible),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () =>
                        setState(() => _index = widget.index(relire: true)),
                    child: const Text(TextesProposition.reessayer),
                  ),
                ],
              ),
            );
          }
          final brouillon = widget.brouillon();
          // L'éditeur n'a pas encore construit son brouillon.
          if (brouillon == null) return avecResume(preparation);
          final perimee =
              widget.recue.empreinte !=
              empreinteBrouillon(brouillon, widget.errors);
          final deplie = _deplie ?? perimee;
          return _apercu(
            context,
            resumeDe(entier: deplie),
            calculerApercu(
              brouillon: brouillon,
              proposition: proposition,
              index: index,
              calculer: widget.calculer,
              errors: widget.errors,
            ),
            perimee: perimee,
          );
        },
      ),
    ];
  }

  Widget _boutons(List<Widget> boutons) =>
      Wrap(spacing: 8, runSpacing: 8, children: boutons);

  Widget _liste(BuildContext context, String titre, List<LigneApercu> l) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(titre, style: theme.textTheme.labelLarge),
        ),
        for (final ligne in l)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              label: ligne.lecture,
              excludeSemantics: true,
              child: Text(ligne.texte),
            ),
          ),
      ],
    );
  }

  Widget _apercu(
    BuildContext context,
    Widget resume,
    Apercu apercu, {
    required bool perimee,
  }) {
    final theme = Theme.of(context);
    switch (apercu) {
      case ApercuInvalide(:final refus):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resume,
            const SizedBox(height: 8),
            const Encadre(
              ton: TonEncadre.erreur,
              icone: Icons.error_outline,
              child: Text(TextesProposition.invalide),
            ),
            if (refus.isNotEmpty)
              _liste(context, TextesProposition.refuses, refus),
          ],
        );
      case ApercuPret(:final changements, :final refus)
          when changements.isEmpty:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resume,
            const SizedBox(height: 8),
            const Encadre(
              ton: TonEncadre.avertissement,
              icone: Icons.warning_amber_outlined,
              child: Text(TextesProposition.aucunChangement),
            ),
            _liste(context, TextesProposition.refuses, refus),
          ],
        );
      case ApercuPret():
        final deplie = _deplie ?? perimee;
        final changes = [
          for (final c in apercu.calculs)
            if (c.change) c.ligne,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resume,
            const SizedBox(height: 8),
            if (perimee) ...[
              const Encadre(
                ton: TonEncadre.avertissement,
                icone: Icons.warning_amber_outlined,
                // Pas de région annoncée : l'avertissement paraît à chaque
                // frappe dans le brouillon.
                child: Text(TextesProposition.perimee),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.etat == EtatApplication.annulee) ...[
              const Text(TextesProposition.annulee),
              const SizedBox(height: 8),
            ],
            Text(
              TextesProposition.compte(
                changements: apercu.changements.length,
                valeursIa: apercu.valeursIa,
                refuses: apercu.refus.length,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!deplie)
              for (final l in changes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Semantics(
                    label: l.lecture,
                    excludeSemantics: true,
                    child: Text(l.texte),
                  ),
                ),
            if (deplie) ...[
              _liste(
                context,
                TextesProposition.changements,
                apercu.changements,
              ),
              _liste(context, TextesProposition.calculs, [
                for (final c in apercu.calculs) c.ligne,
              ]),
              if (apercu.refus.isNotEmpty)
                _liste(context, TextesProposition.refuses, apercu.refus),
            ],
            const SizedBox(height: 12),
            _boutons([
              FilledButton(
                onPressed: () => widget.onAppliquer(apercu),
                child: const Text(TextesProposition.appliquer),
              ),
              TextButton(
                onPressed: () => setState(() => _deplie = !deplie),
                child: Text(
                  deplie
                      ? TextesProposition.masquerDetail
                      : TextesProposition.voirDetail,
                ),
              ),
            ]),
          ],
        );
    }
  }
}
