import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Déconnexion depuis un écran. Un échec est rapporté et annoncé.
Future<void> signOutFrom(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (error, stackTrace) {
    ref
        .read(errorReportServiceProvider)
        .reportError(
          feature: 'auth.sign_out',
          error: error,
          stackTrace: stackTrace,
        );
    messenger?.showSnackBar(
      const SnackBar(content: Text('Déconnexion impossible. Réessayez.')),
    );
  }
}
