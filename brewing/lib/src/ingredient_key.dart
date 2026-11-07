import 'errors.dart';
import 'fermentables.dart';

/// Longueur maximale d'une clé d'ingrédient.
const int maxIngredientKeyLength = 100;

/// Nature d'un ingrédient, qui donne le préfixe de sa clé.
enum IngredientNature {
  /// Malt ou céréale.
  malt('malt'),

  /// Sucre.
  sugar('sucre'),

  /// Houblon.
  hop('houblon'),

  /// Levure.
  yeast('levure'),

  /// Autre ajout (épice, fruit, sel…).
  addition('ajout');

  const IngredientNature(this.prefix);

  /// Préfixe de la clé (`malt`, `sucre`, `houblon`, `levure`, `ajout`).
  final String prefix;

  /// Nature d'un fermentescible.
  static IngredientNature ofFermentable(FermentableKind kind) => switch (kind) {
    FermentableKind.malt => IngredientNature.malt,
    FermentableKind.sugar => IngredientNature.sugar,
  };
}

/// Lettres accentuées en minuscule et leur forme sans accent.
const Map<String, String> _unaccented = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
  // Latin étendu A : lettres d'Europe centrale et du Nord (Žatec, Słód).
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ć': 'c',
  'ĉ': 'c',
  'ċ': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'ē': 'e',
  'ĕ': 'e',
  'ė': 'e',
  'ę': 'e',
  'ě': 'e',
  'ĝ': 'g',
  'ğ': 'g',
  'ġ': 'g',
  'ģ': 'g',
  'ĥ': 'h',
  'ħ': 'h',
  'ĩ': 'i',
  'ī': 'i',
  'ĭ': 'i',
  'į': 'i',
  'ı': 'i',
  'ĳ': 'ij',
  'ĵ': 'j',
  'ķ': 'k',
  'ĸ': 'k',
  'ĺ': 'l',
  'ļ': 'l',
  'ľ': 'l',
  'ŀ': 'l',
  'ł': 'l',
  'ń': 'n',
  'ņ': 'n',
  'ň': 'n',
  'ŉ': 'n',
  'ŋ': 'n',
  'ō': 'o',
  'ŏ': 'o',
  'ő': 'o',
  'ŕ': 'r',
  'ŗ': 'r',
  'ř': 'r',
  'ś': 's',
  'ŝ': 's',
  'ş': 's',
  'š': 's',
  'ţ': 't',
  'ť': 't',
  'ŧ': 't',
  'ũ': 'u',
  'ū': 'u',
  'ŭ': 'u',
  'ů': 'u',
  'ű': 'u',
  'ų': 'u',
  'ŵ': 'w',
  'ŷ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'ſ': 's',
  'þ': 'th',
  'ð': 'd',
};

/// Accents combinants (Unicode décomposé : « e » suivi de U+0301).
final RegExp _combiningMarks = RegExp('[̀-ͯ]');

/// Nom en minuscules, sans accents, chaque suite de caractères hors a-z et 0-9
/// remplacée par un tiret, sans tiret en bord. Vide si le nom n'a ni lettre ni
/// chiffre. Seule définition de la règle K3, lue par [ingredientKey] et
/// [isValidIngredientName].
String _normalizedName(String name) {
  final buffer = StringBuffer();
  final lower = name.toLowerCase().replaceAll(_combiningMarks, '');
  for (final char in lower.split('')) {
    buffer.write(_unaccented[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Vrai si [name] donne une clé d'ingrédient : il contient au moins une lettre
/// ou un chiffre (K3). Sert à la saisie, sans lever d'exception.
bool isValidIngredientName(String name) => _normalizedName(name).isNotEmpty;

/// Clé d'un ingrédient : préfixe de sa nature et nom normalisé.
///
/// Le nom passe en minuscules, perd ses accents ; tout caractère autre qu'une
/// lettre de a à z ou un chiffre devient un tiret ; les tirets se suivant sont
/// réduits à un seul, et aucun ne reste en bord. Le préfixe n'est pas répété
/// quand le nom commence par lui : « Pils » donne `malt-pils`, « Sucre candi
/// ambré » donne `sucre-candi-ambre`. La clé est coupée à
/// [maxIngredientKeyLength] caractères, sans tiret final.
///
/// Lève [BrewingInputException] si le nom ne contient ni lettre ni chiffre
/// ([isValidIngredientName] faux).
String ingredientKey(IngredientNature nature, String name) {
  final normalized = _normalizedName(name);
  if (normalized.isEmpty) {
    throw BrewingInputException(
      'name',
      name,
      'le nom doit contenir une lettre ou un chiffre',
    );
  }
  final prefix = nature.prefix;
  final key = normalized == prefix || normalized.startsWith('$prefix-')
      ? normalized
      : '$prefix-$normalized';
  if (key.length <= maxIngredientKeyLength) return key;
  return key
      .substring(0, maxIngredientKeyLength)
      .replaceAll(RegExp(r'-+$'), '');
}
