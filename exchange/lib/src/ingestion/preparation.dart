import 'dart:convert';

import 'alias.dart';
import 'json_commentaires.dart';
import 'cles.dart';
import 'diydog.dart';
import 'lecture_sources.dart';
import 'referentiel.dart';
import 'resolution.dart';
import 'sources.dart';

/// Préparation de l'ingestion (ADR-005, D5) : lit les sources, fusionne les
/// référentiels, convertit les recettes DIY Dog et produit, par collection,
/// la liste des documents `{id, data}` à écrire, et le rapport chiffré. Aucun
/// réseau, aucune écriture : `bin/preparer_referentiels.dart` écrit les
/// fichiers, `ingest/ecrire.mjs` les documents.

/// Nombre maximal de fichiers DIY Dog lus : la source en compte 415.
const int kMaxFichiersDiyDog = 1000;

/// Contenu des fichiers sources.
class SourcesBrutes {
  /// Crée les sources.
  const SourcesBrutes({
    required this.octets001,
    required this.texte002,
    required this.texte003,
    required this.texte004,
    required this.texte005,
    required this.texteFabricants,
    required this.diyDog,
  });

  /// Fichier 001, en octets (BeerXML en ISO-8859-1).
  final List<int> octets001;

  /// Fichier 002.
  final String texte002;

  /// Fichier 003.
  final String texte003;

  /// Fichier 004.
  final String texte004;

  /// Fichier 005.
  final String texte005;

  /// Fiches techniques des fabricants (`fabricants/cultures.json`).
  final String texteFabricants;

  /// Recettes DIY Dog : nom du fichier et contenu, dans l'ordre des fichiers.
  final List<({String fichier, String texte})> diyDog;
}

/// Résultat de la préparation.
class Preparation {
  /// Crée le résultat.
  const Preparation(this.collections, this.rapport);

  /// Documents par collection : `{id, data}`, triés par identifiant.
  final Map<String, List<Map<String, Object?>>> collections;

  /// Rapport chiffré (`import/ingest/prepare/rapport.json`).
  final Map<String, Object?> rapport;
}

/// Document `{id, data}` avec son `content_sha256`.
Map<String, Object?> _document(String id, Map<String, Object?> contenu) => {
  'id': id,
  'data': {...contenu, 'content_sha256': empreinteContenu(contenu)},
};

/// Taux en pourcentage, au dixième.
double _taux(int partie, int total) =>
    total == 0 ? 0 : (partie * 1000 / total).roundToDouble() / 10;

int _parNom(Map<String, Object?> a, Map<String, Object?> b) {
  final nom = (a['name']! as String).toLowerCase().compareTo(
    (b['name']! as String).toLowerCase(),
  );
  return nom != 0 ? nom : (a['id']! as String).compareTo(b['id']! as String);
}

/// Prépare les documents à partir de [sources], avec la table [alias] et la
/// liste [ajoutsDansHoublons].
Preparation preparer(
  SourcesBrutes sources, {
  List<Alias> alias = kAlias,
  List<String> ajoutsDansHoublons = kAjoutsDansHoublons,
}) {
  final lecture = LectureReferentiels()
    ..lire001(sources.octets001)
    ..lire002(sources.texte002)
    ..lire003ou004(sources.texte003, Source.brewtarget003)
    ..lire003ou004(sources.texte004, Source.brewtarget004)
    ..lire005(sources.texte005)
    ..lireFabricants(sources.texteFabricants);
  final referentiel = Referentiel.fusionner(lecture.entrees);
  final resolveur = Resolveur(
    referentiel,
    alias: alias,
    ajoutsDansHoublons: ajoutsDansHoublons,
  );
  final conversion = ConversionDiyDog(resolveur);

  if (sources.diyDog.length > kMaxFichiersDiyDog) {
    throw StateError(
      '${sources.diyDog.length} fichiers DIY Dog, $kMaxFichiersDiyDog au plus',
    );
  }
  final recettes = <Map<String, Object?>>[];
  for (final f in sources.diyDog) {
    final r = conversion.convertir(lireJsonBorne(f.texte), f.fichier);
    if (r != null) recettes.add(_document(r.id, r.document));
  }
  final ids = <String>{};
  for (final r in recettes) {
    if (!ids.add(r['id']! as String)) {
      throw StateError('recette DIY Dog en double : ${r['id']}');
    }
  }

  final collections = <String, List<Map<String, Object?>>>{};
  final index = <Map<String, Object?>>[];
  for (final nature in NatureReferentiel.values) {
    final entrees = referentiel.parNature[nature]!.values.toList();
    collections[nature.collection] = [
      for (final e in entrees) _document(e.id, e.document()),
    ];
    final lignes = [for (final e in entrees) e.entreeIndex()]..sort(_parNom);
    index.add(
      _document(nature.documentIndex, {
        'count': lignes.length,
        'entries': lignes,
      }),
    );
  }
  collections['beer_styles'] = [
    for (final s in lecture.styles) _document(s.id, s.document),
  ];
  final styles = [
    for (final s in lecture.styles) _entreeIndexStyle(s.id, s.document),
  ]..sort(_parNom);
  index.add(_document('styles', {'count': styles.length, 'entries': styles}));
  collections['beer_index'] = index;
  collections['public_recipes'] = recettes;

  final nonResolus = <Map<String, Object?>>[];
  for (final MapEntry(key: nature, value: compte)
      in conversion.comptes.entries) {
    for (final n in compte.nonResolus.values) {
      nonResolus.add({
        'id': idNonResolu(nature, n.nom),
        'data': {
          'nature': nature.prefixe,
          'name': n.nom,
          'source': Source.diydog.id,
          'count': n.lignes,
        },
      });
    }
  }
  collections['import_unresolved'] = nonResolus;

  for (final liste in collections.values) {
    liste.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    for (var i = 1; i < liste.length; i++) {
      if (liste[i]['id'] == liste[i - 1]['id']) {
        throw StateError('identifiant en double : ${liste[i]['id']}');
      }
    }
  }

  final ecartees = [
    ...lecture.journal.ecartees,
    ...conversion.journal.ecartees,
  ];
  final parSource = lecture.parSource;
  parSource[Source.diydog.id] = {'recette': sources.diyDog.length};
  final rapport = <String, Object?>{
    'sources': [
      for (final s in Source.values) {'source': s.id, 'version': s.version},
    ],
    'entrees_par_source': parSource,
    'entrees_rejetees': [for (final r in lecture.rejets) r.toJson()],
    'listes_ignorees': lecture.listesIgnorees,
    'valeurs_ecartees': {
      'nombre': ecartees.length,
      'lignes': [for (final e in ecartees) e.toJson()],
    },
    'fusions': {
      for (final n in NatureReferentiel.values)
        n.prefixe: {
          'entrees': referentiel.parNature[n]!.values.fold(
            0,
            (t, f) => t + f.entrees.length,
          ),
          'documents': referentiel.parNature[n]!.length,
          'fusions': referentiel.fusions(n),
        },
    },
    'documents': {
      for (final MapEntry(:key, :value) in collections.entries)
        key: value.length,
    },
    'recettes': {
      'lues': sources.diyDog.length,
      'converties': recettes.length,
      'refusees': conversion.recettesRefusees,
    },
    'resolution': {
      for (final MapEntry(key: n, value: c) in conversion.comptes.entries)
        if (c.lignes > 0)
          n.prefixe: {
            'lignes': c.lignes,
            'exactes': c.parEtape[EtapeResolution.exacte],
            'souche': c.parEtape[EtapeResolution.souche],
            'alias': c.parEtape[EtapeResolution.alias],
            'non_resolues': c.lignesNonResolues,
            'taux_avant_alias': _taux(c.avantAlias, c.lignes),
            'taux_apres_alias': _taux(c.resolues, c.lignes),
            'noms_non_resolus': c.nonResolus.length,
          },
    },
    'valeurs_recopiees': conversion.recopiees,
    'non_resolus': {
      for (final MapEntry(key: n, value: c) in conversion.comptes.entries)
        if (c.nonResolus.isNotEmpty)
          n.prefixe: [
            for (final v
                in c.nonResolus.values.toList()..sort(
                  (a, b) => b.lignes != a.lignes
                      ? b.lignes.compareTo(a.lignes)
                      : a.nom.compareTo(b.nom),
                ))
              {'name': v.nom, 'lignes': v.lignes},
          ],
    },
    'lignes_rejetees': {
      'nombre': conversion.lignesRejetees.length,
      'lignes': [for (final l in conversion.lignesRejetees) l.toJson()],
    },
    'libelles_ajouts_perdus': conversion.libellesAjoutsPerdus,
    'fermentations_non_reprises': conversion.fermentationsNonReprises,
    'tailles_index_octets_json': {
      for (final d in index)
        d['id']! as String: utf8.encode(jsonEncode(d['data'])).length,
    },
  };
  return Preparation(collections, rapport);
}

/// Entrée de `beer_index/styles` : plages en `[min, max]`, nombres nus.
Map<String, Object?> _entreeIndexStyle(String id, Map<String, Object> s) {
  List<num>? bornes(String champ) {
    final p = s[champ];
    if (p is! Map) return null;
    return [
      (p['minimum'] as Map)['value'] as num,
      (p['maximum'] as Map)['value'] as num,
    ];
  }

  return {
    'id': id,
    'name': s['name'],
    'code': s['style_id'],
    'category': ?s['category'],
    'og': ?bornes('original_gravity'),
    'fg': ?bornes('final_gravity'),
    'ibu': ?bornes('international_bitterness_units'),
    'ebc': ?bornes('color'),
    'abv': ?bornes('alcohol_by_volume'),
  };
}
