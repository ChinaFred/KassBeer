import 'dart:async';

import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/admin/domain/postes_ia.dart';
import 'package:kass_beer/features/ai/data/ai_repository.dart';
import 'package:kass_beer/features/ai/domain/comptes_ia.dart';
import 'package:kass_beer/features/ai/domain/reglages_ia.dart';
import 'package:kass_beer/features/recipes/data/assistant_repository.dart';
import 'package:kass_beer/features/recipes/domain/assistant_recette.dart';

/// Réglage de test du poste de l'assistant.
const reglageAssistant = ReglagePosteIa(
  modele: 'claude-sonnet-5-5',
  effort: 'medium',
  ouvertAuxMembres: false,
  toursParJour: 20,
  toursFondateurParJour: 60,
  toursParConversation: 20,
);

/// Politique lue qui porte [reglage] pour l'assistant.
LectureIa<PolitiqueIa> politiqueLue(
  ReglagePosteIa reglage, {
  bool fromCache = false,
}) => LectureIa(
  DocumentTrouve(
    PolitiqueIa({kPosteAssistantRecette: ReglagePosteLu(reglage)}),
  ),
  fromCache: fromCache,
);

/// Grille de test : Sonnet 5.5 et Haiku 5.5 (Haiku sans effort).
GrilleTarifaire uneGrille({DateTime? verifieeLe}) => GrilleTarifaire(
  verifieeLe: verifieeLe ?? DateTime(2026, 11, 1),
  source: 'Page des tarifs d\'Anthropic',
  modeles: const [
    ModeleTarife(
      id: 'claude-sonnet-5-5',
      libelle: 'Sonnet 5.5',
      entree: 2,
      sortie: 10,
      ecritureCache: 2.5,
      lectureCache: 0.2,
      efforts: ['low', 'medium', 'high'],
    ),
    ModeleTarife(
      id: 'claude-haiku-5-5',
      libelle: 'Haiku 5.5',
      entree: 0.1,
      sortie: 0.5,
      ecritureCache: 0.125,
      lectureCache: 0.01,
      efforts: [],
    ),
  ],
);

/// Comptes d'un poste pour un mois.
ComptesPoste desComptes({
  int appels = 0,
  int echecs = 0,
  int sansMontant = 0,
  double montant = 0,
}) => ComptesPoste(
  appels: appels,
  echecs: echecs,
  sansMontant: sansMontant,
  jetonsEntree: 98000,
  jetonsCacheEcrits: 2500,
  jetonsCacheLus: 20000,
  jetonsSortie: 15000,
  montantUsd: montant,
);

/// Réglages et comptes de l'IA en mémoire. Une valeur `Object` non lecture
/// est levée par la lecture correspondante.
class FakeAiRepository implements AiRepository {
  Object politique = const LectureIa<PolitiqueIa>(
    DocumentAbsent(),
    fromCache: false,
  );
  Object grille = const LectureIa<GrilleTarifaire>(
    DocumentAbsent(),
    fromCache: false,
  );
  Object quotas = const LectureIa<QuotasIa>(DocumentAbsent(), fromCache: false);
  Object compteMois = const LectureIa<CompteMoisIa>(
    DocumentAbsent(),
    fromCache: false,
  );

  /// Comptes de chaque mois `AAAA-MM`, ou erreur à lever.
  final comptes = <String, Object>{};

  int lecturesPolitique = 0;
  int lecturesQuotas = 0;
  int lecturesCompteMois = 0;
  final moisLus = <String>[];

  /// Enregistrements reçus par `saveAiSettings`.
  final enregistrements = <({String kind, Object value})>[];

  /// Refus à lever au prochain enregistrement.
  EchecReglagesIa? refus;

  Future<T> _rendre<T>(Object v) async {
    if (v is T) return v as T;
    throw v;
  }

  @override
  Future<LectureIa<PolitiqueIa>> lirePolitique() {
    lecturesPolitique++;
    return _rendre(politique);
  }

  @override
  Future<LectureIa<GrilleTarifaire>> lireGrille() => _rendre(grille);

  @override
  Future<LectureIa<QuotasIa>> lireQuotas(String uid) {
    lecturesQuotas++;
    return _rendre(quotas);
  }

  @override
  Future<LectureIa<CompteMoisIa>> lireCompteMois(String mois, String uid) {
    lecturesCompteMois++;
    moisLus.add(mois);
    return _rendre(compteMois);
  }

  @override
  Future<ComptesDuMois> listerComptesMois(String mois) => _rendre(
    comptes[mois] ??
        const ComptesDuMois(comptes: [], fromCache: false, tronque: false),
  );

  @override
  Future<void> enregistrer({
    required String kind,
    required Object value,
  }) async {
    enregistrements.add((kind: kind, value: value));
    final r = refus;
    refus = null;
    if (r != null) throw r;
  }
}

/// Callable de l'assistant simulée : chaque envoi prend la réponse suivante
/// de [reponses] (une [ReponseAssistant] ou une erreur à lever).
class FakeAssistantRepository implements AssistantRepository {
  final reponses = <Object>[];
  final envois = <Map<String, Object?>>[];

  /// Réponse retenue jusqu'à ce que ce `Completer` soit complété.
  Completer<void>? attente;

  @override
  Future<ReponseAssistant> envoyer(Map<String, Object?> arguments) async {
    envois.add(arguments);
    final retenue = attente;
    if (retenue != null) await retenue.future;
    if (reponses.isEmpty) throw StateError('aucune réponse prévue');
    final r = reponses.removeAt(0);
    if (r is ReponseAssistant) return r;
    throw r;
  }
}
