import 'package:brewing/brewing.dart';

import '../bornes.dart';
import '../lecture_beerjson.dart' show kNomEmpatage;
import '../texte.dart';
import 'cles.dart';
import 'referentiel.dart';
import 'resolution.dart';
import 'sources.dart';
import 'valeurs.dart';

/// Lecture d'une recette DIY Dog (`alxiw/punkapi`, `e6c12ab`) vers un
/// document `public_recipes/diydog-{id}` (`DATA_SOURCES.md`, « Correspondance
/// DIY Dog » ; spécification de L3). `recipe` ne porte que les clés que
/// `isBeerJsonRecipe` de `firestore.rules` accepte : « Dupliquer » le copie
/// tel quel vers `recipes/`. Les valeurs annoncées vivent dans `announced`.
/// Aucun texte libre n'est lu, sauf `method.twist` (`recipe.notes`).

/// Auteur écrit dans `recipe.author`.
const kAuteurDiyDog = 'BrewDog';

/// Longueur maximale d'un libellé de `source_hop_timing`.
const kMaxLibelleMoment = 40;

/// Ligne d'une recette écartée : moment ou unité inconnus.
class LigneRejetee {
  /// Crée le rejet.
  const LigneRejetee(this.recette, this.liste, this.nom, this.raison);

  /// Identifiant de la recette.
  final String recette;

  /// Liste de la source (`malt`, `hops`, `yeast`, `mash_temp`).
  final String liste;

  /// Nom de la ligne, ou `null`.
  final String? nom;

  /// Raison.
  final String raison;

  /// Ligne du rapport.
  Map<String, Object> toJson() => {
    'recette': recette,
    'liste': liste,
    'nom': ?nom,
    'raison': raison,
  };
}

/// Compte de résolution d'une nature.
class CompteResolution {
  /// Lignes lues.
  int lignes = 0;

  /// Lignes résolues, par étape.
  final Map<EtapeResolution, int> parEtape = {
    for (final e in EtapeResolution.values) e: 0,
  };

  /// Noms non résolus : clé normalisée → (nom lu, nombre de lignes).
  final Map<String, ({String nom, int lignes})> nonResolus = {};

  /// Lignes résolues sans la table d'alias.
  int get avantAlias =>
      parEtape[EtapeResolution.exacte]! + parEtape[EtapeResolution.souche]!;

  /// Lignes résolues.
  int get resolues => avantAlias + parEtape[EtapeResolution.alias]!;

  /// Lignes non résolues.
  int get lignesNonResolues => lignes - resolues;
}

/// Moment d'un ajout de la liste `hops`.
typedef _Moment = ({Map<String, Object>? timing, bool libelle, String? rejet});

/// Conversion des recettes DIY Dog : documents, comptes de résolution,
/// valeurs recopiées (D4) et lignes rejetées.
class ConversionDiyDog {
  /// Crée la conversion.
  ConversionDiyDog(this.resolveur);

  /// Résolveur des noms.
  final Resolveur resolveur;

  /// Comptes par nature.
  final Map<NatureReferentiel, CompteResolution> comptes = {
    for (final n in NatureReferentiel.values) n: CompteResolution(),
  };

  /// Valeurs recopiées de l'entrée résolue (D4), par champ.
  final Map<String, int> recopiees = {};

  /// Lignes rejetées.
  final List<LigneRejetee> lignesRejetees = [];

  /// Recettes refusées : identifiant ou fichier, et raison.
  final List<Map<String, Object>> recettesRefusees = [];

  /// Valeurs écartées.
  final Journal journal = Journal();

  /// Libellés d'origine perdus sur une ligne de la liste `hops` placée en
  /// `miscellaneous_additions` : `source_hop_timing` ne vise que les houblons.
  int libellesAjoutsPerdus = 0;

  /// Température de fermentation lue et non reprise : `recipe` n'a pas de
  /// `fermentation` (`firestore.rules`).
  int fermentationsNonReprises = 0;

  void _recopie(String champ) => recopiees[champ] = (recopiees[champ] ?? 0) + 1;

  Resolution? _resoudre(NatureReferentiel nature, String nom) {
    final compte = comptes[nature]!;
    compte.lignes++;
    final r = resolveur.resoudre(nature, nom);
    if (r != null) {
      compte.parEtape[r.etape] = compte.parEtape[r.etape]! + 1;
    } else {
      final cle = cleNormalisee(nom);
      final avant = compte.nonResolus[cle];
      compte.nonResolus[cle] = (
        nom: avant?.nom ?? nom,
        lignes: (avant?.lignes ?? 0) + 1,
      );
    }
    return r;
  }

  /// Convertit [brut], le contenu d'un fichier `data/NNN.json` nommé
  /// [fichier] ; `null` si la recette est refusée (comptée).
  ({String id, Map<String, Object?> document})? convertir(
    Object? brut,
    String fichier,
  ) {
    if (brut is! Map) {
      recettesRefusees.add({'fichier': fichier, 'raison': 'objet attendu'});
      return null;
    }
    final numero = brut['id'];
    final nomRecette = nomPropre(brut['name']);
    if (numero is! int ||
        numero < 1 ||
        nomRecette == null ||
        nomDeRecherche(nomRecette).isEmpty) {
      recettesRefusees.add({'fichier': fichier, 'raison': 'id ou nom absent'});
      return null;
    }
    final id = idRecetteDiyDog(numero);
    final v = LecteurValeurs(journal, Source.diydog.id, id);
    final refs = <String, String>{};
    final ingredients = brut['ingredients'] is Map
        ? brut['ingredients'] as Map
        : const <Object?, Object?>{};
    final method = brut['method'] is Map
        ? brut['method'] as Map
        : const <Object?, Object?>{};

    // Malts.
    final malts = <Map<String, Object?>>[];
    for (final l in _lignes(ingredients['malt'])) {
      final nom = nomPropre(l['name']);
      final masse = _grammes(l['amount']);
      final rejet = nom == null || !isValidIngredientName(nom)
          ? 'nom absent'
          : masse.rejet;
      if (rejet != null) {
        lignesRejetees.add(LigneRejetee(id, 'malt', nom, rejet));
        continue;
      }
      // Type : celui de l'entrée résolue (miel, dextrose, lactose…) ; sans
      // entrée, `grain`, car la source range la ligne dans `malt` sans autre
      // précision.
      final ligne = <String, Object?>{
        'name': nom,
        'type': 'grain',
        'amount': couple(masse.grammes!, 'g'),
      };
      final r = _resoudre(NatureReferentiel.fermentable, nom!);
      if (r != null) {
        final e = resolveur.referentiel.entree(r.id)!.principale.valeurs;
        final type = e['type'];
        if (type is String) {
          ligne['type'] = type;
          _recopie('fermentable.type');
        }
        final rendement = e['yield'];
        if (rendement is Map && rendement['fine_grind'] != null) {
          ligne['yield'] = {'fine_grind': rendement['fine_grind']};
          _recopie('fermentable.yield');
        }
        if (e['color'] != null) {
          ligne['color'] = e['color'];
          _recopie('fermentable.color');
        }
        final nature = IngredientNature.ofFermentable(
          FermentableKind.ofType(ligne['type']! as String),
        );
        refs[ingredientKey(nature, nom)] = r.id;
      }
      malts.add(ligne);
    }

    // Houblons, et ajouts écrits dans la liste des houblons.
    final houblons = <Map<String, Object?>>[];
    final ajouts = <Map<String, Object?>>[];
    final moments = <Map<String, Object>>[];
    for (final l in _lignes(ingredients['hops'])) {
      final nom = nomPropre(l['name']);
      final masse = _grammes(l['amount']);
      final moment = _moment(l['add']);
      final rejet = nom == null || !isValidIngredientName(nom)
          ? 'nom absent'
          : (masse.rejet ?? moment.rejet);
      if (rejet != null) {
        lignesRejetees.add(LigneRejetee(id, 'hops', nom, rejet));
        continue;
      }
      // Un nom qui ne se résout pas en houblon et se résout en ajout est un
      // ajout ; un nom non résolu reste un houblon, sauf s'il est listé.
      final estAjout =
          resolveur.estAjoutDansHoublons(nom!) ||
          (resolveur.resoudre(NatureReferentiel.hop, nom) == null &&
              resolveur.resoudre(NatureReferentiel.misc, nom) != null);
      if (estAjout) {
        final timing = moment.timing!;
        final r = _resoudre(NatureReferentiel.misc, nom);
        if (moment.libelle) libellesAjoutsPerdus++;
        ajouts.add({
          'name': nom,
          'amount': couple(masse.grammes!, 'g'),
          // Un ajout en fermentation ne porte que `duration` (lecture de
          // l'application) : le jour d'ajout n'est pas repris.
          'timing': timing['use'] == 'add_to_fermentation'
              ? {'use': 'add_to_fermentation'}
              : timing,
        });
        if (r != null) {
          refs[ingredientKey(IngredientNature.addition, nom)] = r.id;
        }
        continue;
      }
      final r = _resoudre(NatureReferentiel.hop, nom);
      final ligne = <String, Object?>{
        'name': nom,
        'amount': couple(masse.grammes!, 'g'),
        'timing': moment.timing,
      };
      final alpha = _alphaDeLAttribut(l['attribute']);
      if (alpha != null) {
        ligne['alpha_acid'] = couple(alpha, '%');
      } else if (r != null) {
        final a = resolveur.referentiel.entree(r.id)!.principale.valeurs;
        if (a['alpha_acid'] != null) {
          ligne['alpha_acid'] = a['alpha_acid'];
          _recopie('hop.alpha_acid');
        }
      }
      if (r != null) refs[ingredientKey(IngredientNature.hop, nom)] = r.id;
      if (moment.libelle) {
        moments.add({
          'hop_index': houblons.length,
          'label': couper(
            nettoyerLigne('${l['add']}').texte,
            kMaxLibelleMoment,
          ),
        });
      }
      houblons.add(ligne);
    }

    // Levure : un texte, ou deux souches jointes par « & ».
    final levures = <Map<String, Object?>>[];
    final levure = ingredients['yeast'];
    if (levure is String) {
      for (final partie in levure.split(' & ')) {
        final nom = nomPropre(partie);
        if (nom == null || !isValidIngredientName(nom)) {
          lignesRejetees.add(LigneRejetee(id, 'yeast', nom, 'nom absent'));
          continue;
        }
        final ligne = <String, Object?>{'name': nom};
        final r = _resoudre(NatureReferentiel.culture, nom);
        if (r != null) {
          final c = resolveur.referentiel.entree(r.id)!.principale.valeurs;
          if (c['type'] != null) {
            ligne['type'] = c['type'];
            _recopie('culture.type');
          }
          if (c['form'] != null) {
            ligne['form'] = c['form'];
            _recopie('culture.form');
          }
          final attenuation = milieuDePlage(c['attenuation']);
          if (attenuation != null) {
            ligne['attenuation'] = couple(attenuation, '%');
            _recopie('culture.attenuation');
          }
          refs[ingredientKey(IngredientNature.yeast, nom)] = r.id;
        }
        levures.add(ligne);
      }
    } else if (levure != null) {
      lignesRejetees.add(LigneRejetee(id, 'yeast', null, 'valeur illisible'));
    }

    // Empâtage : un palier d'infusion par température.
    final paliers = <Map<String, Object?>>[];
    for (final p in _lignes(method['mash_temp'])) {
      final temp = p['temp'];
      final c = temp is Map && temp['unit'] == 'celsius'
          ? nombre(temp['value'])
          : null;
      if (c == null || c < kMinTemperaturePalier || c > kMaxTemperaturePalier) {
        lignesRejetees.add(
          LigneRejetee(
            id,
            'mash_temp',
            null,
            'température absente ou illisible',
          ),
        );
        continue;
      }
      // Un palier sans durée est écarté : `step_time` est obligatoire dans le
      // schéma partiel et dans la lecture de l'application.
      final duree = nombre(p['duration']);
      if (duree == null || duree < 0 || duree > kMaxDureePalier) {
        lignesRejetees.add(
          LigneRejetee(id, 'mash_temp', null, 'durée absente ou illisible'),
        );
        continue;
      }
      paliers.add({
        // Libellé : la source ne nomme pas ses paliers.
        'name': 'Palier ${paliers.length + 1}',
        'type': 'infusion',
        'step_temperature': couple(c, 'C'),
        'step_time': couple(duree.round(), 'min'),
      });
    }
    final fermentation = method['fermentation'];
    if (fermentation is Map && fermentation['temp'] is Map) {
      if (nombre((fermentation['temp'] as Map)['value']) != null) {
        fermentationsNonReprises++;
      }
    }

    for (final (liste, lignes) in [
      ('fermentable_additions', malts),
      ('hop_additions', houblons),
      ('miscellaneous_additions', ajouts),
      ('culture_additions', levures),
    ]) {
      if (lignes.length > kPlafondsListes[liste]!) {
        recettesRefusees.add({
          'recette': id,
          'raison': 'trop de lignes ($liste)',
        });
        return null;
      }
    }

    final volume = brut['volume'];
    final litres = volume is Map && volume['unit'] == 'litres'
        ? nombre(volume['value'])
        : null;
    if (litres == null || litres <= 0 || litres > kMaxVolumeBrassin) {
      v.ecarter('volume', 'unité inconnue, valeur illisible ou hors bornes');
    }
    final twist = method['twist'];
    final notes = twist is String
        ? couper(nettoyerNotes(twist).texte, kMaxNotes)
        : null;

    final recipe = <String, Object?>{
      'name': nomRecette,
      'author': kAuteurDiyDog,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (litres != null && litres > 0 && litres <= kMaxVolumeBrassin)
        'batch_size': couple(litres, 'l'),
      if (paliers.isNotEmpty)
        'mash': {'name': kNomEmpatage, 'mash_steps': paliers},
      'ingredients': {
        'fermentable_additions': malts,
        'hop_additions': houblons,
        'miscellaneous_additions': ajouts,
        'culture_additions': levures,
      },
    };

    final og = nombre(brut['target_og']);
    final fg = nombre(brut['target_fg']);
    final annonce = <String, Object?>{
      if (og != null) 'original_gravity': _densiteAnnoncee(v, 'target_og', og),
      if (fg != null) 'final_gravity': _densiteAnnoncee(v, 'target_fg', fg),
      'alcohol_by_volume': v.mesure(
        'abv',
        _brutEn(brut['abv'], '%'),
        Grandeur.pourcent,
      ),
      'ibu_estimate': v.mesure(
        'ibu',
        _brutEn(brut['ibu'], 'IBUs'),
        Grandeur.amertume,
      ),
      'color_estimate': v.mesure(
        'ebc',
        _brutEn(brut['ebc'], 'EBC'),
        Grandeur.couleur,
      ),
    }..removeWhere((_, valeur) => valeur == null);

    return (
      id: id,
      document: {
        'format_version': 1,
        'owner_uid': 'system',
        'owner_name': 'DIY Dog',
        'imported_from': 'DIY Dog · $id',
        'search_name': nomDeRecherche(nomRecette),
        'recipe': recipe,
        'ingredient_refs': refs,
        'source_hop_timing': moments,
        'announced': annonce,
        'provenance': [provenance(Source.diydog, '$numero', Licence.diyDog)],
      },
    );
  }

  /// Densité annoncée en points (`1042`), en SG (`1.042`), ou `null`.
  Map<String, Object>? _densiteAnnoncee(
    LecteurValeurs v,
    String champ,
    double points,
  ) {
    final sg = v.valeur(
      champ,
      arrondi(points / 1000, 4),
      'sg',
      Grandeur.densite,
    );
    return sg == null ? null : couple(sg, 'sg');
  }
}

/// Couple `{value, unit}` d'un nombre nu de la source, ou `null` s'il manque.
Map<String, Object?>? _brutEn(Object? valeur, String unite) =>
    valeur == null ? null : {'value': valeur, 'unit': unite};

/// Lignes d'une liste de la source : ses éléments objets.
Iterable<Map<Object?, Object?>> _lignes(Object? liste) =>
    liste is List ? liste.whereType<Map<Object?, Object?>>() : const [];

/// Grammes par unité de masse de DIY Dog.
const Map<String, double> _grammesPar = {
  'grams': 1,
  'gram': 1,
  'kilograms': 1000,
  'kilogram': 1000,
};

/// Masse en grammes d'une quantité de DIY Dog, ou la raison du rejet : unité
/// hors masse (`total`, `ml`), valeur illisible ou hors bornes.
({double? grammes, String? rejet}) _grammes(Object? quantite) {
  if (quantite is! Map) return (grammes: null, rejet: 'quantité absente');
  final par = _grammesPar[quantite['unit']];
  if (par == null) return (grammes: null, rejet: 'unité de quantité inconnue');
  final n = nombre(quantite['value']);
  if (n == null || n < 0) return (grammes: null, rejet: 'quantité illisible');
  final g = arrondi(n * par, 6);
  if (g > kMaxGrammesParLigne) {
    return (grammes: null, rejet: 'quantité hors bornes');
  }
  return (grammes: g, rejet: null);
}

/// Acide alpha donné par `attribute` sous la forme `10% Alpha`, ou `null`.
double? _alphaDeLAttribut(Object? attribut) {
  if (attribut is! String) return null;
  final m = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s*%\s*alpha\s*$',
    caseSensitive: false,
  ).firstMatch(attribut);
  final alpha = m == null ? null : double.tryParse(m[1]!);
  return alpha != null && alpha > 0 && alpha <= 100 ? alpha : null;
}

Map<String, Object> _minutes(int n) => couple(n, 'min');

/// Moment d'ajout `add` de DIY Dog (`DATA_SOURCES.md`, « Moment d'ajout du
/// houblon ») : `timing`, et vrai si le libellé d'origine dit ce que `timing`
/// ne dit pas (`source_hop_timing`).
_Moment _moment(Object? add) {
  final n = nombre(add);
  if (n != null) {
    if (n < 0 || n > kMaxDureeEbullition) {
      return (timing: null, libelle: false, rejet: 'moment hors bornes');
    }
    return (
      timing: {'use': 'add_to_boil', 'time': _minutes(n.round())},
      libelle: false,
      rejet: null,
    );
  }
  if (add is! String) {
    return (timing: null, libelle: false, rejet: 'moment absent');
  }
  final libelle = add.trim().toLowerCase();
  final jour = RegExp(r'^dry hop, at day (\d{1,3})$').firstMatch(libelle);
  if (jour != null) {
    final j = int.parse(jour[1]!);
    if (j > 365) {
      return (timing: null, libelle: false, rejet: 'moment hors bornes');
    }
    return (
      timing: {'use': 'add_to_fermentation', 'time': _minutes(j * 1440)},
      libelle: false,
      rejet: null,
    );
  }
  return switch (libelle) {
    'start' ||
    'middle' => (timing: {'use': 'add_to_boil'}, libelle: true, rejet: null),
    'end' || 'flame out' => (
      timing: {'use': 'add_to_boil', 'time': _minutes(0)},
      libelle: false,
      rejet: null,
    ),
    'whirlpool' || 'whp' => (
      timing: {'use': 'add_to_boil', 'time': _minutes(0)},
      libelle: true,
      rejet: null,
    ),
    'dry hop' => (
      timing: {'use': 'add_to_fermentation'},
      libelle: false,
      rejet: null,
    ),
    'hd1' ||
    'hd2' ||
    'fv' ||
    'fv addition' ||
    'secondary' ||
    'maturation' ||
    'wood ageing' => (
      timing: {'use': 'add_to_fermentation'},
      libelle: true,
      rejet: null,
    ),
    'mash' => (timing: {'use': 'add_to_mash'}, libelle: false, rejet: null),
    // Durée complète d'ébullition, que la source ne donne pas.
    'fwh' || 'first wort hops' => (
      timing: {'use': 'add_to_boil'},
      libelle: true,
      rejet: null,
    ),
    'kettle' ||
    'additions' => (timing: null, libelle: false, rejet: 'moment ambigu'),
    _ => (timing: null, libelle: false, rejet: 'moment inconnu'),
  };
}
