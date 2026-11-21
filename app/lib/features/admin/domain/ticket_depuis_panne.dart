import 'package:flutter/foundation.dart';

import '../../../core/presentation/formats.dart';
import '../../tickets/domain/ticket.dart';
import '../../tickets/domain/ticket_screens.dart';
import 'error_report.dart';
import 'log_entry.dart';

/// Ticket « Analyser » tiré d'un rapport d'erreur ou d'une entrée de journal
/// (ticket #67).
///
/// Le titre et la description partent sur une Issue publique (P24, P49) : ils
/// ne reprennent que des champs écrits par le code (fonctionnalité, version,
/// plateforme, fonction, gravité, heure), le nom de la classe de l'exception,
/// les lignes de pile du code de l'application et l'identifiant du rapport ou
/// de l'entrée. Ni le message de l'erreur, ni le contexte, ni l'uid, ni le
/// message ou les données d'un journal. Chaque champ repris est contrôlé par
/// sa forme : un rapport est écrit par un membre, une valeur hors forme est
/// omise. Une valeur de la bonne forme reste écrite par un membre
/// (fonctionnalité, identifiant du rapport, nom d'une fonction dans une trame
/// de pile) : l'administrateur relit le titre et la description avant
/// l'envoi.
///
/// La première ligne de la description porte l'identifiant : Admin › Rapports
/// d'erreur et Admin › Journaux en dérivent la marque « Ticket #N créé le… »,
/// sans rien écrire sur le rapport.

/// Origine d'un ticket « Analyser ».
enum NaturePanne {
  rapport(
    'Rapport : ',
    'sert à marquer le rapport',
    'Créé depuis Admin › Rapports d\'erreur.',
  ),
  journal(
    'Entrée de journal : ',
    'sert à marquer l\'entrée',
    'Créé depuis Admin › Journaux.',
  );

  const NaturePanne(this.prefixe, this.usage, this.origine);

  /// Début de la première ligne de la description.
  final String prefixe;
  final String usage;

  /// Deuxième ligne de la description.
  final String origine;

  /// « Rapport : er-1 (ne pas modifier : sert à marquer le rapport) ».
  String entete(String id) => '$prefixe$id (ne pas modifier : $usage)';
}

/// Rapport ou entrée de journal désigné par la première ligne d'un ticket.
typedef ClePanne = ({NaturePanne nature, String id});

/// Lignes de pile gardées au plus.
const kLignesPileMax = 15;

const kTitreRapportParDefaut = 'Rapport d\'erreur à analyser';
const kTitreJournalParDefaut = 'Entrée de journal à analyser';
const kPileNonPubliee =
    'Pile non publiée : aucune ligne du code de l\'application.';

/// Identifiant d'un rapport (`error_reports/{id}`) ou `insertId` d'un
/// journal : seule forme publiée.
final _identifiant = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Nom de fonctionnalité écrit par le code (`admin.error_reports.copy`).
final _fonctionnalite = RegExp(r'^[a-z][a-z0-9_.]{0,59}$');

/// Version `X.Y.Z`, `+N` facultatif.
final _version = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}(\+\d{1,9})?$');

/// Nom de fonction d'un journal (`synctickets`).
final _fonction = RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,62}$');

/// Gravité d'un journal (`ERROR`).
final _gravite = RegExp(r'^[A-Z]{1,20}$');

/// Nom de classe d'une exception (`StateError`, `FirebaseException`).
final _classe = RegExp(r'^_?([A-Z][A-Za-z0-9_]{0,50})?(Exception|Error)$');

/// Trame de pile Dart du code de l'application, et rien d'autre :
/// `#1      RecipeEditor.save (package:kass_beer/…/recipe_editor.dart:120:7)`.
/// Aucun texte libre : une ligne d'une autre forme (pile du web compilé,
/// texte ajouté) est écartée.
final _trame = RegExp(
  r'^#\d{1,3}\s+(new )?[A-Za-z0-9_$.]{1,100}(\.<anonymous closure>)*\s'
  r'\(package:kass_beer/[a-z0-9_/]{1,150}\.dart:\d{1,6}(:\d{1,6})?\)$',
);

/// Suite de 28 caractères alphanumériques : forme d'un uid Firebase.
final _formeUid = RegExp(r'(?<![A-Za-z0-9])[A-Za-z0-9]{28}(?![A-Za-z0-9])');

/// Nom de la classe de l'exception : le mot avant le premier « : » de la
/// première ligne non vide de [erreur], s'il a la forme d'un nom de classe
/// qui finit par `Exception` ou `Error` (`StateError`, `FirebaseException`) ;
/// `null` sinon. Le reste du message n'est jamais lu.
String? typeException(String erreur) {
  for (final ligne in erreur.split('\n')) {
    final texte = ligne.trim();
    if (texte.isEmpty) continue;
    final deuxPoints = texte.indexOf(':');
    if (deuxPoints <= 0) return null;
    final mot = texte.substring(0, deuxPoints).trim();
    return _classe.hasMatch(mot) ? mot : null;
  }
  return null;
}

/// Lignes de [pile] du code de l'application, [kLignesPileMax] au plus, dans
/// l'ordre : seules les trames de la forme [_trame]. Une trame qui porte un
/// chemin `users/` ou `members/` ou un mot de la forme d'un uid est écartée.
List<String> lignesPileApplication(String? pile) {
  if (pile == null) return const [];
  final lignes = <String>[];
  for (final brute in pile.split('\n')) {
    if (lignes.length == kLignesPileMax) break;
    final ligne = brute.trim();
    if (!_trame.hasMatch(ligne)) continue;
    if (ligne.contains('users/') ||
        ligne.contains('members/') ||
        _formeUid.hasMatch(ligne)) {
      continue;
    }
    lignes.add(ligne);
  }
  return lignes;
}

String? _si(String? valeur, RegExp forme) {
  final v = valeur?.trim();
  return v != null && forme.hasMatch(v) ? v : null;
}

/// Coupe [titre] à [kTicketTitleMaxLength] caractères.
String _titre(String titre) => titre.length > kTicketTitleMaxLength
    ? titre.substring(0, kTicketTitleMaxLength).trimRight()
    : titre;

/// Description : [tete], puis la pile (retirée par la fin pour tenir dans
/// [kTicketDescriptionMaxLength]), puis une ligne vide où l'administrateur
/// décrit ce qu'il a vu.
String _description(List<String> tete, List<String>? pile) {
  String assembler(List<String>? lignes) => [
    ...tete,
    if (lignes != null) ...[
      'Pile (code de l\'application) :',
      if (lignes.isEmpty) kPileNonPubliee else ...lignes,
    ],
    '',
    '',
  ].join('\n');

  if (pile == null) return assembler(null);
  final gardees = [...pile];
  var texte = assembler(gardees);
  while (texte.length > kTicketDescriptionMaxLength && gardees.isNotEmpty) {
    gardees.removeLast();
    texte = gardees.isEmpty ? assembler(null) : assembler(gardees);
  }
  return texte;
}

/// Brouillon « Analyser » d'un rapport d'erreur : type Bug, écran inconnu.
TicketBrouillon brouillonDepuisRapport(ErrorReport rapport) {
  final id = _si(rapport.id, _identifiant);
  final fonctionnalite = _si(rapport.feature, _fonctionnalite);
  final version = _si(rapport.appVersion, _version);
  final type = typeException(rapport.error);
  final jour = rapport.createdAt;
  final resume = [
    ?fonctionnalite,
    if (version != null) 'v$version',
    rapport.libellePlateforme,
    if (jour != null) formatDateLongue(jour),
  ].join(' · ');
  final titre = switch ((fonctionnalite, type)) {
    (final String f, final String t) => 'Erreur $f : $t',
    (final String f, null) => 'Erreur $f',
    (null, final String t) => 'Erreur $t',
    (null, null) => kTitreRapportParDefaut,
  };
  return TicketBrouillon(
    type: TicketType.bug,
    title: _titre(titre),
    description: _description([
      if (id != null) NaturePanne.rapport.entete(id),
      NaturePanne.rapport.origine,
      resume,
      if (type != null) 'Type : $type',
    ], lignesPileApplication(rapport.stackTrace)),
    screen: kTicketScreenUnknown,
  );
}

/// Brouillon « Analyser » d'une entrée de journal : type Bug, écran inconnu.
/// Ni le message ni les données de l'entrée (P49).
TicketBrouillon brouillonDepuisJournal(EntreeJournal entree) {
  final id = _si(entree.insertId, _identifiant);
  final fonction = _si(entree.fonction, _fonction);
  final gravite = _si(entree.severity, _gravite);
  final heure = entree.horodatage;
  return TicketBrouillon(
    type: TicketType.bug,
    title: _titre(
      fonction == null ? kTitreJournalParDefaut : 'Erreur dans $fonction',
    ),
    description: _description([
      if (id != null) NaturePanne.journal.entete(id),
      NaturePanne.journal.origine,
      if (fonction != null) 'Fonction : $fonction',
      if (gravite != null) 'Gravité : $gravite',
      if (heure != null) 'Heure : ${formatJourCourtHeureSecondes(heure)}',
    ], null),
    screen: kTicketScreenUnknown,
  );
}

/// Clé du rapport ou de l'entrée nommé par la première ligne de
/// [description] ; `null` si elle ne commence pas par « Rapport : » ou
/// « Entrée de journal : » suivi d'un identifiant.
ClePanne? clePanneDeDescription(String description) {
  final premiere = description.trimLeft().split('\n').first.trim();
  for (final nature in NaturePanne.values) {
    if (!premiere.startsWith(nature.prefixe)) continue;
    final reste = premiere.substring(nature.prefixe.length).trim();
    final id = reste.split(RegExp(r'\s')).first;
    return _identifiant.hasMatch(id) ? (nature: nature, id: id) : null;
  }
  return null;
}

/// Tickets d'un rapport ou d'une entrée : le plus récent et leur nombre.
@immutable
class MarquePanne {
  const MarquePanne({required this.recent, required this.nombre});

  final Ticket recent;
  final int nombre;

  /// « Ticket #12 créé le 14 novembre 2026 », « Ticket créé, non publié »,
  /// suivi de « (2 tickets) » s'il y en a plusieurs.
  String get libelle {
    final numero = recent.issueNumber;
    final cree = recent.createdAt;
    final base = numero == null
        ? 'Ticket créé, non publié'
        : cree == null
        ? 'Ticket #$numero'
        : 'Ticket #$numero créé le ${formatDateLongue(cree)}';
    return nombre > 1 ? '$base ($nombre tickets)' : base;
  }
}

/// Index clé → tickets, d'après la première ligne de chaque description.
Map<ClePanne, MarquePanne> indexTicketsParPanne(Iterable<Ticket> tickets) {
  final parCle = <ClePanne, List<Ticket>>{};
  for (final t in tickets) {
    final cle = clePanneDeDescription(t.description);
    if (cle != null) parCle.putIfAbsent(cle, () => []).add(t);
  }
  return {
    for (final MapEntry(:key, :value) in parCle.entries)
      key: MarquePanne(
        recent: (value..sort(compareTicketsRecentFirst)).first,
        nombre: value.length,
      ),
  };
}
