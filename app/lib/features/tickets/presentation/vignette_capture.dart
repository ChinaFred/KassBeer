import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import 'capture_ticket.dart';

/// Libellés de la capture jointe à un ticket (ADR-008, T6).
abstract final class TextesCapture {
  static const titre = 'Capture';
  static const indisponible = 'Capture indisponible.';
  static const effacee = 'Capture effacée.';
  static const horsLigne = 'La capture se lit avec le réseau.';
  static const reessayer = 'Réessayer';
  static const chargement = 'Chargement de la capture';
  static const agrandir = 'Agrandir la capture';
  static const fermer = 'Fermer';
}

/// Vignette d'une capture, agrandie à l'appui dans une boîte où l'image se
/// zoome. L'effet d'appui et le focus se peignent au-dessus de l'image.
class VignetteCapture extends StatelessWidget {
  const VignetteCapture({
    super.key,
    required this.png,
    required this.libelle,
    this.hauteur = 160,
  });

  final Uint8List png;

  /// Nom lu par le lecteur d'écran.
  final String libelle;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void agrandir() => unawaited(_agrandir(context));
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '$libelle. ${TextesCapture.agrandir}',
        onTap: agrandir,
        excludeSemantics: true,
        child: Tooltip(
          message: TextesCapture.agrandir,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  _ImageCapture(png: png, hauteur: hauteur),
                  // Au-dessus de l'image : l'encre et le focus restent visibles.
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: agrandir),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ticket: aucun (capture agrandie, sans action)
  Future<void> _agrandir(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text(TextesCapture.titre),
          leading: IconButton(
            tooltip: TextesCapture.fermer,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Semantics(
              label: libelle,
              image: true,
              child: _ImageCapture(png: png),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Image d'une capture ; un décodage en échec affiche « Capture
/// indisponible. » et se rapporte une fois, sans contenu ni chemin.
class _ImageCapture extends ConsumerStatefulWidget {
  const _ImageCapture({required this.png, this.hauteur});

  final Uint8List png;
  final double? hauteur;

  @override
  ConsumerState<_ImageCapture> createState() => _ImageCaptureState();
}

class _ImageCaptureState extends ConsumerState<_ImageCapture> {
  bool _rapporte = false;

  @override
  Widget build(BuildContext context) {
    final errors = ref.read(errorReportServiceProvider);
    return Image.memory(
      widget.png,
      height: widget.hauteur,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, error, stackTrace) {
        if (!_rapporte) {
          _rapporte = true;
          errors.reportError(
            feature: 'tickets.capture_display',
            error: error,
            stackTrace: stackTrace,
            context: 'capture illisible, ${widget.png.length} octets',
          );
        }
        return const _Indisponible();
      },
    );
  }
}

/// Capture d'un ticket lue dans Cloud Storage par `getData` : vignette, ou
/// « Capture indisponible. » et « Réessayer » si la lecture échoue ; hors
/// ligne, « La capture se lit avec le réseau. ». Une capture effacée par la
/// règle de cycle de vie du bucket ([expiresAt] passée, ou fichier absent)
/// affiche « Capture effacée », sans lecture ni rapport.
class CaptureDuTicket extends ConsumerWidget {
  const CaptureDuTicket({super.key, required this.path, this.expiresAt});

  final String path;

  /// `screenshot_expires_at` du ticket, écrit par le serveur.
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final titre = Semantics(
      header: true,
      child: Text(TextesCapture.titre, style: theme.textTheme.titleSmall),
    );
    final echeance = expiresAt;
    if (echeance != null && !ref.watch(horlogeProvider)().isBefore(echeance)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [titre, const SizedBox(height: 8), const _Effacee()],
      );
    }
    final capture = ref.watch(ticketScreenshotProvider(path));
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titre,
        const SizedBox(height: 8),
        switch (capture) {
          AsyncError(error: CaptureEffacee()) => const _Effacee(),
          AsyncData(:final value) => VignetteCapture(
            png: value,
            libelle: 'Capture jointe au ticket',
          ),
          AsyncError() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Indisponible(),
              if (offline) ...[
                const SizedBox(height: 4),
                Text(
                  TextesCapture.horsLigne,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: capture.isLoading
                    ? null
                    : () => ref.invalidate(ticketScreenshotProvider(path)),
                child: const Text(TextesCapture.reessayer),
              ),
            ],
          ),
          _ => const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: TextesCapture.chargement,
              ),
            ),
          ),
        },
      ],
    );
  }
}

class _Indisponible extends StatelessWidget {
  const _Indisponible();

  @override
  Widget build(BuildContext context) => const _LigneCapture(
    Icons.broken_image_outlined,
    TextesCapture.indisponible,
  );
}

class _Effacee extends StatelessWidget {
  const _Effacee();

  @override
  Widget build(BuildContext context) =>
      const _LigneCapture(Icons.auto_delete_outlined, TextesCapture.effacee);
}

/// Icône et texte gris d'un état de la capture.
class _LigneCapture extends StatelessWidget {
  const _LigneCapture(this.icone, this.texte);

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(icone, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            texte,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
