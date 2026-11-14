import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/presentation/formats.dart';

/// Plateforme d'un rapport, lue dans `error_reports/{id}.platform`.
enum PlateformeRapport {
  android('android', 'Android'),
  web('web', 'Web');

  const PlateformeRapport(this.value, this.libelle);

  /// Valeur stockée dans Firestore.
  final String value;

  /// Libellé affiché.
  final String libelle;

  /// Plateforme de [value], ou `null` si elle est absente ou inconnue.
  static PlateformeRapport? fromValue(Object? value) {
    for (final p in values) {
      if (p.value == value) return p;
    }
    return null;
  }
}

/// Document `error_reports/{id}` (P13), lu par l'admin dans Admin › Rapports
/// d'erreur (ADR-011, J1). Les règles en fixent la forme : chaque champ est lu
/// tel quel, un champ absent ou vide reste `null`.
@immutable
class ErrorReport {
  const ErrorReport({
    required this.id,
    required this.error,
    this.createdAt,
    this.uid,
    this.feature,
    this.context,
    this.stackTrace,
    this.appVersion,
    this.platform,
  });

  static const plateformeInconnue = 'Plateforme inconnue';
  static const erreurSansMessage = 'Erreur sans message';

  final String id;

  /// Texte de l'erreur ; vide si le rapport n'en porte pas.
  final String error;

  /// Heure d'écriture (`created_at`, heure du serveur), en heure locale.
  final DateTime? createdAt;
  final String? uid;
  final String? feature;
  final String? context;
  final String? stackTrace;
  final String? appVersion;

  /// `null` : plateforme absente ou inconnue.
  final PlateformeRapport? platform;

  factory ErrorReport.fromFirestore(String id, Map<String, dynamic> data) {
    String? texte(String key) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    final created = data['created_at'];
    return ErrorReport(
      id: id,
      error: texte('error') ?? '',
      createdAt: created is Timestamp ? created.toDate().toLocal() : null,
      uid: texte('uid'),
      feature: texte('feature'),
      context: texte('context'),
      stackTrace: texte('stack_trace'),
      appVersion: texte('app_version'),
      platform: PlateformeRapport.fromValue(data['platform']),
    );
  }

  /// Première ligne non vide de [error], titre de la ligne repliée.
  String get premiereLigne {
    for (final line in error.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return erreurSansMessage;
  }

  /// Libellé de la plateforme.
  String get libellePlateforme => platform?.libelle ?? plateformeInconnue;

  /// Date, fonctionnalité et version, ce qui manque omis.
  String get resume {
    final at = createdAt;
    return [
      if (at != null) formatJourCourtHeure(at),
      ?feature,
      if (appVersion != null) 'v$appVersion',
    ].join(' · ');
  }

  /// Texte copié par « Copier le rapport » : résumé, plateforme, puis chaque
  /// section non vide.
  String get texteCopie {
    final buffer = StringBuffer('Rapport d\'erreur $id\n');
    final r = resume;
    if (r.isNotEmpty) buffer.writeln(r);
    buffer.writeln(libellePlateforme);
    void section(String titre, String? contenu) {
      if (contenu == null || contenu.isEmpty) return;
      buffer
        ..writeln()
        ..writeln(titre)
        ..writeln(contenu);
    }

    section('Erreur', error.isEmpty ? erreurSansMessage : error);
    section('Contexte', context);
    section('Pile d\'appels', stackTrace);
    section('Compte', uid);
    return buffer.toString().trimRight();
  }
}
