// Crochet de chargement (node --import) : refuse toute résolution de @anthropic-ai/sdk.
// Sert à vérifier qu'un module s'importe sans charger le SDK (ADR-013, P54).

import { registerHooks } from "node:module";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@anthropic-ai/sdk" || specifier.startsWith("@anthropic-ai/sdk/")) {
      throw new Error("SDK d'Anthropic chargé : interdit à l'import (P54)");
    }
    return nextResolve(specifier, context);
  },
});
