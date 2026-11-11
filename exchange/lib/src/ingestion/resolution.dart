import 'alias.dart';
import 'cles.dart';
import 'referentiel.dart';

/// Résolution d'un nom de DIY Dog contre les référentiels
/// (`DATA_SOURCES.md`, « Résolution des noms DIY Dog ») : correspondance exacte
/// après normalisation, puis, pour une levure, producteur et référence, puis
/// la table d'alias. Aucune correspondance floue.

/// Étape qui a résolu un nom.
enum EtapeResolution {
  /// Même clé normalisée qu'un nom du référentiel.
  exacte,

  /// Levure : producteur et référence lus dans le nom (`Wyeast 1056`,
  /// `WLP099`).
  souche,

  /// Table d'alias ([kAlias]).
  alias,
}

/// Nom résolu : identifiant de l'entrée et étape.
typedef Resolution = ({String id, EtapeResolution etape});

/// Résolveur : référentiels et table d'alias.
class Resolveur {
  /// Crée le résolveur. Chaque alias doit désigner une entrée existante, et
  /// une entrée ne reçoit qu'un `label_fr` : sinon [StateError] (table
  /// fausse). Le nom de chaque alias s'ajoute aux `aliases` de son entrée, et
  /// son `label_fr` à l'entrée.
  Resolveur(
    this.referentiel, {
    List<Alias> alias = kAlias,
    List<String> ajoutsDansHoublons = kAjoutsDansHoublons,
  }) : _ajoutsDansHoublons = {
         for (final nom in ajoutsDansHoublons) cleNormalisee(nom),
       } {
    for (final a in alias) {
      final cle = '${a.nature.prefixe}|${cleNormalisee(a.nom)}';
      if (_alias.containsKey(cle)) {
        throw StateError('alias en double : ${a.nature.prefixe} ${a.nom}');
      }
      final id = _cible(a);
      if (id == null) {
        throw StateError('alias sans entrée : ${a.nature.prefixe} ${a.nom}');
      }
      _alias[cle] = id;
      final entree = referentiel.entree(id)!;
      entree.aliasAjoutes.add(a.nom);
      final label = a.labelFr;
      if (label != null) {
        if (entree.labelFr != null && entree.labelFr != label) {
          throw StateError('deux label_fr pour $id');
        }
        entree.labelFr = label;
      }
    }
  }

  /// Référentiels.
  final Referentiel referentiel;

  final Map<String, String> _alias = {};

  final Set<String> _ajoutsDansHoublons;

  /// Vrai si [nom], lu dans la liste `hops` de DIY Dog, est un ajout
  /// ([kAjoutsDansHoublons]).
  bool estAjoutDansHoublons(String nom) =>
      _ajoutsDansHoublons.contains(cleNormalisee(nom));

  String? _cible(Alias a) {
    final cible = a.cible;
    if (cible != null) {
      final e = referentiel.entree(cible);
      return e != null && e.nature == a.nature ? cible : null;
    }
    return referentiel.parSouche(a.producteur!, a.produit!);
  }

  /// Résout [nom] de [nature], ou `null`.
  Resolution? resoudre(NatureReferentiel nature, String nom) {
    final exact = referentiel.parNomExact(nature, nom);
    if (exact != null) return (id: exact, etape: EtapeResolution.exacte);
    if (nature == NatureReferentiel.culture) {
      final souche = soucheDuNom(nom);
      if (souche != null) {
        final id = referentiel.parSouche(souche.producteur, souche.produit);
        if (id != null) return (id: id, etape: EtapeResolution.souche);
      }
    }
    final alias = _alias['${nature.prefixe}|${cleNormalisee(nom)}'];
    if (alias != null) return (id: alias, etape: EtapeResolution.alias);
    return null;
  }
}
