import 'package:brewing/brewing.dart' show MissingInputKind;
import 'package:exchange/exchange.dart';
import 'package:exchange/fiches.dart';

import '../../../core/presentation/formats.dart';
import '../../../core/services/error_report_service.dart';
import '../../costs/domain/cost_evaluation.dart';
import '../../costs/presentation/formats_cout.dart';
import '../../equipment/domain/equipment.dart';
import '../../recipes/presentation/libelles_echange.dart';
import '../../recipes/presentation/recipe_calculations_view.dart';
import '../data/execution_import.dart';
import '../domain/fiches_a_importer.dart';

/// Libellés d'Admin › Import (v0.6, proposition d'écran validée). Un texte
/// tiré du fichier s'affiche en texte simple (P9). Les montants ne paraissent
/// que dans la rubrique « Coût », lue par l'administrateur seul (CO5) : jamais
/// dans une annonce ni dans un rapport d'erreur.
abstract final class TextesImportFiches {
  static const titre = 'Importer les fiches Excel';
  static const aide =
      'Choisissez le fichier JSON préparé à partir des fiches Excel. 10 Mo au '
      'plus. Rien n\'est écrit avant votre confirmation.';
  static const choisir = 'Choisir le fichier';
  static const choisirAutre = 'Choisir un autre fichier';
  static const horsLigne =
      'Import impossible hors ligne. Reconnectez-vous pour analyser le '
      'fichier.';
  static const horsLigneImport =
      'Import impossible hors ligne. Reconnectez-vous pour importer les fiches '
      'cochées.';
  static const reessayer = 'Réessayer';
  static const relancer = 'Relancez l\'import du même fichier pour reprendre.';
  static const tropGros = 'Ce fichier dépasse 10 Mo.';
  static const pasUnFichier =
      'Ce fichier n\'est pas un fichier de fiches Kass\'Beer. Choisissez le '
      'fichier JSON préparé.';
  static const versionInconnue =
      'Ce fichier est d\'un format que cette version ne lit pas. Faites-le '
      'préparer de nouveau.';
  static const tropDeFiches =
      'Ce fichier contient plus de $kMaxFiches fiches. Faites-le préparer de '
      'nouveau.';
  static String identifiantEnDouble(String id) =>
      'Deux fiches de ce fichier portent l\'identifiant « $id ». Faites-le '
      'préparer de nouveau.';
  static const vide = 'Ce fichier ne contient aucune fiche.';
  static const lecture = 'Lecture du fichier';
  static const comparaison = 'Comparaison avec les données déjà enregistrées';
  static const erreurServeur =
      'Impossible de vérifier ce qui est déjà importé. Vérifiez la connexion.';
  static const rienAEcrire =
      'Toutes les fiches de ce fichier sont déjà importées. Rien à écrire.';
  static const rienDeNouveau =
      'Rien de nouveau à importer. Cochez « Remplacer » pour réécrire une '
      'fiche modifiée.';
  static const remplacerCeBrassin = 'Remplacer ce brassin';
  static const supprimes = 'Supprimés';
  static const aucuneCochee = 'Cochez au moins une fiche.';
  static const detail = 'Détail';
  static const termine = 'Import terminé';
  static const voirBrassins = 'Voir les brassins';
  static const revenir = 'Revenir à l\'administration';
  static const aRevoir = 'Fiches à revoir';
  static const ignorees = 'Ignorées';
  static const enErreur = 'En erreur';
  static const arreterTitre = 'Arrêter l\'import ?';
  static const arreterTexte =
      'La fiche en cours sera reprise au prochain import du même fichier.';
  static const continuer = 'Continuer l\'import';
  static const arreter = 'Arrêter';

  static String importer(int n) =>
      n == 1 ? 'Importer 1 fiche' : 'Importer $n fiches';
  static String remplacer(int n) =>
      n == 1 ? 'Remplacer 1 fiche' : 'Remplacer $n fiches';

  /// Titre de la confirmation : « Importer 14 fiches ? », « Importer 14 fiches
  /// et en remplacer 2 ? », « Remplacer 16 brassins ? ».
  static String confirmationTitre(int imports, {int remplacements = 0}) {
    if (imports == 0) {
      return remplacements == 1
          ? 'Remplacer 1 brassin ?'
          : 'Remplacer $remplacements brassins ?';
    }
    final importer = imports == 1
        ? 'Importer 1 fiche'
        : 'Importer $imports fiches';
    return remplacements == 0
        ? '$importer ?'
        : '$importer et en remplacer $remplacements ?';
  }

  /// Bouton de la confirmation : « Importer », « Importer et remplacer »,
  /// « Remplacer ».
  static String confirmationBouton(int imports, int remplacements) =>
      imports == 0
      ? 'Remplacer'
      : remplacements == 0
      ? 'Importer'
      : 'Importer et remplacer';

  /// « 2 brassins seront remplacés. Leurs étapes, … perdues. »
  static String remplacements(int n) =>
      '${n == 1 ? '1 brassin sera remplacé. Ses' : '$n brassins seront remplacés. Leurs'} '
      'étapes, ${n == 1 ? 'ses' : 'leurs'} mesures et ${n == 1 ? 'son coût figé seront supprimés' : 'leurs coûts figés seront supprimés'} '
      'puis écrits de nouveau. Les heures corrigées depuis l\'import seront '
      'perdues.';

  /// Paragraphe de la confirmation : écritures, puis remplacements.
  static String confirmationRemplacement({
    required int brassins,
    required int recettes,
    required int remplacementsN,
  }) {
    if (brassins == 0) return remplacements(remplacementsN);
    final b = _n(brassins, 'brassin', 'brassins');
    final quoi = recettes == 0
        ? b
        : '$b et ${_n(recettes, 'recette', 'recettes')}';
    final pluriel = brassins + recettes > 1;
    final ecrits = pluriel
        ? '$quoi seront écrits sous votre compte.'
        : '$quoi sera écrit sous votre compte.';
    final visibles = brassins + remplacementsN > 1
        ? 'Ils seront visibles du groupe.'
        : 'Il sera visible du groupe.';
    return '$ecrits ${remplacements(remplacementsN)} $visibles Les coûts '
        'restent privés.';
  }

  /// « 16 brassins et 15 recettes seront écrits sous votre compte. »
  static String confirmation(int brassins, int recettes) {
    final b = _n(brassins, 'brassin', 'brassins');
    final pluriel = brassins + recettes > 1;
    final quoi = recettes == 0
        ? b
        : '$b et ${_n(recettes, 'recette', 'recettes')}';
    return pluriel
        ? '$quoi seront écrits sous votre compte. Ils seront visibles du '
              'groupe. Les coûts restent privés.'
        : '$quoi sera écrit sous votre compte. Il sera visible du groupe. Les '
              'coûts restent privés.';
  }

  /// En-tête de l'analyse (EC3).
  static String resume({
    required int fiches,
    required int recettes,
    required int brassins,
    required int mesures,
    required int couts,
  }) => [
    _n(fiches, 'fiche', 'fiches'),
    _n(recettes, 'recette', 'recettes'),
    _n(brassins, 'brassin', 'brassins'),
    '$mesures ${mesures > 1 ? 'heures et mesures' : 'heure ou mesure'}',
    _n(couts, 'coût figé', 'coûts figés'),
  ].join(' · ');

  /// Comptes par état, sans les compteurs à zéro.
  static String comptes(Map<EtatFiche, int> n) => [
    for (final e in EtatFiche.values)
      if ((n[e] ?? 0) > 0) _compteEtat(e, n[e]!),
  ].join(' · ');

  static String _compteEtat(EtatFiche e, int n) => switch (e) {
    EtatFiche.nouvelle => _n(n, 'nouvelle', 'nouvelles'),
    EtatFiche.aCompleter => '$n à compléter',
    EtatFiche.remplacementATerminer =>
      '$n remplacement${n > 1 ? 's' : ''} à terminer',
    EtatFiche.dejaImportee => _n(n, 'déjà importée', 'déjà importées'),
    EtatFiche.contenuDifferent => '$n au contenu différent',
    EtatFiche.refusee => _n(n, 'refusée', 'refusées'),
  };

  static String etat(EtatFiche e) => switch (e) {
    EtatFiche.nouvelle => 'Nouvelle',
    EtatFiche.aCompleter => 'À compléter',
    EtatFiche.remplacementATerminer => 'Remplacement à terminer',
    EtatFiche.dejaImportee => 'Déjà importée',
    EtatFiche.contenuDifferent => 'Déjà importée, contenu différent',
    EtatFiche.refusee => 'Refusée',
  };

  static String? explication(EtatFiche e) => switch (e) {
    EtatFiche.aCompleter =>
      'Import commencé et non terminé : seul ce qui manque sera écrit.',
    EtatFiche.remplacementATerminer =>
      'Remplacement commencé et non terminé : l\'import le terminera.',
    EtatFiche.contenuDifferent => 'Le fichier a changé depuis l\'import.',
    _ => null,
  };

  /// « Fiche 4 sur 16 · Ale blonde », « … · Ale blonde · remplacement ».
  static String progression(
    int fiche,
    int fiches,
    String nom, {
    bool remplacement = false,
  }) => nom.isEmpty
      ? 'Fiche $fiche sur $fiches'
      : 'Fiche $fiche sur $fiches · $nom${remplacement ? ' · remplacement' : ''}';
  static String ecritures(int faites, int total) =>
      '$faites écriture${faites > 1 ? 's' : ''} sur $total';
  static const enCours = 'Import en cours';

  static const arrete = 'Import arrêté';

  /// « Import terminé · 12 créées · 2 remplacées · 2 ignorées · 0 en
  /// erreur », sans « remplacées » quand aucune fiche n'est remplacée ;
  /// « Import arrêté · … » après une perte de connexion ou un accusé absent
  /// ([arret]).
  static String bilan(
    int creees,
    int ignorees,
    int erreurs, {
    int remplacees = 0,
    bool arret = false,
  }) =>
      '${arret ? arrete : termine} · '
      '${_comptesBilan(creees, remplacees, ignorees, erreurs)}';
  static String bilanParle(
    int creees,
    int ignorees,
    int erreurs, {
    int remplacees = 0,
    bool arret = false,
  }) =>
      '${arret ? arrete : termine}. '
      '${_comptesBilan(creees, remplacees, ignorees, erreurs).replaceAll(' · ', ', ')}.';

  static String _comptesBilan(
    int creees,
    int remplacees,
    int ignorees,
    int erreurs,
  ) => [
    _n(creees, 'créée', 'créées'),
    if (remplacees > 0) _n(remplacees, 'remplacée', 'remplacées'),
    _n(ignorees, 'ignorée', 'ignorées'),
    '$erreurs en erreur',
  ].join(' · ');

  /// « Ale blonde (2024-07-14-ale-blonde) : 34 heures et mesures, 1 coût
  /// figé ».
  static String supprime(
    String nom,
    String ficheId,
    int evenements,
    bool cout,
  ) =>
      '$nom ($ficheId) : $evenements '
      '${evenements > 1 ? 'heures et mesures' : 'heure ou mesure'}'
      '${cout ? ', 1 coût figé' : ''}';

  static const nonCocheeDifferente = 'Non cochée : contenu différent';

  static String connexionPerdue(int fiche, int fiches) =>
      'Connexion perdue. Import arrêté à la fiche $fiche sur $fiches. '
      'Reconnectez-vous puis choisissez de nouveau le fichier : les fiches '
      'commencées seront reprises.';

  static const nonTraitee = 'Non traitée : import arrêté';

  /// « Ale blonde (2024-07-14-ale-blonde) — événements, lot 3 : écriture
  /// refusée. Relancez l'import du même fichier pour reprendre. »
  static String erreur(String nom, String ficheId, FicheEnErreur e) =>
      '$nom ($ficheId) — ${e.etape.libelle}'
      '${e.lot == null ? '' : ', lot ${e.lot}'} : ${_code(e.code)}. $relancer';

  /// Fiche interrompue par la perte de la connexion ou un accusé absent.
  static String interrompue(String nom, String ficheId) =>
      '$nom ($ficheId) — réseau indisponible. $relancer';

  static String _code(String code) => switch (code) {
    'permission-denied' => 'écriture refusée',
    'unavailable' => 'réseau indisponible',
    _ => code,
  };
}

String _n(int n, String singulier, String pluriel) =>
    '$n ${n > 1 ? pluriel : singulier}';

/// Raison d'une fiche refusée, après « Refusée : ».
String libelleRefusImport(RefusImport refus) => switch (refus) {
  RefusDeLecture(:final refus) => _refusLecture(refus),
  RecetteNonRelue() => 'recette illisible après lecture.',
  DocumentDUnAutreMembre() =>
    'un autre membre a déjà une recette ou un brassin à cet identifiant.',
};

String _refusLecture(RefusFiche r) {
  final champ = r.chemin.isEmpty ? 'entrée' : r.chemin;
  return switch (r.code) {
    CodeRefusFiche.champInconnu => 'champ inconnu ($champ).',
    CodeRefusFiche.champAbsent => 'champ absent ($champ).',
    CodeRefusFiche.typeInattendu => 'valeur illisible ($champ).',
    CodeRefusFiche.horsBornes => 'valeur hors limites ($champ).',
    CodeRefusFiche.formatInvalide => 'valeur mal écrite ($champ).',
    CodeRefusFiche.enDouble => 'identifiant en double ($champ).',
    CodeRefusFiche.debutEnDouble => 'deux débuts pour la même étape ($champ).',
    CodeRefusFiche.heuresHorsOrdre =>
      'heure antérieure à celle d\'une étape précédente ($champ).',
    CodeRefusFiche.heureEnTrop =>
      'heure écrite pour une heure estimée ($champ).',
    CodeRefusFiche.etapeInconnue => 'étape inconnue ($champ).',
    CodeRefusFiche.evenementInconnu => 'mesure retenue introuvable ($champ).',
    CodeRefusFiche.adresseWeb => 'adresse web dans un texte ($champ).',
    CodeRefusFiche.montant =>
      'montant dans un texte lu par le groupe ($champ).',
    CodeRefusFiche.recetteAbsente => 'recette absente du fichier.',
    CodeRefusFiche.recetteRefusee =>
      'recette refusée : ${r.refusRecette == null ? 'illisible.' : libelleRefus(r.refusRecette!)}',
    CodeRefusFiche.recetteIncoherente =>
      'même recette qu\'une fiche précédente, contenu différent.',
  };
}

/// Une rubrique du détail d'une fiche (EC5).
typedef Rubrique = ({String titre, List<String> lignes});

/// Rubriques du détail de [f], dans l'ordre de la proposition d'écran ; une
/// rubrique vide est absente. [nomEnDouble] : une autre recette de
/// l'administrateur porte ce nom.
List<Rubrique> rubriquesDe(
  FicheAImporter f, {
  required bool nomEnDouble,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  final fiche = f.fiche;
  final recette = f.recette;
  if (fiche == null || recette == null) return const [];
  final rubriques = <Rubrique>[
    if (nomEnDouble)
      (
        titre: 'Nom en double',
        lignes: ['Une de vos recettes s\'appelle déjà « ${recette.name} ».'],
      ),
    (
      titre: 'À compléter dans la recette',
      lignes: _aCompleter(f, errors, reported),
    ),
    (titre: 'Divergences', lignes: fiche.divergences),
    (
      titre: 'Corrections validées',
      lignes: [
        for (final c in fiche.corrections)
          '${c.sujet} : ${c.valeurFiche} → ${c.valeurImportee}. ${c.raison}',
      ],
    ),
    (
      titre: 'Valeurs déduites',
      lignes: [
        ...fiche.deductions,
        for (final m in f.modifications)
          if (_deduite(m)) libelleModification(m),
      ],
    ),
    (
      titre: 'Reprises de la Bibliothèque',
      lignes: [for (final r in f.reprises) libelleModification(r)],
    ),
    (titre: 'Heures estimées', lignes: heuresEstimees(f)),
    (
      titre: 'Non importé',
      lignes: [
        ...fiche.nonImporte,
        for (final m in f.modifications)
          if (!_deduite(m) && m is! ValeurReprise) libelleModification(m),
      ],
    ),
    (titre: 'Coût', lignes: lignesCout(f.cout)),
  ];
  return [
    for (final r in rubriques)
      if (r.lignes.isNotEmpty) r,
  ];
}

/// Vrai pour une modification de lecture qui garde la valeur sous une autre
/// forme (unité convertie, durée arrondie, moment ou style simplifié, texte
/// coupé) : « Valeurs déduites ». Parties non importées, valeurs rejetées,
/// champs inconnus et caractères retirés : « Non importé ». Une
/// [ValeurReprise] n'est créée que par `completerRecette`, dans
/// `FicheAImporter.reprises` (« Reprises de la Bibliothèque ») : la lecture de
/// la recette n'en met aucune dans `modifications`, et « Non importé » l'écarte.
bool _deduite(Modification m) => switch (m) {
  UnitesConverties() ||
  DureeArrondie() ||
  StyleReduitAuNom() ||
  TexteCoupe() ||
  MomentSimplifie() ||
  FirstWortEnEbullition() ||
  ArretDuFeuSansDuree() ||
  AromaEnEbullition() => true,
  PartiesNonImportees() ||
  ValeurRejetee() ||
  CaracteresRetires() ||
  ChampsInconnus() ||
  ValeurReprise() => false,
};

/// Données que `brewing/` attend pour calculer la recette, avec la copie
/// d'équipement neutre du brassin (EQ3).
List<String> _aCompleter(
  FicheAImporter f,
  ErrorReportService errors,
  Set<String> reported,
) {
  final fiche = f.fiche!;
  final recette = f.recette!;
  final equipement = EquipementConnu(
    Equipment(
      id: '',
      ownerUid: '',
      content: EquipmentContent(
        name: fiche.brassin.equipementNom,
        kind: fiche.brassin.equipementType == TypeEquipementFiche.toutEnUn
            ? EquipmentKind.allInOne
            : EquipmentKind.multiVessel,
      ),
    ),
  );
  return switch (evaluerRecette(
    recette,
    equipement,
    errors: errors,
    reported: reported,
    recipeKey: 'import-fiche:${fiche.ficheId}',
  )) {
    CalculsObtenus(:final calculation) => [
      for (final m in calculation.missingInputs)
        if (m.kind != MissingInputKind.originalGravity)
          libelleManque(m, equipement, content: recette),
    ],
    CalculsImpossibles(:final field) => [messageCalculImpossible(field)],
  };
}

/// Heures non notées dans la fiche : estimées par le lecteur ou datées par la
/// préparation (CR4, CR5, CR6, CR12). Écrites avec `time_estimated`.
List<String> heuresEstimees(FicheAImporter f) {
  final fiche = f.fiche;
  if (fiche == null) return const [];
  int n(OrigineHeure o) =>
      fiche.evenements.where((e) => e.origineHeure == o).length;
  final estimee = n(OrigineHeure.estimee);
  final midi = n(OrigineHeure.midi);
  final j28 = n(OrigineHeure.estimeeJ28);
  return [
    if (f.brassageDateParLePlan)
      'Aucune heure notée : brassage daté de l\'heure de début prévue.',
    if (estimee > 0)
      'Heure non notée : estimée d\'après la chronologie ($estimee).',
    if (midi > 0) 'Relevé sans heure : daté de 12:00 ($midi).',
    for (var i = 0; i < j28; i++)
      'Relevé sans date : daté de 28 jours après le brassage.',
  ];
}

/// Nombre d'heures estimées de [f].
int nombreHeuresEstimees(FicheAImporter f) {
  final fiche = f.fiche;
  if (fiche == null) return 0;
  return fiche.evenements.where((e) => e.heureEstimee).length +
      (f.brassageDateParLePlan ? 1 : 0);
}

/// Rubrique « Coût » : montants pour l'administrateur seul (CO5).
List<String> lignesCout(CoutDeFiche cout) {
  const rattrapage = 'Vous pourrez le figer depuis le brassin.';
  String? ecart(double? fiche, double calcule) {
    if (fiche == null || formatEuros(fiche) == formatEuros(calcule)) {
      return null;
    }
    return 'Écart avec la fiche : ${formatEuros(fiche)} dans la fiche, '
        '${formatEuros(calcule)} recalculé.';
  }

  return switch (cout) {
    SansPrix() => ['Coût non figé : la fiche ne donne aucun prix. $rattrapage'],
    CoutCalcule(:final cout, :final totalFicheEur) => [
      'Coût figé : ${formatEuros(cout.totalEur)}',
      ?ecart(totalFicheEur, cout.totalEur),
    ],
    CoutImpossible(:final raisons) => [
      'Coût non figé : ${raisons.map(_raison).join(', ')}. $rattrapage',
    ],
  };
}

String _raison(RaisonCout r) => switch (r) {
  PrixManquant(:final ingredient) => 'prix manquant pour ${ingredient.name}',
  PrixUniteIncompatible(:final ingredient) =>
    'unité du prix de ${ingredient.name} différente de la recette',
  PrixIllisible(:final ingredient) => 'prix illisible pour ${ingredient.name}',
  QuantitesDeDeuxUnites(:final name) => '$name compté en grammes et en litres',
  BouteillesNonRenseignees() =>
    'nombre de bouteilles absent avec un frais par bouteille',
  LigneSansNom() => 'une ligne sans nom',
  AucunIngredient() => 'aucun ingrédient',
  SucreResucrageSansNature() => 'sucre de resucrage sans nature',
  VolumeNonRenseigne() => 'volume non renseigné',
  FraisIllisible() => 'frais illisible',
  PrixIndisponiblesHorsLigne() => 'prix indisponibles',
  CalculImpossible() => 'calcul impossible',
};

/// « 3 divergences · 1 correction · 2 heures estimées · 1 à compléter ».
String pointsARevoir(FicheAImporter f, List<Rubrique> rubriques) {
  final fiche = f.fiche;
  if (fiche == null) return '';
  final aCompleter = [
    for (final r in rubriques)
      if (r.titre == 'À compléter dans la recette') ...r.lignes,
  ].length;
  final heures = nombreHeuresEstimees(f);
  return [
    if (fiche.divergences.isNotEmpty)
      _n(fiche.divergences.length, 'divergence', 'divergences'),
    if (fiche.corrections.isNotEmpty)
      _n(fiche.corrections.length, 'correction', 'corrections'),
    if (heures > 0) _n(heures, 'heure estimée', 'heures estimées'),
    if (aCompleter > 0) '$aCompleter à compléter',
  ].join(' · ');
}

/// Nombre de points à revoir, pour le lecteur d'écran.
int nombrePointsARevoir(FicheAImporter f, List<Rubrique> rubriques) {
  final fiche = f.fiche;
  if (fiche == null) return 0;
  return fiche.divergences.length +
      fiche.corrections.length +
      nombreHeuresEstimees(f) +
      [
        for (final r in rubriques)
          if (r.titre == 'À compléter dans la recette') ...r.lignes,
      ].length;
}

/// Date du brassage affichée : « 14 juil. 2024 » ; parlée : « 14 juillet
/// 2024 ».
String dateDeFiche(FicheLue fiche) =>
    formatDateCourte(fiche.brassin.plannedFor.toLocal());
String dateDeFicheParlee(FicheLue fiche) =>
    formatDateLongue(fiche.brassin.plannedFor.toLocal());
