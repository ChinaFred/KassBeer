import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_ticket.dart';

/// Libellés de la capture jointe à un ticket (ADR-008, T6).
abstract final class TextesCapture {
  static const titre = 'Capture';
  static const indisponible = 'Capture indisponible.';
  static const chargement = 'Chargement de la capture';
  static const agrandir = 'Agrandir la capture';
  static const fermer = 'Fermer';
}

/// Vignette d'une capture, agrandie à l'appui dans une boîte où l'image se
/// zoome.
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '$libelle. ${TextesCapture.agrandir}',
        excludeSemantics: true,
        child: Tooltip(
          message: TextesCapture.agrandir,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => unawaited(_agrandir(context)),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  png,
                  height: hauteur,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const _Indisponible(),
                ),
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
            child: Image.memory(
              png,
              fit: BoxFit.contain,
              semanticLabel: libelle,
              errorBuilder: (_, _, _) => const _Indisponible(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Capture d'un ticket lue dans Cloud Storage par `getData` : vignette, ou
/// « Capture indisponible. » si la lecture échoue.
class CaptureDuTicket extends ConsumerWidget {
  const CaptureDuTicket({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final capture = ref.watch(ticketScreenshotProvider(path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(TextesCapture.titre, style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        switch (capture) {
          AsyncData(:final value) => VignetteCapture(
            png: value,
            libelle: 'Capture jointe au ticket',
          ),
          AsyncError() => const _Indisponible(),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            TextesCapture.indisponible,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
