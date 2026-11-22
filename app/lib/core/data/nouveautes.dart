import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/error_report_service.dart';

/// Asset écrit par `scripts/changelog-recent.mjs` depuis `documentation/CHANGELOG.md`.
const kNouveautesAsset = 'assets/changelog_recent.json';

/// Journal complet sur GitHub, entrées « technique » et versions plus récentes
/// comprises (ticket #114).
final kJournalComplet = Uri.parse(
  'https://github.com/ChinaFred/KassBeer/blob/main/documentation/CHANGELOG.md',
);

/// Une version de l'écran « Nouveautés » : son entrée « fonctionnel » du CHANGELOG.
@immutable
class Nouveaute {
  const Nouveaute({
    required this.version,
    required this.date,
    required this.summaries,
    required this.paragraphs,
  });

  /// « 0.1.13 », sans « v » ni numéro de build.
  final String version;

  /// Jour de la version, sans heure.
  final DateTime date;

  /// Résumés de la version, un par entrée « fonctionnel » qui en porte un
  /// (ligne « Résumé : » du CHANGELOG) ; vide pour les versions antérieures.
  final List<String> summaries;

  /// Détail, en texte simple, un paragraphe par chaîne ; une puce commence par
  /// « • ». Vide seulement si la version a un résumé.
  final List<String> paragraphs;
}

final RegExp _version = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Lit le JSON de [kNouveautesAsset], de la plus récente version à la plus ancienne.
///
/// Lève une [FormatException] sur un fichier mal formé : racine sans `versions`,
/// version qui n'a pas la forme `X.Y.Z`, date absente ou invalide, résumés ou
/// paragraphes absents, blancs ou qui ne sont pas des chaînes, version sans résumé
/// ni paragraphe. La longueur d'un résumé est bornée par le script qui écrit
/// l'asset. Aucune liste de repli.
List<Nouveaute> lireNouveautes(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('nouveautés : objet JSON attendu');
  }
  final versions = decoded['versions'];
  if (versions is! List<Object?>) {
    throw const FormatException('nouveautés : liste « versions » attendue');
  }
  return [
    for (final (index, item) in versions.indexed) _lireVersion(index, item),
  ];
}

Nouveaute _lireVersion(int index, Object? item) {
  FormatException invalide(String champ) =>
      FormatException('nouveautés : « $champ » invalide, version n° $index');

  if (item is! Map<String, Object?>) throw invalide('versions');
  final version = item['version'];
  if (version is! String || !_version.hasMatch(version)) {
    throw invalide('version');
  }
  final date = item['date'];
  final match = date is String ? _date.firstMatch(date) : null;
  if (match == null) throw invalide('date');
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw invalide('date');
  }
  bool blanc(Object? p) => p is! String || p.trim().isEmpty;
  final summaries = item['summaries'];
  if (summaries is! List<Object?> || summaries.any(blanc)) {
    throw invalide('summaries');
  }
  final paragraphs = item['paragraphs'];
  if (paragraphs is! List<Object?> ||
      (paragraphs.isEmpty && summaries.isEmpty) ||
      paragraphs.any(blanc)) {
    throw invalide('paragraphs');
  }
  return Nouveaute(
    version: version,
    date: parsed,
    summaries: List.unmodifiable(summaries.cast<String>()),
    paragraphs: List.unmodifiable(paragraphs.cast<String>()),
  );
}

/// Lit l'asset des nouveautés et journalise une panne avant de la relancer.
class NouveautesRepository {
  NouveautesRepository({
    required ErrorReportService errorReportService,
    required Future<String> Function() load,
  }) : _errors = errorReportService,
       _load = load;

  final ErrorReportService _errors;
  final Future<String> Function() _load;

  Future<List<Nouveaute>> lire() async {
    try {
      return lireNouveautes(await _load());
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'nouveautes',
        error: error,
        stackTrace: stackTrace,
        context: 'lecture de $kNouveautesAsset',
      );
      rethrow;
    }
  }
}

/// Source du JSON ; les tests la remplacent.
final nouveautesSourceProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => rootBundle.loadString(kNouveautesAsset),
);

final nouveautesRepositoryProvider = Provider<NouveautesRepository>(
  (ref) => NouveautesRepository(
    errorReportService: ref.watch(errorReportServiceProvider),
    load: ref.watch(nouveautesSourceProvider),
  ),
);

/// Versions à afficher. Une panne s'affiche ; « Réessayer » relance la lecture.
final nouveautesProvider = FutureProvider.autoDispose<List<Nouveaute>>(
  (ref) => ref.watch(nouveautesRepositoryProvider).lire(),
  retry: (retryCount, error) => null,
);
