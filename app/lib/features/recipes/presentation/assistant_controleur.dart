import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../library/data/library_repository.dart';
import '../../library/domain/referentiel.dart';
import '../data/assistant_repository.dart';
import '../domain/assistant_recette.dart';
import '../domain/import_recettes.dart' show indexBibliotheque;
import '../domain/recipe.dart';
import 'recipe_calculations_view.dart';

/// Assistant de recette (ADR-015), dépôt de la callable `recipeAssistantTurn`.
/// Fourni par `main.dart` ; les tests y mettent un double. Déclaré ici, hors
/// de `core/providers.dart` : l'écran du jour et les journées n'importent
/// aucun fichier de l'assistant (P2, P60).
final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => throw UnimplementedError('assistantRepositoryProvider non fourni'),
);

/// Conversation de l'assistant, gardée en mémoire tant que l'éditeur est
/// ouvert (ADR-015, section 8) : fermer le panneau la garde, fermer
/// l'éditeur la perd. Un appel part sur « Envoyer » ou « Résumer et
/// continuer » seulement, jamais sur une frappe, à l'ouverture ou au retour
/// du réseau (P60).
class ControleurAssistant extends ChangeNotifier {
  ControleurAssistant({
    required AssistantRepository repository,
    required ErrorReportService errorReportService,
    Random? random,
  }) : _repository = repository,
       _errors = errorReportService,
       _random = random,
       idConversation = nouvelIdConversation(random);

  final AssistantRepository _repository;
  final ErrorReportService _errors;
  final Random? _random;

  /// Champ du message ; gardé hors ligne et après un échec.
  final champ = TextEditingController();

  String idConversation;

  /// Messages des tours aboutis, en rôles alternés : la personne puis
  /// l'assistant. Un tour en échec n'y entre pas (P59).
  final List<MessageConversation> messages = [];

  /// Résumé de la conversation précédente, envoyé dans `summary` (jamais
  /// dans `history`) ; affiché en première bulle.
  String? resume;

  /// Message parti, en attente de la réponse.
  String? enAttente;

  /// Appel en cours : tour ou résumé.
  ModeAssistant? appelEnCours;

  /// Dernier échec, affiché au-dessus du champ ; retiré à l'envoi suivant.
  EchecAssistant? echec;

  /// Tours du jour rendus par le serveur au dernier appel.
  QuotaRendu? quota;

  /// Monte à chaque réponse reçue : l'écran l'annonce.
  int reponsesRecues = 0;

  bool _ferme = false;

  bool get enCours => appelEnCours != null;

  /// Tours aboutis de cette conversation.
  int get toursFaits => messages.length ~/ 2;

  /// La conversation a au moins un tour ou un résumé : la quitter la perd.
  bool get aDuContenu => messages.isNotEmpty || resume != null;

  /// Envoie le message du champ. [contexte] lit la recette, ses calculs, son
  /// équipement, son style et les arômes au moment de l'envoi ; `null` :
  /// recette illisible, déjà rapportée.
  Future<void> envoyer(Future<ContexteAssistant?> Function() contexte) async {
    final message = champ.text.trim();
    if (enCours || message.isEmpty) return;
    appelEnCours = ModeAssistant.tour;
    enAttente = message;
    echec = null;
    champ.clear();
    _notifier();
    try {
      final ctx = await contexte();
      if (_ferme) return;
      if (ctx == null) {
        // Brouillon illisible, déjà rapporté par [contexte].
        _echouer(
          const EchecAssistant(CauseEchecAssistant.recetteIllisible),
          message,
        );
        return;
      }
      final reponse = await _repository.envoyer(
        argumentsAssistant(
          idConversation: idConversation,
          historique: List.unmodifiable(messages),
          mode: ModeAssistant.tour,
          message: message,
          resume: resume,
          contexte: ctx,
        ),
      );
      if (_ferme) return;
      messages
        ..add(MessageConversation(AuteurMessage.personne, message))
        ..add(MessageConversation(AuteurMessage.assistant, reponse.texte));
      quota = reponse.quota ?? quota;
      enAttente = null;
      appelEnCours = null;
      reponsesRecues++;
      _notifier();
    } on EchecAssistant catch (e) {
      // Déjà rapporté par le dépôt, avec la raison et des longueurs.
      _echouer(e, message);
    } catch (error, stackTrace) {
      _inattendu(error, stackTrace, message);
    }
  }

  /// « Résumer et continuer » : un tour en mode résumé ; le résumé ouvre une
  /// nouvelle conversation (amendement « cadrage du lot A1 » d'ADR-015).
  Future<void> resumer(Future<ContexteAssistant?> Function() contexte) async {
    if (enCours || messages.isEmpty) return;
    appelEnCours = ModeAssistant.resume;
    echec = null;
    _notifier();
    try {
      final ctx = await contexte();
      if (_ferme) return;
      if (ctx == null) {
        // Brouillon illisible, déjà rapporté par [contexte].
        _echouer(const EchecAssistant(CauseEchecAssistant.recetteIllisible));
        return;
      }
      final reponse = await _repository.envoyer(
        argumentsAssistant(
          idConversation: idConversation,
          historique: List.unmodifiable(messages),
          mode: ModeAssistant.resume,
          resume: resume,
          contexte: ctx,
        ),
      );
      if (_ferme) return;
      messages.clear();
      resume = reponse.texte;
      idConversation = nouvelIdConversation(_random);
      quota = reponse.quota ?? quota;
      appelEnCours = null;
      reponsesRecues++;
      _notifier();
    } on EchecAssistant catch (e) {
      // Déjà rapporté par le dépôt, avec la raison et des longueurs.
      _echouer(e);
    } catch (error, stackTrace) {
      _inattendu(error, stackTrace);
    }
  }

  /// Panne imprévue (lecture du contexte, bug) : rapportée sans texte, puis
  /// affichée comme un résultat inconnu ; l'appel en cours est toujours levé.
  void _inattendu(Object error, StackTrace stackTrace, [String? message]) {
    _errors.reportError(
      feature: 'recipes.assistant',
      error: error,
      stackTrace: stackTrace,
      context: 'panne imprévue du tour : ${error.runtimeType}',
    );
    _echouer(
      const EchecAssistant(CauseEchecAssistant.resultatInconnu),
      message,
    );
  }

  /// Vide la conversation et tire un nouvel identifiant. Le compte du jour
  /// ne change pas.
  void nouvelleConversation() {
    if (enCours) return;
    messages.clear();
    resume = null;
    echec = null;
    idConversation = nouvelIdConversation(_random);
    _notifier();
  }

  /// Le message revient dans le champ : l'historique finit toujours par une
  /// réponse (P59).
  void _echouer(EchecAssistant e, [String? message]) {
    if (_ferme) return;
    if (message != null && champ.text.trim().isEmpty) champ.text = message;
    quota = e.quota ?? quota;
    echec = e;
    enAttente = null;
    appelEnCours = null;
    _notifier();
  }

  void _notifier() {
    if (!_ferme) notifyListeners();
  }

  /// Texte de la conversation pour « Copier la conversation ».
  String texteCopie() => [
    if (resume case final r?) 'Résumé de la conversation précédente :\n$r',
    for (final m in messages)
      '${m.auteur == AuteurMessage.personne ? 'Vous' : 'Assistant'} : '
          '${m.texte}',
  ].join('\n\n');

  @override
  void dispose() {
    _ferme = true;
    champ.dispose();
    super.dispose();
  }
}

/// Données envoyées avec un tour, lues au moment de l'envoi (ADR-015,
/// section 5) : le brouillon que lit le bloc Calculs (U13), ses calculs
/// (U14), l'équipement choisi s'il est lu (U16), le style s'il désigne une
/// seule entrée de la Bibliothèque par son nom exact (U15), les arômes des
/// houblons résolus dans la Bibliothèque, 20 au plus (U17). Une lecture en
/// panne, déjà rapportée par le dépôt, laisse la donnée absente. `null` :
/// recette illisible (rapportée ici).
Future<ContexteAssistant?> contexteAssistant({
  required RecipeContent content,
  required CalculsRecette calculs,
  required EquipementRecette equipement,
  required LibraryRepository library,
  required ErrorReportService errors,
}) async {
  final Map<String, Object?> recette;
  try {
    recette = recettePourAssistant(content);
  } catch (error, stackTrace) {
    // Ni le texte de la recette ni le nom d'un ingrédient (P13).
    errors.reportError(
      feature: 'recipes.assistant',
      error: error,
      stackTrace: stackTrace,
      context: 'recette illisible pour l\'assistant : ${error.runtimeType}',
    );
    return null;
  }
  final (style, aromes) = await (
    _style(content.style, library),
    _aromes(content, library),
  ).wait;
  return ContexteAssistant(
    recette: recette,
    calculs: calculsPourAssistant(
      calculs.calculOuNul,
      champRefuse: switch (calculs) {
        CalculsImpossibles(:final field) => field,
        CalculsObtenus() => null,
      },
      rendementEmpatage: equipement.efficiency,
    ),
    equipement: switch (equipement) {
      EquipementConnu(:final equipment) => equipementPourAssistant(
        equipment.content,
      ),
      _ => null,
    },
    style: style,
    aromes: aromes,
  );
}

Future<Map<String, Object?>?> _style(
  String? nom,
  LibraryRepository library,
) async {
  final cherche = nom?.trim();
  if (cherche == null || cherche.isEmpty) return null;
  try {
    final index = await library.lireIndex(NatureReferentiel.styles);
    if (index is! DocumentTrouve<IndexReferentiel>) return null;
    final trouves = [
      for (final e in index.value.entrees)
        if (e.name == cherche) e,
    ];
    if (trouves.length != 1) return null;
    final fiche = await library.lireFiche(
      NatureReferentiel.styles,
      trouves.single.id,
    );
    return switch (fiche) {
      DocumentTrouve(value: final FicheStyle style) => stylePourAssistant(
        style,
      ),
      _ => null,
    };
  } catch (_) {
    // Déjà rapporté par le dépôt de la Bibliothèque : le style part absent.
    return null;
  }
}

Future<List<Map<String, Object?>>> _aromes(
  RecipeContent content,
  LibraryRepository library,
) async {
  final noms = houblonsDistincts(content);
  if (noms.isEmpty) return const [];
  final RechercheDocument<IndexReferentiel> index;
  try {
    index = await library.lireIndex(NatureReferentiel.hops);
  } catch (_) {
    // Déjà rapporté par le dépôt de la Bibliothèque : aucun arôme ne part.
    return const [];
  }
  if (index is! DocumentTrouve<IndexReferentiel>) return const [];
  final resolus = indexBibliotheque(index.value);
  final lus = await Future.wait([
    for (final nom in noms) _arome(nom, resolus.resoudre(nom)?.id, library),
  ]);
  return [for (final a in lus) ?a];
}

Future<Map<String, Object?>?> _arome(
  String nom,
  String? id,
  LibraryRepository library,
) async {
  if (id == null) return null;
  try {
    return switch (await library.lireAromesHoublon(id)) {
      DocumentTrouve(:final value) => aromesPourAssistant(nom, value),
      _ => null,
    };
  } catch (_) {
    // Déjà rapporté par le dépôt de la Bibliothèque : cet arôme part absent.
    return null;
  }
}
