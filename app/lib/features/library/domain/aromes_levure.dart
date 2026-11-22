import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'aromes_houblon.dart';

/// Collection des descriptions aromatiques des levures (ADR-017), écrite par
/// l'ingestion seule, lue par `get` à l'ouverture de la fiche d'une levure.
const kCollectionAromesLevures = 'beer_culture_aromas';

/// Nombre de styles conseillés au plus (ADR-017, section 4).
const kStylesConseillesMax = 6;

/// Longueur d'un texte au plus, borne de l'écrivain (`TEXTE_MAX` de
/// `ingest/lib/aromes/validation.mjs`).
const kTexteAromeLevureMax = 400;

/// Longueur du nom d'un style au plus, borne de `beer_styles.name` dans
/// `ingest/lib/validation.mjs`.
const kNomStyleMax = 120;

/// Forme de l'identifiant d'un style, celle d'`idStyle` de
/// `exchange/lib/src/ingestion/cles.dart` : le code sert à construire une
/// adresse de l'application.
final _codeStyle = RegExp(r'^bjcp2021-[a-z0-9]+(-[a-z0-9]+)*$');

/// Style conseillé : `code` est l'identifiant de `beer_styles/` (`bjcp2021-…`),
/// `name` est affiché tel quel. Aucune liste de styles en Dart (P62).
@immutable
class StyleConseille {
  const StyleConseille({required this.code, required this.name});

  final String code;
  final String name;
}

/// Description aromatique d'une levure, `beer_culture_aromas/{id}` (ADR-017,
/// section 4). Lecture stricte : un champ attendu absent ou mal typé lève
/// [DocumentIllisible], dont la raison ne recopie aucun texte du document. Une
/// clé de `texts` inconnue est ignorée. `reviewed` et `reviewed_at` servent à
/// l'ingestion seule : l'application ne les lit pas (décision de l'utilisateur
/// du 2026-11-21).
@immutable
sealed class AromesLevure {
  const AromesLevure();

  static AromesLevure fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    switch (data['status']) {
      case 'unknown':
        return const AromesLevureInconnus();
      case 'described':
        final confiance = lireConfianceArome(data);
        final descripteurs = lireDescripteursArome(read);
        final texts = read.objet('texts');
        final profil = _texteBorne(texts.objet('profile'));
        final cool = texts.objetFacultatif('cool');
        final warm = texts.objetFacultatif('warm');
        final bas = cool == null ? null : _texteBorne(cool);
        final haut = warm == null ? null : _texteBorne(warm);
        final styles = read.liste('styles');
        if (styles.length > kStylesConseillesMax) {
          throw const DocumentIllisible('styles', '6 styles au plus');
        }
        return AromesLevureDecrits(
          confiance: confiance,
          descripteurs: descripteurs,
          profil: profil,
          basDePlage: bas,
          hautDePlage: haut,
          styles: List.unmodifiable([for (final s in styles) _style(s)]),
        );
      default:
        throw const DocumentIllisible('status', 'described ou unknown attendu');
    }
  }

  /// `text` de [objet], de [kTexteAromeLevureMax] caractères au plus.
  static String _texteBorne(LecteurChamps objet) {
    final texte = objet.texte('text');
    // Points de code, comme l'écrivain (`[...t].length`, ingest/lib/aromes/validation.mjs).
    if (texte.runes.length > kTexteAromeLevureMax) {
      throw DocumentIllisible('${objet.prefix}text', '400 caractères au plus');
    }
    return texte;
  }

  /// Style conseillé : code de la forme d'`idStyle`, nom de [kNomStyleMax]
  /// caractères au plus. La raison d'un refus ne recopie aucune valeur.
  static StyleConseille _style(LecteurChamps s) {
    final code = s.texte('code');
    if (!_codeStyle.hasMatch(code)) {
      throw DocumentIllisible(
        '${s.prefix}code',
        'identifiant de style attendu',
      );
    }
    final name = s.texte('name');
    if (name.length > kNomStyleMax) {
      throw DocumentIllisible('${s.prefix}name', '120 caractères au plus');
    }
    return StyleConseille(code: code, name: name);
  }
}

/// `status: described`.
class AromesLevureDecrits extends AromesLevure {
  const AromesLevureDecrits({
    required this.confiance,
    required this.descripteurs,
    required this.profil,
    required this.basDePlage,
    required this.hautDePlage,
    required this.styles,
  });

  final ConfianceArome confiance;

  /// Dans l'ordre du document.
  final List<DescripteurArome> descripteurs;

  /// `texts.profile.text`.
  final String profil;

  /// `texts.cool.text`, absent quand le profil ne change pas.
  final String? basDePlage;

  /// `texts.warm.text`, absent quand le profil ne change pas.
  final String? hautDePlage;

  /// Dans l'ordre du document, 6 au plus.
  final List<StyleConseille> styles;
}

/// `status: unknown` : levure trop peu documentée.
class AromesLevureInconnus extends AromesLevure {
  const AromesLevureInconnus();
}
