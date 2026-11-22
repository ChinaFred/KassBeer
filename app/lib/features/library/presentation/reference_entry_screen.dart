import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/router/page_de_coquille.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/domain/beerjson.dart';
import '../domain/referentiel.dart';
import 'couleur_ebc.dart';
import 'libelles_bibliotheque.dart';
import 'library_providers.dart';
import 'section_aromes.dart';
import 'section_aromes_levure.dart';

/// Textes des états d'une fiche de la Bibliothèque.
abstract final class TextesFicheBibliotheque {
  static const loadError =
      'Impossible de lire cette fiche. L\'erreur est signalée à '
      'l\'administrateur.';
  static const absent = 'Cette fiche n\'existe pas ou a été retirée.';
  static const offline =
      'Fiche indisponible hors ligne. Elle s\'ouvre au retour du réseau.';
  static const loading = 'Chargement de la fiche';
  static const unreadable =
      'Cette fiche ne peut pas s\'afficher. L\'erreur est signalée à '
      'l\'administrateur.';

  /// Bouton de la fiche ouverte à côté de la liste, et de ses états absente
  /// ou illisible.
  static const fermer = 'Fermer la fiche';

  /// Annonce aux lecteurs d'écran d'une fiche ouverte à côté de la liste.
  static String ouverte(String nom) => 'Fiche ouverte : $nom';
}

/// Ferme la fiche ouverte à côté de la liste : dépile une fiche ouverte par
/// `push` par-dessus une autre page (« Voir le style » depuis une recette
/// publique), qui revient à cette page ; sinon, ouvre le segment, qui montre
/// l'invite. « Fermer la fiche » et la touche Échap passent par elle.
void fermerFicheBibliotheque(
  BuildContext context,
  SegmentBibliotheque segment,
) {
  if (pageEmpilee(context)) {
    context.pop();
  } else {
    context.go(AppRoutes.librarySegment(segment.slug));
  }
}

/// Fiche ouverte à côté de la liste (Bibliothèque en large) : « Fermer la
/// fiche », premier élément de la colonne, puis [child]. La touche Échap est
/// posée sur les deux colonnes (`BibliothequeCoteACote`). L'en-tête de la colonne annonce
/// « Fiche ouverte : » suivi du nom aux lecteurs d'écran à chaque fiche ouverte ;
/// [nom] est `null` tant que la fiche n'est pas lue.
class FicheCoteACote extends StatelessWidget {
  const FicheCoteACote({
    super.key,
    required this.nom,
    required this.onFermer,
    required this.child,
  });

  final String? nom;
  final VoidCallback onFermer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nom = this.nom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          liveRegion: nom != null,
          label: nom == null ? null : TextesFicheBibliotheque.ouverte(nom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: TextesFicheBibliotheque.fermer,
                onPressed: onFermer,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// État d'une fiche lue par `get()` : chargement, panne, absente, absente du cache
/// hors ligne, illisible ; `null` quand la fiche est trouvée.
Widget? etatFiche<T>({
  required AsyncValue<RechercheDocument<T>> async,
  required bool offline,
  required VoidCallback onRetry,
  required VoidCallback onBack,
  required String retour,
}) {
  final value = async.value;
  final back = FilledButton(onPressed: onBack, child: Text(retour));
  if (value == null) {
    if (!async.hasError) {
      return const EtatChargement(label: TextesFicheBibliotheque.loading);
    }
    if (offline) {
      return EtatVide(
        icon: Icons.cloud_off,
        message: TextesFicheBibliotheque.offline,
        action: FilledButton(
          onPressed: onRetry,
          child: const Text('Réessayer'),
        ),
      );
    }
    return EtatErreur(
      message: TextesFicheBibliotheque.loadError,
      retrying: async.isLoading,
      retryingLabel: 'Lecture en cours',
      onRetry: onRetry,
    );
  }
  return switch (value) {
    DocumentTrouve() => null,
    DocumentAbsent() => EtatVide(
      icon: Icons.search_off,
      message: TextesFicheBibliotheque.absent,
      action: back,
    ),
    DocumentAbsentDuCache() => EtatVide(
      icon: Icons.cloud_off,
      message: TextesFicheBibliotheque.offline,
      action: back,
    ),
    DocumentIllisibleTrouve() => EtatVide(
      icon: Icons.error_outline,
      message: TextesFicheBibliotheque.unreadable,
      action: back,
    ),
  };
}

/// Section « Provenance » : une ligne courte par source (« Brewtarget 5.2.3 ·
/// licence GPL-3.0 · relevé le 8 novembre 2026 »), sans doublon, et le lien
/// vers « Sources des données », qui donne le fichier et le commit.
class SectionProvenance extends StatelessWidget {
  const SectionProvenance({super.key, required this.provenance});

  final List<Provenance> provenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreSection('Provenance'),
        if (provenance.isEmpty) const TexteAbsent('Provenance non renseignée.'),
        for (final ligne in lignesProvenance(provenance))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(ligne, style: theme.textTheme.bodyMedium),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(context.push(AppRoutes.dataSources)),
            icon: const Icon(Icons.info_outline),
            label: const Text('Sources des données'),
          ),
        ),
      ],
    );
  }
}

/// Fiche d'un style ou d'un ingrédient : valeurs, plages, provenance et licence.
/// [coteACote] : fiche ouverte à côté de la liste, dans [FicheCoteACote].
class ReferenceEntryScreen extends ConsumerWidget {
  const ReferenceEntryScreen({
    super.key,
    required this.segment,
    required this.id,
    this.coteACote = false,
  });

  final SegmentBibliotheque segment;
  final String id;
  final bool coteACote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nature = segment.nature!;
    final cle = (nature: nature, id: id);
    final async = ref.watch(ficheReferentielProvider(cle));
    void fermer() => coteACote
        ? fermerFicheBibliotheque(context, segment)
        : context.go(AppRoutes.librarySegment(segment.slug));
    final etat = etatFiche(
      async: async,
      offline: ref.watch(grantedAccessProvider)?.offline ?? false,
      onRetry: () => ref.invalidate(ficheReferentielProvider(cle)),
      onBack: fermer,
      retour: coteACote
          ? TextesFicheBibliotheque.fermer
          : 'Revenir à la bibliothèque',
    );
    final fiche = switch (async.value) {
      DocumentTrouve<FicheReferentiel>(:final value) when etat == null => value,
      _ => null,
    };
    final contenu = fiche == null ? etat! : _Fiche(fiche: fiche);
    if (!coteACote) return contenu;
    return FicheCoteACote(nom: fiche?.name, onFermer: fermer, child: contenu);
  }
}

class _Fiche extends StatelessWidget {
  const _Fiche({required this.fiche});

  final FicheReferentiel fiche;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fiche;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Semantics(
            header: true,
            child: Text(f.name, style: theme.textTheme.headlineSmall),
          ),
          if (f.aliases.isNotEmpty)
            Text('Autres noms : ${f.aliases.join(', ')}', style: muted),
          ..._valeurs(f),
          if (f is FicheHoublon) SectionAromes(id: f.id),
          if (f is FicheLevure)
            SectionAromesLevure(id: f.id, temperature: f.temperature),
          SectionProvenance(provenance: f.provenance),
        ],
      ),
    );
  }

  List<Widget> _valeurs(FicheReferentiel f) => switch (f) {
    FicheStyle() => [
      const TitreSection('Classement'),
      LigneFiche(label: 'Code', value: f.styleId),
      LigneFiche(label: 'Catégorie', value: _categorie(f)),
      LigneFiche(
        label: 'Type',
        value: f.type == null ? null : libelleTypeStyle(f.type!),
      ),
      LigneFiche(label: 'Guide', value: f.styleGuide),
      const TitreSection('Plages'),
      LigneFiche(
        label: 'Densité initiale',
        value: formatPlage(f.og, formatDensite),
      ),
      LigneFiche(
        label: 'Densité finale',
        value: formatPlage(f.fg, formatDensite),
      ),
      LigneFiche(label: 'Degré', value: formatPlage(f.abv, formatDegre)),
      LigneFiche(label: 'Amertume', value: formatPlage(f.ibu, formatIbu)),
      LigneFiche(label: 'Couleur', value: formatPlage(f.color, formatEbc)),
      if (f.color case final couleur?) BarreCouleurEbc(plage: couleur),
    ],
    FicheFermentable() => [
      const TitreSection('Valeurs'),
      if (f.labelFr != null)
        LigneFiche(label: 'Nom français', value: f.labelFr),
      LigneFiche(
        label: 'Type',
        value: f.type == null ? null : typesFermentable.libelle(f.type!),
      ),
      LigneFiche(
        label: 'Couleur',
        value: f.colorEbc == null ? null : formatEbc(f.colorEbc!),
        avant: f.colorEbc == null ? null : PastilleEbc(ebc: f.colorEbc!),
      ),
      LigneFiche(
        label: 'Rendement d\'extrait',
        value: f.yieldPct == null ? null : formatPourcent(f.yieldPct!),
      ),
      LigneFiche(label: 'Producteur', value: f.producer),
      LigneFiche(
        label: 'Origine',
        value: origineAffichee(f.originFr, f.origin),
      ),
    ],
    FicheHoublon() => [
      const TitreSection('Valeurs'),
      if (f.labelFr != null)
        LigneFiche(label: 'Nom français', value: f.labelFr),
      LigneFiche(
        label: 'Forme',
        value: f.form == null ? null : formesHoublon.libelle(f.form!),
      ),
      LigneFiche(
        label: 'Acides alpha',
        value: f.alphaPct == null ? null : formatPourcent(f.alphaPct!),
      ),
      LigneFiche(
        label: 'Acides bêta',
        value: f.betaPct == null ? null : formatPourcent(f.betaPct!),
      ),
      LigneFiche(
        label: 'Usage',
        value: f.purpose == null ? null : libelleUsageHoublon(f.purpose!),
      ),
      LigneFiche(
        label: 'Origine',
        value: origineAffichee(f.originFr, f.origin),
      ),
    ],
    FicheLevure() => [
      const TitreSection('Valeurs'),
      LigneFiche(
        label: 'Producteur',
        value: producteurLevure(f.producer, f.productId),
      ),
      LigneFiche(
        label: 'Type',
        value: f.type == null ? null : typesLevure.libelle(f.type!),
      ),
      LigneFiche(
        label: 'Forme',
        value: f.form == null ? null : formesLevure.libelle(f.form!),
      ),
      LigneFiche(
        label: 'Atténuation',
        value: formatPlage(f.attenuation, formatPourcent),
      ),
      LigneFiche(
        label: 'Température de fermentation',
        value: formatPlage(f.temperature, formatCelsius),
      ),
      LigneFiche(
        label: 'Floculation',
        value: f.flocculation == null
            ? null
            : libelleFloculation(f.flocculation!),
      ),
    ],
    FicheDivers() => [
      const TitreSection('Valeurs'),
      if (f.labelFr != null)
        LigneFiche(label: 'Nom français', value: f.labelFr),
      LigneFiche(
        label: 'Type',
        value: f.type == null ? null : typesAjout.libelle(f.type!),
      ),
    ],
  };

  /// « 21 · IPA », le numéro seul ou le nom seul.
  String? _categorie(FicheStyle f) {
    final parts = [?f.categoryId, ?f.category];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
