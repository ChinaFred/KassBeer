import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

/// Image choisie sur l'appareil (« Choisir une image ») réduite et réencodée
/// en PNG : [preparerImage]. Lève si elle ne se décode pas. Remplacée dans les
/// tests, comme [capturerEcranProvider].
typedef PreparerImage = Future<Uint8List> Function(Uint8List octets);

final preparerImageProvider = Provider<PreparerImage>((ref) => preparerImage);

/// Taille du côté long visée pour une image de [largeur] × [hauteur] pixels :
/// `null` si elle tient déjà dans [kCaptureMaxSide] (taille d'origine
/// gardée), sinon [kCaptureMaxSide] posé sur le côté long, l'autre suivant
/// les proportions. Pure.
ui.TargetImageSize tailleImageChoisie(int largeur, int hauteur) {
  final max = kCaptureMaxSide.toInt();
  if (math.max(largeur, hauteur) <= max) return const ui.TargetImageSize();
  return largeur >= hauteur
      ? ui.TargetImageSize(width: max)
      : ui.TargetImageSize(height: max);
}

/// Plus grand nombre de pixels (largeur × hauteur) d'une image choisie avant
/// son décodage : au-delà, l'image est refusée sans être décodée (une image
/// de 30 000 × 30 000 demanderait 3,6 Go en mémoire).
const kImageChoisieMaxPixels = 50000000;

/// Image choisie refusée avant son décodage : format non reconnu, en-tête
/// tronqué, ou plus de [kImageChoisieMaxPixels] pixels. Ne porte ni nom ni
/// contenu de fichier.
class ImageRefusee implements Exception {
  const ImageRefusee(this.raison);

  /// `format` ou `pixels`.
  final String raison;

  @override
  String toString() => 'ImageRefusee($raison)';
}

/// Largeur et hauteur annoncées par l'en-tête d'une image PNG, JPEG ou WebP,
/// lues sans décoder l'image ; `null` pour un autre format ou un en-tête
/// tronqué. Pure.
///
/// `ui.ImageDescriptor.encoded` lit aussi l'en-tête sans décoder sur
/// Android, mais son `width` lève `UnsupportedError` sur le web : la lecture
/// se fait ici, de la même façon sur les deux cibles.
({int largeur, int hauteur})? dimensionsImage(Uint8List o) {
  int be16(int i) => (o[i] << 8) | o[i + 1];
  int be32(int i) =>
      (o[i] << 24) | (o[i + 1] << 16) | (o[i + 2] << 8) | o[i + 3];
  int le16(int i) => o[i] | (o[i + 1] << 8);
  int le24(int i) => o[i] | (o[i + 1] << 8) | (o[i + 2] << 16);
  bool ascii(int i, String texte) {
    if (o.length < i + texte.length) return false;
    for (var k = 0; k < texte.length; k++) {
      if (o[i + k] != texte.codeUnitAt(k)) return false;
    }
    return true;
  }

  // PNG : signature, puis bloc IHDR (largeur et hauteur aux octets 16 à 23).
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (o.length >= 24 &&
      List<int>.generate(8, (i) => i).every((i) => o[i] == png[i]) &&
      ascii(12, 'IHDR')) {
    return (largeur: be32(16), hauteur: be32(20));
  }

  // JPEG : segments jusqu'au premier SOFn (hauteur puis largeur).
  if (o.length >= 4 && o[0] == 0xff && o[1] == 0xd8) {
    var i = 2;
    while (i + 3 < o.length) {
      if (o[i] != 0xff) return null;
      final marqueur = o[i + 1];
      if (marqueur == 0xff) {
        i++; // octet de remplissage
        continue;
      }
      if (marqueur == 0x01 || (marqueur >= 0xd0 && marqueur <= 0xd8)) {
        i += 2; // marqueur sans longueur
        continue;
      }
      if (marqueur == 0xd9 || marqueur == 0xda) return null; // fin, données
      final longueur = be16(i + 2);
      if (longueur < 2) return null;
      final sof =
          marqueur >= 0xc0 &&
          marqueur <= 0xcf &&
          marqueur != 0xc4 &&
          marqueur != 0xc8 &&
          marqueur != 0xcc;
      if (sof) {
        if (i + 9 > o.length) return null;
        return (largeur: be16(i + 7), hauteur: be16(i + 5));
      }
      i += 2 + longueur;
    }
    return null;
  }

  // WebP : conteneur RIFF, puis bloc VP8, VP8L ou VP8X.
  if (ascii(0, 'RIFF') && ascii(8, 'WEBP') && o.length >= 30) {
    if (ascii(12, 'VP8 ')) {
      return (largeur: le16(26) & 0x3fff, hauteur: le16(28) & 0x3fff);
    }
    if (ascii(12, 'VP8L') && o[20] == 0x2f) {
      final bits = o[21] | (o[22] << 8) | (o[23] << 16) | (o[24] << 24);
      return (
        largeur: (bits & 0x3fff) + 1,
        hauteur: ((bits >> 14) & 0x3fff) + 1,
      );
    }
    if (ascii(12, 'VP8X')) {
      return (largeur: le24(24) + 1, hauteur: le24(27) + 1);
    }
  }
  return null;
}

/// Vrai si [largeur] × [hauteur] dépasse [kImageChoisieMaxPixels], comparé
/// sans multiplier : le produit de deux côtés de 32 bits déborde en Dart natif
/// (0xFFFFFFFF × 0xFFFFFFFF rend un nombre négatif). [hauteur] est positive.
/// Pure.
bool depasseMaxPixels(int largeur, int hauteur) =>
    largeur > kImageChoisieMaxPixels ||
    hauteur > kImageChoisieMaxPixels ||
    largeur > kImageChoisieMaxPixels ~/ hauteur;

/// Vérifie l'en-tête de [octets] avant tout décodage : lève [ImageRefusee]
/// pour un format autre que PNG, JPEG ou WebP, un en-tête illisible, un côté
/// nul ou plus de [kImageChoisieMaxPixels] pixels. Pure.
void verifierImageAvantDecodage(Uint8List octets) {
  final dims = dimensionsImage(octets);
  if (dims == null) throw const ImageRefusee('format');
  if (dims.largeur <= 0 || dims.hauteur <= 0) {
    throw const ImageRefusee('format');
  }
  if (depasseMaxPixels(dims.largeur, dims.hauteur)) {
    throw const ImageRefusee('pixels');
  }
}

/// Vérifie l'en-tête de [octets] ([verifierImageAvantDecodage] : aucun
/// décodage au-delà de [kImageChoisieMaxPixels] pixels), puis décode l'image
/// par `dart:ui` (PNG, JPEG, WebP), côté long réduit à [kCaptureMaxSide]
/// pixels au plus, et réencode la première image en PNG : les métadonnées du
/// fichier d'origine (EXIF, position) ne passent pas. Lève si l'image est
/// refusée ou ne se décode pas ; l'appelant rapporte l'erreur.
Future<Uint8List> preparerImage(Uint8List octets) async {
  verifierImageAvantDecodage(octets);
  final buffer = await ui.ImmutableBuffer.fromUint8List(octets);
  if (kIsWeb) {
    // Sur le web, `ImageDescriptor.width` lève `UnsupportedError` :
    // `instantiateImageCodecWithSize` décode et libère le tampon.
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: tailleImageChoisie,
    );
    return _premiereImageEnPng(codec);
  }
  // Ailleurs, le descripteur lit l'en-tête ; le décodeur lit ses données
  // jusqu'à la première image : descripteur et tampon se libèrent après.
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    // Second contrôle, sur l'en-tête lu par le moteur : il refuse une image
    // dont la taille diffère de celle lue par [dimensionsImage].
    final largeur = descriptor.width;
    final hauteur = descriptor.height;
    if (largeur <= 0 || hauteur <= 0) throw const ImageRefusee('format');
    if (depasseMaxPixels(largeur, hauteur)) {
      throw const ImageRefusee('pixels');
    }
    final taille = tailleImageChoisie(largeur, hauteur);
    final codec = await descriptor.instantiateCodec(
      targetWidth: taille.width,
      targetHeight: taille.height,
    );
    return await _premiereImageEnPng(codec);
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Première image de [codec], réencodée en PNG ; [codec] est libéré.
Future<Uint8List> _premiereImageEnPng(ui.Codec codec) async {
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('réencodage PNG impossible');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
