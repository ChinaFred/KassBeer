import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/error_report_service.dart';
import 'fichiers_web_stub.dart'
    if (dart.library.js_interop) 'fichiers_web.dart';

/// Choix d'un fichier de l'appareil et envoi d'un fichier produit (ADR-007) :
/// canal Kotlin `fr.kassbeer/files` sur Android, `package:web` sur le web. Aucun
/// greffon, aucune permission de stockage, rien sur le réseau.
abstract class EchangeFichiers {
  /// Ouvre le sélecteur du système. Sans [types], aucun filtre : le format se
  /// lit au contenu. Avec [types] (types MIME de [kMotifTypeMime], par exemple
  /// [kTypesImages]), le sélecteur ne propose que ces types ; le contenu reste
  /// contrôlé par l'appelant. Un fichier de plus de [maxOctets] est refusé
  /// avant sa lecture.
  Future<ResultatChoix> choisir({required int maxOctets, List<String>? types});

  /// Façons d'envoyer un fichier sur cette plateforme, dans l'ordre des boutons.
  List<ModeEnvoi> get modes;

  /// Envoie le fichier [nom] ([typeMime], [octets]) selon [mode].
  Future<ResultatEnvoi> envoyer(
    ModeEnvoi mode, {
    required String nom,
    required String typeMime,
    required Uint8List octets,
  });
}

/// Résultat d'un choix de fichier.
sealed class ResultatChoix {
  const ResultatChoix();
}

/// Sélecteur fermé sans choix.
class ChoixAnnule extends ResultatChoix {
  const ChoixAnnule();
}

/// Fichier choisi et lu.
class FichierChoisi extends ResultatChoix {
  const FichierChoisi(this.nom, this.octets);

  /// Nom affiché par le fournisseur ; il n'entre jamais dans un rapport.
  final String nom;
  final Uint8List octets;
}

/// Fichier plus gros que la borne ; [taille] en octets, `null` quand le
/// fournisseur ne la donne pas (lecture arrêtée à la borne).
class FichierTropGros extends ResultatChoix {
  const FichierTropGros(this.taille);

  final int? taille;
}

/// Ouverture ou lecture impossible (déjà rapportée).
class ChoixImpossible extends ResultatChoix {
  const ChoixImpossible();
}

/// Façon d'envoyer un fichier.
enum ModeEnvoi {
  /// Android : « Enregistrer », `ACTION_CREATE_DOCUMENT`.
  enregistrer('Enregistrer'),

  /// Android : « Partager le fichier », feuille de partage du système.
  partager('Partager le fichier'),

  /// Web : « Télécharger », lien `download`.
  telecharger('Télécharger');

  const ModeEnvoi(this.libelle);

  /// Libellé du bouton.
  final String libelle;
}

/// Résultat d'un envoi.
sealed class ResultatEnvoi {
  const ResultatEnvoi();
}

/// Fichier enregistré, téléchargé, ou confié à la feuille de partage.
class EnvoiFait extends ResultatEnvoi {
  const EnvoiFait();
}

/// Enregistrement annulé par l'utilisateur.
class EnvoiAnnule extends ResultatEnvoi {
  const EnvoiAnnule();
}

/// Envoi impossible (déjà rapporté).
class EnvoiImpossible extends ResultatEnvoi {
  const EnvoiImpossible();
}

/// Canal Android. Noms identiques dans `EchangeFichiers.kt` (P17).
const kCanalFichiers = 'fr.kassbeer/files';
const kMethodeChoisir = 'pickDocument';
const kMethodePartager = 'shareFile';
const kMethodeEnregistrer = 'saveDocument';

/// Types MIME admis par le filtre de [EchangeFichiers.choisir] : le même
/// motif que `EchangeFichiers.kt`, au plus [kTypesMax] types.
final kMotifTypeMime = RegExp(r'^[a-z]{1,20}/[a-z0-9.+*-]{1,60}$');
const kTypesMax = 10;

/// Images qu'un ticket accepte (« Choisir une image », ADR-008, T6) : toutes
/// sont décodées puis réencodées en PNG avant l'envoi.
const kTypesImages = ['image/png', 'image/jpeg', 'image/webp'];

/// Code d'erreur de `EchangeFichiers.kt` que le Dart distingue : fichier trop
/// gros. Les autres codes (`ALREADY_ACTIVE`, `NO_PICKER`, `INVALID_NAME`,
/// `READ_FAILED`, `WRITE_FAILED`, `SHARE_FAILED`) rendent un échec, rapporté
/// avec son code.
const kCodeTropGros = 'TOO_LARGE';

/// [EchangeFichiers] de la plateforme. Chaque échec est rapporté par
/// `reportError` avec un `context` limité au code et à la taille : ni nom ni
/// contenu de fichier (P13, ADR-007).
class EchangeFichiersPlateforme implements EchangeFichiers {
  EchangeFichiersPlateforme({required ErrorReportService errorReportService})
    : _errors = errorReportService;

  static const _canal = MethodChannel(kCanalFichiers);

  final ErrorReportService _errors;
  final FichiersWeb _web = FichiersWeb();

  @override
  List<ModeEnvoi> get modes => kIsWeb
      ? const [ModeEnvoi.telecharger]
      : const [ModeEnvoi.enregistrer, ModeEnvoi.partager];

  @override
  Future<ResultatChoix> choisir({
    required int maxOctets,
    List<String>? types,
  }) async {
    if (types != null &&
        (types.isEmpty ||
            types.length > kTypesMax ||
            !types.every(kMotifTypeMime.hasMatch))) {
      // Erreur de programmation : rapportée, sélecteur non ouvert.
      _rapporter(
        'exchange.pick',
        ArgumentError('types de fichier hors motif'),
        StackTrace.current,
        'filtre de types refusé',
      );
      return const ChoixImpossible();
    }
    if (kIsWeb) {
      try {
        return await _web.choisir(maxOctets, types: types);
      } catch (error, stackTrace) {
        _rapporter('exchange.pick', error, stackTrace, 'lecture web');
        return const ChoixImpossible();
      }
    }
    try {
      final result = await _canal.invokeMapMethod<String, Object?>(
        kMethodeChoisir,
        {'maxBytes': maxOctets, 'mimeTypes': ?types},
      );
      if (result == null) return const ChoixAnnule();
      final nom = result['name'];
      final octets = result['bytes'];
      if (nom is! String || octets is! Uint8List) {
        throw const FormatException('réponse du canal inattendue');
      }
      if (octets.length > maxOctets) return FichierTropGros(octets.length);
      return FichierChoisi(nom, octets);
    } on PlatformException catch (error, stackTrace) {
      final taille = error.details is int ? error.details as int : null;
      _rapporter(
        'exchange.pick',
        error,
        stackTrace,
        'code ${error.code}${taille == null ? '' : ', taille $taille octets'}',
      );
      return error.code == kCodeTropGros
          ? FichierTropGros(taille)
          : const ChoixImpossible();
    } catch (error, stackTrace) {
      _rapporter('exchange.pick', error, stackTrace, 'réponse du canal');
      return const ChoixImpossible();
    }
  }

  @override
  Future<ResultatEnvoi> envoyer(
    ModeEnvoi mode, {
    required String nom,
    required String typeMime,
    required Uint8List octets,
  }) async {
    final feature = mode == ModeEnvoi.enregistrer
        ? 'exchange.save'
        : 'exchange.share';
    try {
      switch (mode) {
        case ModeEnvoi.telecharger:
          if (!kIsWeb) throw UnsupportedError('téléchargement hors du web');
          _web.telecharger(nom, typeMime, octets);
          return const EnvoiFait();
        case ModeEnvoi.partager:
        case ModeEnvoi.enregistrer:
          if (kIsWeb) throw UnsupportedError('canal Android sur le web');
          final args = {'name': nom, 'mimeType': typeMime, 'bytes': octets};
          if (mode == ModeEnvoi.partager) {
            await _canal.invokeMethod<void>(kMethodePartager, args);
            return const EnvoiFait();
          }
          final saved = await _canal.invokeMethod<bool>(
            kMethodeEnregistrer,
            args,
          );
          return saved == true ? const EnvoiFait() : const EnvoiAnnule();
      }
    } on PlatformException catch (error, stackTrace) {
      _rapporter(
        feature,
        error,
        stackTrace,
        'code ${error.code}, taille ${octets.length} octets',
      );
      return const EnvoiImpossible();
    } catch (error, stackTrace) {
      _rapporter(feature, error, stackTrace, 'taille ${octets.length} octets');
      return const EnvoiImpossible();
    }
  }

  void _rapporter(
    String feature,
    Object error,
    StackTrace stackTrace,
    String context,
  ) => _errors.reportError(
    feature: feature,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );
}
