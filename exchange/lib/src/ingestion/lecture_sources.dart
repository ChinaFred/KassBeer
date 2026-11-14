import '../decodage_xml.dart';
import '../schema.dart';
import 'cles.dart';
import 'json_commentaires.dart';
import 'sources.dart';
import 'valeurs.dart';

/// Lecture des fichiers DefaultContent 001 à 005 de Brewtarget (v5.2.3) et
/// du fichier des fiches techniques des fabricants vers
/// des entrées de référentiel en unités canoniques. Seuls les noms et les
/// valeurs techniques sont lus (P20) : aucun `notes`, description, URL,
/// substitut, `best_for`, recette, équipement ni eau.

/// `HopVarietyBase.type` du schéma figé, écrit dans `purpose`.
const Set<String> kUsagesHoublon = {
  'aroma',
  'bittering',
  'flavor',
  'aroma/bittering',
  'bittering/flavor',
  'aroma/flavor',
  'aroma/bittering/flavor',
};

/// `QualitativeRangeType` du schéma figé (floculation).
const Set<String> kFloculations = {
  'very low',
  'low',
  'medium low',
  'medium',
  'medium high',
  'high',
  'very high',
};

/// `StyleBase.type` du schéma figé.
const Set<String> kTypesStyle = {
  'beer',
  'cider',
  'kombucha',
  'mead',
  'other',
  'soda',
  'wine',
};

/// Entrée lue d'une source, avant fusion.
class EntreeBrute {
  /// Crée l'entrée.
  EntreeBrute({
    required this.nature,
    required this.nom,
    required this.valeurs,
    required this.source,
    required this.sourceId,
    required this.licence,
  });

  /// Nature de l'entrée.
  final NatureReferentiel nature;

  /// Nom nettoyé.
  final String nom;

  /// Champs canoniques du document, hors `name`, `aliases`, `label_fr` et
  /// `provenance`.
  final Map<String, Object> valeurs;

  /// Source lue.
  final Source source;

  /// Identifiant de l'entrée dans sa source : `id` ou `local_id`, sinon le nom.
  final String sourceId;

  /// Licence de l'entrée.
  final String licence;

  /// Producteur d'une culture, ou `null`.
  String? get producteur => valeurs['producer'] as String?;

  /// Référence d'une culture chez son producteur, ou `null`.
  String? get produit => valeurs['product_id'] as String?;

  /// Ligne de `provenance[]`.
  Map<String, Object> get provenanceLigne =>
      provenance(source, sourceId, licence);
}

/// Entrée refusée d'une source : sans nom, ou sans valeur obligatoire.
class EntreeRejetee {
  /// Crée le rejet.
  const EntreeRejetee(this.source, this.nature, this.nom, this.raison);

  /// Source.
  final String source;

  /// Nature ou liste de la source.
  final String nature;

  /// Nom lu, ou `null`.
  final String? nom;

  /// Raison du rejet.
  final String raison;

  /// Ligne du rapport.
  Map<String, Object> toJson() => {
    'source': source,
    'nature': nature,
    'nom': ?nom,
    'raison': raison,
  };
}

/// Style BJCP lu du fichier 002.
class StyleLu {
  /// Crée le style.
  const StyleLu(this.id, this.document);

  /// `bjcp2021-<code>`.
  final String id;

  /// Document `beer_styles/{id}` sans `content_sha256` ni `updated_at`.
  final Map<String, Object> document;
}

/// Ce que la lecture des sources de Brewtarget a produit.
class LectureReferentiels {
  /// Entrées lues, dans l'ordre : 001, 002, 003, 004, 005, fiches des
  /// fabricants.
  final List<EntreeBrute> entrees = [];

  /// Styles du fichier 002.
  final List<StyleLu> styles = [];

  /// Entrées refusées.
  final List<EntreeRejetee> rejets = [];

  /// Valeurs écartées.
  final Journal journal = Journal();

  /// Listes d'une source que l'ingestion ne lit pas, et leur nombre
  /// d'éléments (recettes, équipements, eaux, styles hors 002…).
  final Map<String, int> listesIgnorees = {};

  /// Entrées lues par source et par nature.
  Map<String, Map<String, int>> get parSource {
    final compte = <String, Map<String, int>>{};
    for (final e in entrees) {
      final s = compte.putIfAbsent(e.source.id, () => {});
      s[e.nature.prefixe] = (s[e.nature.prefixe] ?? 0) + 1;
    }
    if (styles.isNotEmpty) {
      compte.putIfAbsent(Source.brewtarget002.id, () => {})['style'] =
          styles.length;
    }
    return compte;
  }

  void _ajouter(
    NatureReferentiel nature,
    String? nom,
    Map<String, Object?> valeurs,
    Source source,
    String? sourceId,
    String licence,
  ) {
    if (nom == null || cleNormalisee(nom).isEmpty) {
      rejets.add(EntreeRejetee(source.id, nature.prefixe, nom, 'nom absent'));
      return;
    }
    entrees.add(
      EntreeBrute(
        nature: nature,
        nom: nom,
        valeurs: {
          for (final MapEntry(:key, :value) in valeurs.entries) key: ?value,
        },
        source: source,
        sourceId: sourceId ?? nom,
        licence: licence,
      ),
    );
  }

  /// Lit le fichier 001 (BeerXML 1.0, ISO-8859-1, plusieurs éléments racines :
  /// `EQUIPMENTS`, `FERMENTABLES`, `HOPS`, `MISCS`, `STYLES`, `WATERS`,
  /// `YEASTS`, `RECIPES`). Seuls `FERMENTABLES`, `HOPS`, `MISCS` et `YEASTS`
  /// sont lus ; les 127 styles d'anciennes éditions, les recettes et les
  /// équipements sont écartés (`DATA_SOURCES.md`).
  void lire001(List<int> octets) {
    final texte = decoderXml(octets, 0);
    if (texte == null) {
      throw const FormatException('001 : encodage non pris en charge');
    }
    // Plusieurs racines : le texte est placé sous une racine ajoutée, après
    // la déclaration XML.
    final corps = texte.replaceFirst(RegExp(r'^\s*<\?xml[^>]*\?>'), '');
    final lu = lireXml(
      '<SOURCE>$corps</SOURCE>',
      maxRecettes: 0,
      conteneurs: const {
        'FERMENTABLES',
        'FERMENTABLE',
        'HOPS',
        'HOP',
        'MISCS',
        'MISC',
        'YEASTS',
        'YEAST',
      },
      ignore: (nom) => nom == 'NOTES' || nom == 'VERSION',
    );
    if (lu is! XmlArbre) throw const FormatException('001 : fichier refusé');
    const source = Source.brewtarget001;
    for (final liste in lu.racine.enfants) {
      for (final e in liste.enfants) {
        String? t(String nom) {
          final v = e.enfant(nom)?.texte.trim();
          return v == null || v.isEmpty ? null : v;
        }

        final nom = nomPropre(t('NAME'));
        final v = LecteurValeurs(journal, source.id, nom ?? '');
        switch ((liste.nom, e.nom)) {
          case ('FERMENTABLES', 'FERMENTABLE'):
            final type = v.enumeree('TYPE', t('TYPE'), kTypesFermentable, {
              'adjunct': 'grain',
            });
            final rendement = _nonNul(
              v,
              'YIELD',
              v.valeur('YIELD', t('YIELD'), '%', Grandeur.pourcent),
            );
            // Couleur en Lovibond, en SRM pour un extrait liquide (norme).
            final couleur = v.valeur(
              'COLOR',
              t('COLOR'),
              type == 'extract' ? 'SRM' : 'Lovi',
              Grandeur.couleur,
            );
            if (type == null) {
              rejets.add(
                EntreeRejetee(source.id, 'fermentable', nom, 'type absent'),
              );
              continue;
            }
            _ajouter(
              NatureReferentiel.fermentable,
              nom,
              {
                'type': type,
                if (rendement != null)
                  'yield': {'fine_grind': couple(rendement, '%')},
                if (couleur != null) 'color': couple(couleur, 'EBC'),
                'producer': v.texte('PRODUCER', t('PRODUCER')),
                'origin': v.texte('ORIGIN', t('ORIGIN')),
              },
              source,
              null,
              Licence.gpl3,
            );
          case ('HOPS', 'HOP'):
            final alpha = _nonNul(
              v,
              'ALPHA',
              v.valeur('ALPHA', t('ALPHA'), '%', Grandeur.pourcent),
            );
            final beta = v.valeur('BETA', t('BETA'), '%', Grandeur.pourcent);
            _ajouter(
              NatureReferentiel.hop,
              nom,
              {
                'form': v.enumeree('FORM', t('FORM'), kFormesHoublon),
                if (alpha != null) 'alpha_acid': couple(alpha, '%'),
                if (beta != null) 'beta_acid': couple(beta, '%'),
                'origin': v.texte('ORIGIN', t('ORIGIN')),
                'purpose': v.enumeree('TYPE', t('TYPE'), kUsagesHoublon, {
                  'both': 'aroma/bittering',
                }),
              },
              source,
              null,
              Licence.gpl3,
            );
          case ('YEASTS', 'YEAST'):
            final min = v.valeur(
              'MIN_TEMPERATURE',
              t('MIN_TEMPERATURE'),
              'C',
              Grandeur.temperature,
            );
            final max = v.valeur(
              'MAX_TEMPERATURE',
              t('MAX_TEMPERATURE'),
              'C',
              Grandeur.temperature,
            );
            final attenuation = _nonNul(
              v,
              'ATTENUATION',
              v.valeur('ATTENUATION', t('ATTENUATION'), '%', Grandeur.pourcent),
            );
            _ajouter(
              NatureReferentiel.culture,
              nom,
              {
                'type': v.enumeree('TYPE', t('TYPE'), kTypesLevure),
                'form': v.enumeree('FORM', t('FORM'), kFormesLevure),
                'producer': v.texte('LABORATORY', t('LABORATORY')),
                'product_id': v.texte('PRODUCT_ID', t('PRODUCT_ID')),
                // Une seule valeur en BeerXML : une plage d'une valeur.
                if (attenuation != null)
                  'attenuation': plage(attenuation, attenuation, '%'),
                if (min != null && max != null)
                  'temperature_range': v.plageDe(
                    'TEMPERATURE',
                    min,
                    max,
                    Grandeur.temperature,
                  ),
                'flocculation': v.enumeree(
                  'FLOCCULATION',
                  t('FLOCCULATION'),
                  kFloculations,
                ),
              },
              source,
              null,
              Licence.gpl3,
            );
          case ('MISCS', 'MISC'):
            _ajouter(
              NatureReferentiel.misc,
              nom,
              {'type': v.enumeree('TYPE', t('TYPE'), kTypesAjout)},
              source,
              null,
              Licence.gpl3,
            );
          default:
            final cle = '${source.id}:${liste.nom}';
            listesIgnorees[cle] = (listesIgnorees[cle] ?? 0) + 1;
        }
      }
      if (liste.enfants.isEmpty && liste.renseigne) {
        final cle = '${source.id}:${liste.nom}';
        listesIgnorees[cle] = (listesIgnorees[cle] ?? 0) + 1;
      }
    }
  }

  /// Lit le fichier 002 (BeerJSON 2.01, 110 styles BJCP 2021) : nom, code,
  /// catégorie, type, guide et plages chiffrées seuls (P20).
  void lire002(String texte) {
    const source = Source.brewtarget002;
    final racine = _racine(texte, 'beerjson', source);
    for (final brut in _liste(racine, 'styles', source)) {
      final s = brut is Map ? brut : const <String, Object?>{};
      final nom = nomPropre(s['name']);
      final code = nomPropre(s['style_id']);
      if (nom == null || code == null || cleNormalisee(code).isEmpty) {
        rejets.add(
          EntreeRejetee(source.id, 'style', nom, 'nom ou code absent'),
        );
        continue;
      }
      final v = LecteurValeurs(journal, source.id, nom);
      final document = <String, Object?>{
        'name': nom,
        'category': v.texte('category', s['category']),
        'category_id': v.texte('category_id', s['category_id']),
        'style_id': code,
        'type': v.enumeree('type', s['type'], kTypesStyle),
        'style_guide': v.texte('style_guide', s['style_guide']),
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
        'provenance': [provenance(source, code, Licence.bjcp)],
      };
      styles.add(
        StyleLu(idStyle(code), {
          for (final MapEntry(:key, :value) in document.entries) key: ?value,
        }),
      );
    }
  }

  /// Lit le fichier 003 ou 004 (BeerJSON 2.01) : `hop_varieties` et
  /// `cultures`.
  void lire003ou004(String texte, Source source) {
    final racine = _racine(texte, 'beerjson', source);
    for (final MapEntry(:key, :value) in racine.entries) {
      if (value is! List) continue;
      switch (key) {
        case 'hop_varieties':
          for (final brut in value) {
            final h = brut is Map ? brut : const <String, Object?>{};
            final nom = nomPropre(h['name']);
            final v = LecteurValeurs(journal, source.id, nom ?? '');
            _ajouter(
              NatureReferentiel.hop,
              nom,
              _houblon(v, h, h['type']),
              source,
              _texteId(h['id']),
              Licence.gpl3,
            );
          }
        case 'cultures':
          _lireCultures(value, source, Licence.gpl3);
        default:
          listesIgnorees['${source.id}:$key'] = value.length;
      }
    }
  }

  /// Lit le fichier des fiches techniques des fabricants (BeerJSON 2.01,
  /// `fabricants/cultures.json`, écrit à la main) : `cultures` seules, avec
  /// les mêmes champs que 003 et 004. Toute autre liste est ignorée et
  /// comptée.
  void lireFabricants(String texte) {
    const source = Source.fabricants;
    final racine = _racine(texte, 'beerjson', source);
    for (final MapEntry(:key, :value) in racine.entries) {
      if (value is! List) continue;
      if (key == 'cultures') {
        _lireCultures(value, source, Licence.fabricant);
      } else {
        listesIgnorees['${source.id}:$key'] = value.length;
      }
    }
  }

  void _lireCultures(List<Object?> liste, Source source, String licence) {
    for (final brut in liste) {
      final c = brut is Map ? brut : const <String, Object?>{};
      final nom = nomPropre(c['name']);
      final v = LecteurValeurs(journal, source.id, nom ?? '');
      _ajouter(
        NatureReferentiel.culture,
        nom,
        _culture(v, c, c['type']),
        source,
        _texteId(c['id']),
        licence,
      );
    }
  }

  /// Lit le fichier 005 (DotBeer 1.0.0) : `fermentables`, `hops`, `miscs`,
  /// `cultures`. Licence par entrée selon `folder_path` ([licence005]).
  void lire005(String texte) {
    const source = Source.brewtarget005;
    final racine = _racine(texte, 'DotBeer', source);
    for (final MapEntry(:key, :value) in racine.entries) {
      if (value is! List) continue;
      for (final brut in value) {
        final e = brut is Map ? brut : const <String, Object?>{};
        final nom = nomPropre(e['name']);
        final v = LecteurValeurs(journal, source.id, nom ?? '');
        final folder = e['folder_path'];
        final licence = licence005(folder is String ? folder : null);
        final sourceId = _texteId(e['local_id']);
        switch (key) {
          case 'fermentables':
            final type = v.enumeree(
              'fermentable_type',
              e['fermentable_type'],
              kTypesFermentable,
            );
            if (type == null) {
              rejets.add(
                EntreeRejetee(source.id, 'fermentable', nom, 'type absent'),
              );
              continue;
            }
            final rendement = _nonNul(
              v,
              'yield_fine_grind',
              v.mesure(
                'yield_fine_grind',
                e['yield_fine_grind'],
                Grandeur.pourcent,
              )?['value'],
            );
            _ajouter(
              NatureReferentiel.fermentable,
              nom,
              {
                'type': type,
                if (rendement != null)
                  'yield': {'fine_grind': couple(rendement, '%')},
                'color': v.mesure('color', e['color'], Grandeur.couleur),
                'producer': v.texte('producer', e['producer']),
                'origin': v.texte('origin', e['origin']),
              },
              source,
              sourceId,
              licence,
            );
          case 'hops':
            _ajouter(
              NatureReferentiel.hop,
              nom,
              _houblon(v, e, e['hop_type']),
              source,
              sourceId,
              licence,
            );
          case 'miscs':
            // `water_agent_type` ignoré en v1 (DATA_SOURCES.md).
            _ajouter(
              NatureReferentiel.misc,
              nom,
              {'type': v.enumeree('misc_type', e['misc_type'], kTypesAjout)},
              source,
              sourceId,
              licence,
            );
          case 'cultures':
            _ajouter(
              NatureReferentiel.culture,
              nom,
              _culture(v, e, e['culture_type']),
              source,
              sourceId,
              licence,
            );
          default:
            listesIgnorees['${source.id}:$key'] =
                (listesIgnorees['${source.id}:$key'] ?? 0) + 1;
        }
      }
    }
  }

  Map<String, Object?> _houblon(
    LecteurValeurs v,
    Map<Object?, Object?> h,
    Object? type,
  ) {
    final alpha = _nonNul(
      v,
      'alpha_acid',
      v.mesure('alpha_acid', h['alpha_acid'], Grandeur.pourcent)?['value'],
    );
    return {
      'form': v.enumeree('form', h['form'], kFormesHoublon),
      if (alpha != null) 'alpha_acid': couple(alpha, '%'),
      'beta_acid': v.mesure('beta_acid', h['beta_acid'], Grandeur.pourcent),
      'origin': v.texte('origin', h['origin']),
      'purpose': v.enumeree('type', type, kUsagesHoublon),
    };
  }

  Map<String, Object?> _culture(
    LecteurValeurs v,
    Map<Object?, Object?> c,
    Object? type,
  ) => {
    'type': v.enumeree('type', type, kTypesLevure),
    'form': v.enumeree('form', c['form'], kFormesLevure),
    'producer': v.texte('producer', c['producer']),
    'product_id': v.texte('product_id', c['product_id']),
    'attenuation': v.plageMesuree(
      'attenuation_range',
      c['attenuation_range'],
      Grandeur.pourcent,
    ),
    'temperature_range': v.plageMesuree(
      'temperature_range',
      c['temperature_range'],
      Grandeur.temperature,
    ),
    'flocculation': v.enumeree(
      'flocculation',
      c['flocculation'],
      kFloculations,
    ),
  };

  Map<Object?, Object?> _racine(String texte, String cle, Source source) {
    final json = lireJsonCommente(texte);
    final racine = json is Map ? json[cle] : null;
    if (racine is! Map) {
      throw FormatException('${source.id} : objet « $cle » absent');
    }
    return racine;
  }

  List<Object?> _liste(Map<Object?, Object?> racine, String cle, Source s) {
    final liste = racine[cle];
    if (liste is! List) {
      throw FormatException('${s.id} : liste « $cle » absente');
    }
    return liste;
  }
}

/// Un rendement, un acide alpha ou une atténuation à 0 tient lieu de valeur
/// inconnue dans les sources : il est écarté et noté, comme à l'import
/// (`DATA_SOURCES.md`).
double? _nonNul(LecteurValeurs v, String champ, Object? valeur) {
  if (valeur is! double) return null;
  if (valeur == 0) {
    v.ecarter(champ, 'valeur nulle');
    return null;
  }
  return valeur;
}

/// Identifiant d'une entrée dans sa source (`id`, `local_id`), ou `null`.
String? _texteId(Object? brut) => switch (brut) {
  String() when brut.trim().isNotEmpty => nomPropre(brut),
  int() => '$brut',
  _ => null,
};
