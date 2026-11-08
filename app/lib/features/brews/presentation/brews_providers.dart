import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../domain/brew.dart';
import '../domain/brew_event.dart';

/// Brassins du groupe, lus par tous les membres.
final brewsListProvider = StreamProvider.autoDispose<ListeLue<Brew>>(
  (ref) => ref.watch(brewsRepositoryProvider).watchAll(),
  retry: (retryCount, error) => null,
);

/// Saisies d'un brassin.
final brewEventsProvider = StreamProvider.autoDispose
    .family<ListeLue<BrewEvent>, String>(
      (ref, brewId) => ref.watch(brewsRepositoryProvider).watchEvents(brewId),
      retry: (retryCount, error) => null,
    );

/// Brassins passés par « Préparer le brassage » pendant cette session (PR5).
/// Mémoire de session seule : rien n'est écrit en base (PR4).
final preparedBrewsProvider = Provider<Set<String>>((ref) => <String>{});

/// Anomalies de chronologie déjà rapportées, par brassin et par événement : un
/// rapport par session, pas un par seconde.
final planReportsProvider = Provider<Set<String>>((ref) => <String>{});

/// Vrai une fois la reprise au lancement traitée (D-Q3) : une seule par session.
final repriseTraiteeProvider = Provider<List<bool>>((ref) => [false]);

/// Textes des états d'une page de brassin (fiche, préparation, écran du jour).
const textesBrassin = TextesDocument(
  chargement: 'Chargement du brassin',
  lectureImpossible: 'Impossible de lire les brassins.',
  absent: 'Ce brassin n\'existe pas ou a été supprimé.',
  horsLigne: 'Brassin indisponible hors ligne.',
  illisible:
      'Ce brassin est illisible : une valeur enregistrée est inattendue.',
  retour: 'Revenir aux brassins',
);
