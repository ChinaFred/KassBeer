import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'echange_fichiers.dart';

/// Choix et téléchargement d'un fichier dans le navigateur (ADR-007) : un
/// `<input type="file">` et un lien `download`. Rien ne part vers un serveur.
class FichiersWeb {
  Completer<ResultatChoix>? _enCours;

  /// Crée et clique un `<input type="file">` : l'appel part du geste de
  /// l'utilisateur, que le navigateur exige. Un nouveau choix clôt le
  /// précédent comme annulé (navigateur sans événement `cancel`).
  Future<ResultatChoix> choisir(int maxOctets) {
    final precedent = _enCours;
    if (precedent != null && !precedent.isCompleted) {
      precedent.complete(const ChoixAnnule());
    }
    final completer = Completer<ResultatChoix>();
    _enCours = completer;
    final input = web.HTMLInputElement()..type = 'file';
    input.addEventListener(
      'change',
      ((web.Event _) => _lire(input, maxOctets, completer)).toJS,
    );
    input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!completer.isCompleted) completer.complete(const ChoixAnnule());
      }).toJS,
    );
    input.click();
    return completer.future;
  }

  /// Lit le fichier choisi : `File.size` au-delà de la borne le refuse avant
  /// `arrayBuffer()`. Une erreur de lecture passe à l'appelant, qui la rapporte.
  void _lire(
    web.HTMLInputElement input,
    int maxOctets,
    Completer<ResultatChoix> completer,
  ) {
    final file = input.files?.item(0);
    if (completer.isCompleted) return;
    if (file == null) {
      completer.complete(const ChoixAnnule());
      return;
    }
    if (file.size > maxOctets) {
      completer.complete(FichierTropGros(file.size));
      return;
    }
    final nom = file.name;
    unawaited(
      file.arrayBuffer().toDart.then(
        (buffer) {
          if (!completer.isCompleted) {
            completer.complete(FichierChoisi(nom, buffer.toDart.asUint8List()));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );
  }

  /// Télécharge [octets] sous [nom] : `Blob`, `URL.createObjectURL`, lien
  /// `download`, clic, puis `revokeObjectURL`.
  void telecharger(String nom, String typeMime, Uint8List octets) {
    final blob = web.Blob(
      <JSAny>[octets.toJS].toJS,
      web.BlobPropertyBag(type: typeMime),
    );
    final url = web.URL.createObjectURL(blob);
    final lien = web.HTMLAnchorElement()
      ..href = url
      ..download = nom;
    web.document.body?.append(lien);
    lien.click();
    lien.remove();
    // Le navigateur lit l'adresse au clic ; elle est libérée une seconde après.
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 1),
        () => web.URL.revokeObjectURL(url),
      ),
    );
  }
}
