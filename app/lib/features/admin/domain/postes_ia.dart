/// Postes de coût de l'IA (ADR-016, section 3) : clé, libellé affiché par
/// Admin › Moteur d'IA et Admin › Coûts de l'IA, ADR qui l'a ouvert. Valeurs
/// seules, égales à `test-fixtures/ai_cost_centers.json`, que rejoue aussi
/// `functions/src/ai/costCenters.ts` (« Logique dupliquée »). Un poste retiré
/// du code reste dans cette liste : les mois passés gardent son libellé.
class PosteIa {
  const PosteIa({required this.cle, required this.libelle, required this.adr});

  /// Nom du poste sur chaque appel (`recipe_assistant_turn`).
  final String cle;
  final String libelle;
  final String adr;
}

/// Assistant de recette (ADR-015).
const kPosteAssistantRecette = 'recipe_assistant_turn';

/// Postes connus, dans l'ordre d'affichage.
const kPostesIa = [
  PosteIa(
    cle: kPosteAssistantRecette,
    libelle: 'Assistant de recette',
    adr: 'ADR-015',
  ),
];

/// Poste de [cle], ou `null` pour une clé inconnue de cette version.
PosteIa? posteIa(String cle) {
  for (final p in kPostesIa) {
    if (p.cle == cle) return p;
  }
  return null;
}

/// Libellé de [cle] ; une clé inconnue s'affiche telle quelle.
String libellePosteIa(String cle) => posteIa(cle)?.libelle ?? cle;
