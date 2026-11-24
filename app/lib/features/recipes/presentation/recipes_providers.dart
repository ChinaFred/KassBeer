import 'package:exchange/exchange.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../../equipment/presentation/equipment_providers.dart';
import '../domain/filtres_recettes.dart';
import '../domain/recipe.dart';
import 'apercu_recette.dart';
import 'recipe_calculations_view.dart';

/// Recettes du groupe, lues par tous les membres.
final recipesListProvider = StreamProvider.autoDispose<ListeLue<Recipe>>(
  (ref) => ref.watch(recipesRepositoryProvider).watchAll(),
  // Une panne s'affiche ; « Réessayer » relance la lecture.
  retry: (retryCount, error) => null,
);

/// Calculs refusés par `brewing/` déjà rapportés, par recette et par champ
/// (`evaluerRecette`) : un rapport par session, pas un par frappe ni par lecture.
final calculationReportsProvider = Provider<Set<String>>((ref) => <String>{});

/// Analyse d'un fichier choisi dans Recettes › Importer (`exchange/`). Les tests
/// la remplacent pour simuler une panne inattendue.
final analyseurFichierProvider = Provider<AnalyseFichier Function(List<int>)>(
  (ref) => analyserFichier,
);

/// Origine choisie dans la liste (« Toutes », « Les miennes », « Autres ») :
/// en mémoire pour la session, jamais en base ; remise à « Toutes » au
/// changement de compte.
class OrigineRecettesNotifier extends Notifier<OrigineRecettes> {
  @override
  OrigineRecettes build() {
    ref.watch(grantedAccessProvider.select((a) => a?.user.uid));
    return OrigineRecettes.toutes;
  }

  void choisir(OrigineRecettes origine) => state = origine;
}

final origineRecettesProvider =
    NotifierProvider<OrigineRecettesNotifier, OrigineRecettes>(
      OrigineRecettesNotifier.new,
    );

/// Filtres de la liste, partagés par les trois origines : en mémoire pour la
/// session, jamais en base ni sur l'appareil ; vidés au changement de compte.
class FiltresRecettesNotifier extends Notifier<FiltresRecettes> {
  @override
  FiltresRecettes build() {
    ref.watch(grantedAccessProvider.select((a) => a?.user.uid));
    return FiltresRecettes.vide;
  }

  void appliquer(FiltresRecettes filtres) => state = filtres;
}

final filtresRecettesProvider =
    NotifierProvider<FiltresRecettesNotifier, FiltresRecettes>(
      FiltresRecettesNotifier.new,
    );

/// Clé d'un aperçu mémorisé : la recette n'a pas changé (même `updated_at`,
/// aucune écriture en attente) et son équipement donne le même rendement.
typedef _CleApercu = ({DateTime updatedAt, Type equipement, double? rendement});

/// Aperçus calculés des recettes de la liste, par identifiant : recalculés à
/// une nouvelle lecture des recettes ou des équipements, jamais à une frappe
/// dans la recherche ni à un changement de filtre. Une recette inchangée
/// garde son aperçu.
final apercusRecettesProvider =
    Provider.autoDispose<Map<String, ApercuRecette>>(
      (ref) => _apercus(ref, ref.watch(_memoApercusProvider)),
    );

/// Aperçus déjà calculés, gardés d'une lecture à l'autre tant que la liste
/// est ouverte.
final _memoApercusProvider =
    Provider.autoDispose<Map<String, (_CleApercu, ApercuRecette)>>(
      (ref) => <String, (_CleApercu, ApercuRecette)>{},
    );

Map<String, ApercuRecette> _apercus(
  Ref ref,
  Map<String, (_CleApercu, ApercuRecette)> memo,
) {
  final list = ref.watch(recipesListProvider).value;
  if (list == null) return const {};
  final equipment = ref.watch(equipmentListProvider);
  final offline = ref.watch(
    grantedAccessProvider.select((a) => a?.offline ?? false),
  );
  final errors = ref.read(errorReportServiceProvider);
  final reported = ref.read(calculationReportsProvider);
  final result = <String, ApercuRecette>{};
  for (final recipe in list.valides) {
    final equipement = equipementDe(
      recipe.content.equipmentId,
      equipment,
      offline: offline,
    );
    final updatedAt = recipe.updatedAt;
    final cle = updatedAt == null || recipe.hasPendingWrites
        ? null
        : (
            updatedAt: updatedAt,
            equipement: equipement.runtimeType,
            rendement: equipement.efficiency,
          );
    final connu = memo[recipe.id];
    if (cle != null && connu != null && connu.$1 == cle) {
      result[recipe.id] = connu.$2;
      continue;
    }
    final apercu = apercuDe(
      recipe,
      equipement,
      errors: errors,
      reported: reported,
    );
    if (cle != null) memo[recipe.id] = (cle, apercu);
    result[recipe.id] = apercu;
  }
  return result;
}
