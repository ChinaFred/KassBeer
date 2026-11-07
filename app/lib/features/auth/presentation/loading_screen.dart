import 'package:flutter/material.dart';

import '../../../core/presentation/etats.dart';
import '../../../core/presentation/logo_kass_beer.dart';

/// Affiché tant que la session et `members/{email}` ne sont pas lus.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoKassBeer(),
                SizedBox(height: 32),
                SizedBox(
                  height: 48,
                  child: EtatChargement(label: 'Vérification de l\'accès'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
