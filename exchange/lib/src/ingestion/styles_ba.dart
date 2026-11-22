import '../bornes.dart';
import '../texte.dart';
import 'cles.dart';
import 'json_commentaires.dart';
import 'lecture_sources.dart';
import 'sources.dart';
import 'valeurs.dart';

/// Styles de la Brewers Association (ADR-018) : lecture de la table de
/// décisions versionnée (`exchange/donnees/styles/ba.json`) et du fichier des
/// plages recopiées du PDF (`import/sources/ba-<édition>/styles.json`, jamais
/// versionné), jointure et contrôles des sections 1 à 4 d'ADR-018. La
/// préparation ne décide aucun doublon : elle lit la décision écrite dans la
/// table et refuse ce qui la contredit. Aucune description, aucun exemple ni
/// aucun lien n'est lu (P20). Les erreurs lèvent [FormatException] (fichier
/// illisible) ou [StateError] (contrôle en échec, avec la liste des noms) :
/// rien n'est écrit.

/// Motif d'un code Kass'Beer de style BA : `BA` + rang de la catégorie + lettre
/// du rang du style (ADR-018, section 4).
final RegExp kMotifCodeBa = RegExp(r'^BA[1-9][0-9]?[A-Z]{1,2}$');

/// Première et dernière édition acceptées.
const int _editionMin = 2000, _editionMax = 2100;

/// Longueur maximale de la mention de la BA et d'un motif de décision.
const int _maxMention = 400, _maxMotif = 400;

/// Plus grand nombre de lignes de la table et de styles du fichier des plages.
const int kMaxStylesBa = 500;

/// Décision écrite pour un style BA.
enum DecisionBa {
  /// Style sans équivalent BJCP 2021 : il entre dans `beer_styles`.
  nouveau,

  /// Style couvert par un ou plusieurs styles BJCP 2021 : il n'entre pas.
  equivalent,
}

/// Ligne de la table de décisions.
class LigneBa {
  /// Crée la ligne.
  const LigneBa({
    required this.nom,
    required this.categorie,
    required this.decision,
    required this.equivalent,
    required this.contenuDans,
    required this.motif,
    required this.code,
    required this.editions,
    required this.retireEn,
  });

  /// Nom BA tel que publié.
  final String nom;

  /// Catégorie BA telle que publiée.
  final String categorie;

  /// Décision.
  final DecisionBa decision;

  /// Codes BJCP 2021 d'un [DecisionBa.equivalent] ; vide pour un nouveau.
  final List<String> equivalent;

  /// Code BJCP du style plus large qui nomme ce sous-type, ou `null`.
  final String? contenuDans;

  /// Raison de la décision.
  final String motif;

  /// Code Kass'Beer d'un [DecisionBa.nouveau] ; `null` pour un équivalent.
  final String? code;

  /// Éditions où le style figure.
  final List<int> editions;

  /// Édition qui ne contient plus le style, ou `null`.
  final int? retireEn;

  /// Vrai si la ligne est retirée à l'édition [edition].
  bool retireeA(int edition) => retireEn != null && retireEn! <= edition;

  /// Clé de jointure : nom et catégorie.
  String get cle => '$nom\u0000$categorie';
}

/// Table de décisions (ADR-018, section 2).
class TableBa {
  /// Crée la table.
  const TableBa(this.editionCourante, this.mention, this.lignes);

  /// Édition du guide préparée.
  final int editionCourante;

  /// Mention de la BA pour cette édition, recopiée telle quelle.
  final String mention;

  /// Lignes, dans l'ordre du fichier.
  final List<LigneBa> lignes;

  /// Lignes non retirées à [editionCourante] : les styles de l'édition.
  List<LigneBa> get lignesActives => [
    for (final l in lignes)
      if (!l.retireeA(editionCourante)) l,
  ];
}

/// Fichier des plages recopiées du PDF : en-tête et styles bruts.
class PlagesBa {
  /// Crée le fichier lu.
  const PlagesBa({
    required this.edition,
    required this.publication,
    required this.pdfSha256,
    required this.releve,
    required this.styles,
  });

  /// Édition du guide.
  final int edition;

  /// Date de publication du PDF (`AAAA-MM-JJ`).
  final String publication;

  /// SHA-256 du PDF, 64 chiffres hexadécimaux en minuscules.
  final String pdfSha256;

  /// Date de la recopie (`AAAA-MM-JJ`) : `provenance[].retrieved`.
  final String releve;

  /// Styles BeerJSON 2.01, non lus.
  final List<Map<Object?, Object?>> styles;
}

/// Résultat de la jointure.
class StylesBa {
  /// Crée le résultat.
  const StylesBa(this.styles, this.mention, this.rapport, this.lus);

  /// Styles `nouveau` de l'édition courante, à écrire.
  final List<StyleLu> styles;

  /// Champ racine `ba_mention` de `beer_index/styles`.
  final Map<String, Object> mention;

  /// Section `styles_ba` de `rapport.json`.
  final Map<String, Object?> rapport;

  /// Styles lus dans le fichier des plages.
  final int lus;
}

final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// Marques combinantes et caractères que la forme NFC remplace (Kelvin,
/// Ångström, Ohm). Le SDK Dart n'a pas de normalisation Unicode : un nom qui
/// en porte est refusé au lieu d'être normalisé, et deux noms sans eux se
/// comparent en NFC par égalité exacte.
final RegExp _horsNfc = RegExp(
  '[̀-ͯ᪰-᫿᷀-᷿⃐-⃿︠-︯'
  'ΩKÅ̀́̓̈́ʹ;·]',
);

Never _illisible(String fichier, String chemin, String raison) =>
    throw FormatException('$fichier : $chemin : $raison');

void _cles(
  String fichier,
  String chemin,
  Map<Object?, Object?> objet,
  Set<String> permises,
) {
  for (final cle in objet.keys) {
    if (!permises.contains(cle)) {
      _illisible(fichier, chemin, 'clé non permise « $cle »');
    }
  }
}

/// Texte d'une ligne exact : déjà nettoyé, en NFC, de 1 à [max] caractères.
String _texteExact(String fichier, String chemin, Object? brut, int max) {
  if (brut is! String) _illisible(fichier, chemin, 'texte attendu');
  final propre = nettoyerLigne(brut);
  if (propre.texte.isEmpty) _illisible(fichier, chemin, 'texte vide');
  if (propre.retires || propre.texte != brut) {
    _illisible(fichier, chemin, 'caractère de contrôle ou espace de bord');
  }
  if (brut.length > max) {
    _illisible(fichier, chemin, '$max caractères au plus');
  }
  if (_horsNfc.hasMatch(brut)) {
    _illisible(fichier, chemin, 'texte hors de la forme NFC');
  }
  return brut;
}

int _edition(String fichier, String chemin, Object? brut) {
  if (brut is! int || brut < _editionMin || brut > _editionMax) {
    _illisible(
      fichier,
      chemin,
      'édition entière de $_editionMin à $_editionMax attendue',
    );
  }
  return brut;
}

List<Object?> _liste(String fichier, String chemin, Object? brut) {
  if (brut is! List) _illisible(fichier, chemin, 'liste attendue');
  if (brut.length > kMaxStylesBa) {
    _illisible(fichier, chemin, '$kMaxStylesBa éléments au plus');
  }
  return brut;
}

const _fichierTable = 'ba.json';
const _fichierPlages = 'styles.json';

/// Lit la table de décisions [texte] : en-tête `edition_courante` et
/// `mention`, puis `styles`. Toute autre clé, à la racine ou dans une ligne,
/// lève [FormatException] : la table ne porte que les champs de P20, aucune
/// plage ni description. La règle d'attribution des codes est décrite dans
/// `DATA_SOURCES.md`.
TableBa lireTableBa(String texte) {
  const f = _fichierTable;
  final racine = lireJsonBorne(texte);
  if (racine is! Map) _illisible(f, 'racine', 'objet attendu');
  _cles(f, 'racine', racine, const {'edition_courante', 'mention', 'styles'});
  final edition = _edition(f, 'edition_courante', racine['edition_courante']);
  final mention = _texteExact(f, 'mention', racine['mention'], _maxMention);
  if (!mention.contains('$edition')) {
    _illisible(f, 'mention', 'ne cite pas l\'édition $edition');
  }
  final lignes = <LigneBa>[];
  final brutes = _liste(f, 'styles', racine['styles']);
  for (var i = 0; i < brutes.length; i++) {
    final c = 'styles[$i]';
    final l = brutes[i];
    if (l is! Map) _illisible(f, c, 'objet attendu');
    _cles(f, c, l, const {
      'name',
      'category',
      'decision',
      'equivalent',
      'contenu_dans',
      'motif',
      'code',
      'editions',
      'retire_en',
    });
    final decision = switch (l['decision']) {
      'nouveau' => DecisionBa.nouveau,
      'equivalent' => DecisionBa.equivalent,
      _ => _illisible(f, '$c.decision', '« nouveau » ou « equivalent »'),
    };
    final equivalent = <String>[];
    if (decision == DecisionBa.equivalent) {
      final codes = l['equivalent'];
      if (codes is! List || codes.isEmpty || codes.length > 10) {
        _illisible(f, '$c.equivalent', 'liste de 1 à 10 codes BJCP attendue');
      }
      for (var j = 0; j < codes.length; j++) {
        equivalent.add(_texteExact(f, '$c.equivalent[$j]', codes[j], 10));
      }
      for (final interdit in const ['code', 'contenu_dans']) {
        if (l.containsKey(interdit)) {
          _illisible(f, '$c.$interdit', 'refusé sur un « equivalent »');
        }
      }
    } else if (l.containsKey('equivalent')) {
      _illisible(f, '$c.equivalent', 'refusé sur un « nouveau »');
    }
    final code = decision == DecisionBa.nouveau
        ? _texteExact(f, '$c.code', l['code'], 10)
        : null;
    if (code != null && !kMotifCodeBa.hasMatch(code)) {
      _illisible(f, '$c.code', 'code hors du motif ${kMotifCodeBa.pattern}');
    }
    final contenuDans = l.containsKey('contenu_dans')
        ? _texteExact(f, '$c.contenu_dans', l['contenu_dans'], 10)
        : null;
    final eds = l['editions'];
    if (eds is! List || eds.isEmpty || eds.length > 100) {
      _illisible(f, '$c.editions', 'liste de 1 à 100 éditions attendue');
    }
    final editions = [
      for (var j = 0; j < eds.length; j++)
        _edition(f, '$c.editions[$j]', eds[j]),
    ];
    final retireEn = l.containsKey('retire_en')
        ? _edition(f, '$c.retire_en', l['retire_en'])
        : null;
    if (retireEn != null && editions.any((e) => e >= retireEn)) {
      _illisible(f, '$c.retire_en', 'postérieure à chaque édition attendue');
    }
    lignes.add(
      LigneBa(
        nom: _texteExact(f, '$c.name', l['name'], kMaxNom),
        categorie: _texteExact(f, '$c.category', l['category'], kMaxNom),
        decision: decision,
        equivalent: equivalent,
        contenuDans: contenuDans,
        motif: _texteExact(f, '$c.motif', l['motif'], _maxMotif),
        code: code,
        editions: editions,
        retireEn: retireEn,
      ),
    );
  }
  return TableBa(edition, mention, lignes);
}

/// Lit le fichier des plages [texte] : `edition`, `published`, `pdf_sha256`,
/// `retrieved`, et `beerjson` (BeerJSON 2.01, liste `styles`). Les styles ne
/// sont lus qu'à la jointure, champ par champ.
PlagesBa lirePlagesBa(String texte) {
  const f = _fichierPlages;
  final racine = lireJsonBorne(texte);
  if (racine is! Map) _illisible(f, 'racine', 'objet attendu');
  _cles(f, 'racine', racine, const {
    'edition',
    'published',
    'pdf_sha256',
    'retrieved',
    'beerjson',
  });
  String date(String cle) {
    final v = racine[cle];
    if (v is! String || !_date.hasMatch(v)) {
      _illisible(f, cle, 'date AAAA-MM-JJ attendue');
    }
    return v;
  }

  final sha = racine['pdf_sha256'];
  if (sha is! String || !_sha256.hasMatch(sha)) {
    _illisible(f, 'pdf_sha256', '64 chiffres hexadécimaux attendus');
  }
  final beerjson = racine['beerjson'];
  if (beerjson is! Map) _illisible(f, 'beerjson', 'objet attendu');
  final styles = _liste(f, 'beerjson.styles', beerjson['styles']);
  return PlagesBa(
    edition: _edition(f, 'edition', racine['edition']),
    publication: date('published'),
    pdfSha256: sha,
    releve: date('retrieved'),
    styles: [
      for (var i = 0; i < styles.length; i++)
        switch (styles[i]) {
          final Map<Object?, Object?> s => s,
          _ => _illisible(f, 'beerjson.styles[$i]', 'objet attendu'),
        },
    ],
  );
}

/// Contrôles de la table seule (ADR-018, sections 2 à 4), rendus en liste de
/// messages, vide si la table est bonne : code en double (lignes retirées
/// comprises), deux lignes non retirées de même nom et même catégorie, ligne
/// non retirée qui ne cite pas l'édition courante, nom d'un `nouveau` non
/// retiré sans lettre ni chiffre ou égal, après `cleNormalisee`, à celui d'un
/// autre. Avec [codesBjcp] (codes du 002 préparé), un `equivalent` ou un
/// `contenu_dans` hors de cette liste est refusé ; avec [nomsBjcp] (clé
/// normalisée → identifiant), un nom retenu égal à celui d'un style BJCP l'est
/// aussi. Sans eux, ces deux contrôles n'ont pas lieu.
List<String> controlerTableBa(
  TableBa table, {
  Set<String>? codesBjcp,
  Map<String, String>? nomsBjcp,
}) {
  final edition = table.editionCourante;
  final erreurs = <String>[];
  final codes = <String, String>{};
  final actives = <String>{};
  final nomsBa = <String, String>{};
  for (final l in table.lignes) {
    if (l.code case final code?) {
      if (codes[code] case final autre?) {
        erreurs.add('code $code porté par « $autre » et « ${l.nom} »');
      }
      codes[code] = l.nom;
    }
    if (codesBjcp != null) {
      for (final c in l.equivalent) {
        if (!codesBjcp.contains(c)) {
          erreurs.add(
            '« ${l.nom} » : équivalent $c absent du BJCP 2021 préparé',
          );
        }
      }
      if (l.contenuDans case final c? when !codesBjcp.contains(c)) {
        erreurs.add(
          '« ${l.nom} » : contenu_dans $c absent du BJCP 2021 préparé',
        );
      }
    }
    if (l.retireeA(edition)) continue;
    if (!l.editions.contains(edition)) {
      erreurs.add('« ${l.nom} » : ligne non retirée sans l\'édition $edition');
    }
    if (!actives.add(l.cle)) {
      erreurs.add('« ${l.nom} » (${l.categorie}) : deux lignes non retirées');
    }
    if (l.decision != DecisionBa.nouveau) continue;
    final cle = cleNormalisee(l.nom);
    if (cle.isEmpty) {
      erreurs.add('« ${l.nom} » : nom sans lettre ni chiffre');
      continue;
    }
    if (nomsBjcp?[cle] case final id?) {
      erreurs.add('« ${l.nom} » : même nom normalisé que $id');
    }
    if (nomsBa[cle] case final autre?) {
      erreurs.add('« ${l.nom} » : même nom normalisé que « $autre »');
    }
    nomsBa[cle] = l.nom;
  }
  return erreurs;
}

/// Joint [table] et [plages] et rend les styles `nouveau` à écrire, contrôlés
/// contre les styles BJCP 2021 préparés [bjcp] (ADR-018, sections 1 à 4). Les
/// valeurs écartées vont dans [journal]. Chaque contrôle en échec lève
/// [StateError] avec la liste des noms en cause.
StylesBa joindreStylesBa(
  TableBa table,
  PlagesBa plages,
  List<StyleLu> bjcp,
  Journal journal,
) {
  final edition = table.editionCourante;
  if (plages.edition != edition) {
    throw StateError(
      'styles.json : édition ${plages.edition}, la table prépare l\'édition '
      '$edition (edition_courante)',
    );
  }
  final erreurs = controlerTableBa(
    table,
    codesBjcp: {for (final s in bjcp) s.document['style_id']! as String},
    nomsBjcp: {
      for (final s in bjcp) cleNormalisee(s.document['name']! as String): s.id,
    },
  );
  final actives = {for (final l in table.lignesActives) l.cle: l};
  final retirees = {
    for (final l in table.lignes)
      if (l.retireeA(edition)) l.cle,
  };

  // Jointure : chaque style a sa ligne, chaque ligne non retirée son style.
  final joints = <String, Map<Object?, Object?>>{};
  final sansLigne = <String>[];
  for (var i = 0; i < plages.styles.length; i++) {
    final s = plages.styles[i];
    final c = 'beerjson.styles[$i]';
    final nom = _texteExact(_fichierPlages, '$c.name', s['name'], kMaxNom);
    final categorie = _texteExact(
      _fichierPlages,
      '$c.category',
      s['category'],
      kMaxNom,
    );
    final cle = '$nom\u0000$categorie';
    if (joints.containsKey(cle)) {
      erreurs.add('« $nom » ($categorie) : deux fois dans styles.json');
    } else if (actives.containsKey(cle)) {
      joints[cle] = s;
    } else {
      sansLigne.add(
        retirees.contains(cle)
            ? '« $nom » ($categorie, ligne retirée)'
            : '« $nom » ($categorie)',
      );
    }
  }
  if (sansLigne.isNotEmpty) {
    erreurs.add('styles sans ligne de la table : ${sansLigne.join(', ')}');
  }
  final sansStyle = [
    for (final l in actives.values)
      if (!joints.containsKey(l.cle)) '« ${l.nom} » (${l.categorie})',
  ];
  if (sansStyle.isNotEmpty) {
    erreurs.add('lignes sans style dans styles.json : ${sansStyle.join(', ')}');
  }

  final retenus = [
    for (final l in actives.values)
      if (l.decision == DecisionBa.nouveau) l,
  ];
  if (erreurs.isNotEmpty) {
    throw StateError(
      'styles BA refusés (${erreurs.length}) :\n  ${erreurs.join('\n  ')}',
    );
  }

  final styles = <StyleLu>[];
  for (final l in retenus) {
    final s = joints[l.cle]!;
    final code = l.code!;
    final v = LecteurValeurs(journal, kSourceBa, l.nom);
    final document = <String, Object?>{
      'name': l.nom,
      'category': l.categorie,
      // Numéro de catégorie : le code sans sa lettre (`BA3C` donne `BA3`),
      // comme `21` pour `21B` : l'export BeerXML en tire la lettre.
      'category_id': code.replaceFirst(RegExp(r'[A-Z]+$'), ''),
      'style_id': code,
      'type': v.enumeree('type', s['type'], kTypesStyle),
      'style_guide': 'BA$edition',
      'original_gravity': v.plageMesuree(
        'original_gravity',
        s['original_gravity'],
        Grandeur.densite,
      ),
      'final_gravity': v.plageMesuree(
        'final_gravity',
        s['final_gravity'],
        Grandeur.densite,
      ),
      'international_bitterness_units': v.plageMesuree(
        'international_bitterness_units',
        s['international_bitterness_units'],
        Grandeur.amertume,
      ),
      // SRM converti en EBC par brewing/ (P3).
      'color': v.plageMesuree('color', s['color'], Grandeur.couleur),
      'alcohol_by_volume': v.plageMesuree(
        'alcohol_by_volume',
        s['alcohol_by_volume'],
        Grandeur.pourcent,
      ),
      'provenance': [
        {
          'source': kSourceBa,
          'source_id': l.nom,
          'version': '$edition',
          'licence': Licence.ba,
          'retrieved': plages.releve,
        },
      ],
    };
    styles.add(
      StyleLu(idStyleBa(l.nom), {
        for (final MapEntry(:key, :value) in document.entries) key: ?value,
      }),
    );
  }

  final rapport = <String, Object?>{
    'edition': edition,
    'publication': plages.publication,
    'pdf_sha256': plages.pdfSha256,
    'lignes': table.lignes.length,
    'lus': plages.styles.length,
    'nouveaux': styles.length,
    'equivalents': [
      for (final l in actives.values)
        if (l.decision == DecisionBa.equivalent)
          {'name': l.nom, 'equivalent': l.equivalent},
    ],
    'retirees': retirees.length,
    'chevauchements': [
      for (var i = 0; i < styles.length; i++)
        {
          'id': styles[i].id,
          'name': retenus[i].nom,
          'code': retenus[i].code,
          'contenu_dans': ?retenus[i].contenuDans,
          'bjcp': chevauchementsBjcp(styles[i].document, bjcp),
        },
    ],
  };
  return StylesBa(
    styles,
    {'edition': edition, 'mention': table.mention},
    rapport,
    plages.styles.length,
  );
}

/// Plages comparées par [chevauchementsBjcp], en unités canoniques.
const _plagesComparees = [
  'original_gravity',
  'final_gravity',
  'international_bitterness_units',
  'color',
  'alcohol_by_volume',
];

/// Codes des styles de [bjcp] dont les plages chevauchent celles de [style] :
/// chaque plage présente des deux côtés a une partie commune, et au moins une
/// l'est. Comparaison d'intervalles seule, sur des valeurs déjà converties par
/// `brewing/` : aucune grandeur n'est calculée (ADR-018, section 3).
List<String> chevauchementsBjcp(Map<String, Object> style, List<StyleLu> bjcp) {
  (num, num)? bornes(Map<String, Object> d, String champ) {
    final p = d[champ];
    if (p is! Map) return null;
    return (
      (p['minimum'] as Map)['value'] as num,
      (p['maximum'] as Map)['value'] as num,
    );
  }

  final codes = <String>[];
  for (final b in bjcp) {
    var comparees = 0;
    var communes = true;
    for (final champ in _plagesComparees) {
      final x = bornes(style, champ);
      final y = bornes(b.document, champ);
      if (x == null || y == null) continue;
      comparees++;
      if (x.$1 > y.$2 || y.$1 > x.$2) {
        communes = false;
        break;
      }
    }
    if (comparees > 0 && communes) codes.add(b.document['style_id']! as String);
  }
  return codes..sort();
}
