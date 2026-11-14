import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/zone_capture.dart';
import '../../../core/providers.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/ticket.dart';

/// Capture de l'écran quitté, prise par « Signaler ou proposer » au moment de
/// l'appui, avant la navigation (ADR-008, T6). En mémoire seulement : jamais
/// écrite sur l'appareil.
@immutable
class CaptureEcran {
  const CaptureEcran({required this.png, required this.ecran});

  /// Image PNG, 5 Mo au plus.
  final Uint8List png;

  /// Valeur de `ticket_screens.dart` de l'écran capturé (`/recettes/:id`).
  final String ecran;
}

/// Capture qui attend le formulaire. Le formulaire la prend une fois
/// ([CaptureEnAttente.prendre]), dans `initState`, et la vide. Aucun écran ne
/// l'écoute : c'est un dépôt en mémoire, pas un état affiché.
class CaptureEnAttente {
  CaptureEcran? _capture;

  void poser(CaptureEcran? capture) => _capture = capture;

  /// La capture en attente, retirée du dépôt.
  CaptureEcran? prendre() {
    final capture = _capture;
    _capture = null;
    return capture;
  }
}

final captureEnAttenteProvider = Provider<CaptureEnAttente>(
  (ref) => CaptureEnAttente(),
);

/// Prend l'image PNG du contenu de la page qui porte le contexte, ou `null`.
/// Remplacée dans les tests : `toImage` ne se termine pas sous l'horloge
/// simulée de `flutter_test`.
typedef CapturerEcran = Future<Uint8List?> Function(BuildContext context);

final capturerEcranProvider = Provider<CapturerEcran>((ref) {
  final errors = ref.watch(errorReportServiceProvider);
  return (context) => capturerEcran(context, errors);
});

/// Délai du rendu d'une capture : au-delà, le formulaire s'ouvre sans elle.
const kCaptureTimeout = Duration(seconds: 5);

/// Image PNG de la [ZoneCapture] de la page de [context] : échelle 2 au plus,
/// 2 000 px au plus de côté, 5 Mo au plus ; sinon `null`. Un rendu en échec
/// est rapporté, sans contenu ni nom de fichier, et rend `null` : le ticket
/// part sans capture.
Future<Uint8List?> capturerEcran(
  BuildContext context,
  ErrorReportService errors,
) async {
  final zone = zoneCaptureDe(context);
  if (zone == null) return null;
  final dpr = MediaQuery.devicePixelRatioOf(context);
  try {
    return await rendrePng(
      zone,
      devicePixelRatio: dpr,
      maxBytes: kTicketScreenshotMaxBytes,
    ).timeout(kCaptureTimeout);
  } catch (error, stackTrace) {
    errors.reportError(
      feature: 'tickets.capture',
      error: error,
      stackTrace: stackTrace,
      context: 'rendu de la capture impossible',
    );
    return null;
  }
}

/// Octets de la capture rangée sous un chemin Storage, pour l'auteur et
/// l'administrateur.
final ticketScreenshotProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, path) => ref.watch(ticketsRepositoryProvider).loadScreenshot(path),
      // Une panne s'affiche : « Capture indisponible. ».
      retry: (retryCount, error) => null,
    );
