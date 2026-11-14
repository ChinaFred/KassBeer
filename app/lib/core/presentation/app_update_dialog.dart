import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_installer.dart';
import '../services/app_update_service.dart';
import 'formats.dart';

/// Ouvre la fenêtre « Nouvelle version » (ADR-012). Elle se ferme par
/// « Plus tard » ou à l'ouverture de l'installateur du système.
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required MiseAJourDisponible miseAJour,
  required AppUpdateService service,
}) =>
    // ticket: aucun (fenêtre de mise à jour de l'APK, ADR-012)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDialog(miseAJour: miseAJour, service: service),
    );

enum _Etape { offre, autorisation, telechargement, installation, echec }

/// Étapes : offre, autorisation, téléchargement (progression, « Annuler »),
/// installation, échec (« Réessayer », « Plus tard »). Aucun repli vers le
/// navigateur.
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.miseAJour,
    required this.service,
  });

  final MiseAJourDisponible miseAJour;
  final AppUpdateService service;

  static const titre = 'Nouvelle version';
  static const plusTard = 'Plus tard';
  static const mettreAJour = 'Mettre à jour';
  static const autorisationTexte =
      'Autorisez Kass\'Beer à installer des applications';
  static const autorisationAide =
      'Dans les réglages, activez « Autoriser cette source », puis revenez '
      'ici.';
  static const ouvrirReglages = 'Ouvrir les réglages';
  static const annuler = 'Annuler';
  static const reessayer = 'Réessayer';
  static const ouvertureInstallateur = 'Ouverture de l\'installateur…';
  static const echecReseau =
      'Le téléchargement s\'est interrompu. Vérifiez la connexion.';
  static const echecAnnule = 'Téléchargement annulé.';
  static const echecFichier =
      'Le fichier reçu ne correspond pas à la version annoncée. Il a été '
      'effacé.';
  static const echecAppareil =
      'Le fichier n\'a pas pu être enregistré sur l\'appareil.';
  static const echecInstallateur =
      'L\'installateur du système n\'a pas pu s\'ouvrir.';
  static const echecReglages = 'Les réglages n\'ont pas pu s\'ouvrir.';

  /// « Kass'Beer X.Y.Z est disponible (vous avez X.Y.Z). »
  static String offre(String nouvelle, String? installee) =>
      'Kass\'Beer $nouvelle est disponible'
      '${installee == null ? '' : ' (vous avez $installee)'}.';

  /// « Téléchargement de 48,2 Mo. »
  static String taille(int octets) =>
      'Téléchargement de ${formatOctets(octets)}.';

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

/// Taille en Mo (une décimale) ou en Ko.
String formatOctets(int octets) {
  const mo = 1024 * 1024;
  if (octets >= mo) {
    return '${formatNombre(octets / mo, decimales: 1, fixe: true)}${nbsp}Mo';
  }
  return '${formatNombre(octets / 1024, decimales: 0)}${nbsp}Ko';
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _Etape _etape = _Etape.offre;
  ApkDownload? _suivi;
  int _recus = 0;
  String _echec = '';
  AppLifecycleListener? _retour;

  ManifesteApk get _manifeste => widget.miseAJour.manifeste;

  bool get _occupe =>
      _etape == _Etape.telechargement || _etape == _Etape.installation;

  @override
  void dispose() {
    _suivi?.annuler();
    _retour?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texte = Theme.of(context).textTheme;
    return PopScope(
      // Retour du système : refusé pendant le téléchargement et
      // l'installation, « Plus tard » sinon.
      canPop: !_occupe,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_outlined),
        title: const Text(AppUpdateDialog.titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: switch (_etape) {
            _Etape.offre => [
              Text(
                AppUpdateDialog.offre(
                  _manifeste.version,
                  widget.miseAJour.versionInstallee,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppUpdateDialog.taille(_manifeste.tailleOctets),
                style: texte.bodySmall,
              ),
            ],
            _Etape.autorisation => [
              const Text(AppUpdateDialog.autorisationTexte),
              const SizedBox(height: 8),
              Text(AppUpdateDialog.autorisationAide, style: texte.bodySmall),
            ],
            _Etape.telechargement => [
              LinearProgressIndicator(
                value: _recus / _manifeste.tailleOctets,
                semanticsLabel: 'Téléchargement',
              ),
              const SizedBox(height: 12),
              Text(
                '${formatOctets(_recus)} sur '
                '${formatOctets(_manifeste.tailleOctets)}',
                style: texte.bodySmall,
              ),
            ],
            _Etape.installation => const [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text(AppUpdateDialog.ouvertureInstallateur)),
                ],
              ),
            ],
            _Etape.echec => [Text(_echec)],
          },
        ),
        actions: switch (_etape) {
          _Etape.offre => [
            TextButton(
              onPressed: _fermer,
              child: const Text(AppUpdateDialog.plusTard),
            ),
            FilledButton(
              onPressed: _commencer,
              child: const Text(AppUpdateDialog.mettreAJour),
            ),
          ],
          _Etape.autorisation => [
            TextButton(
              onPressed: _fermer,
              child: const Text(AppUpdateDialog.plusTard),
            ),
            FilledButton(
              onPressed: _ouvrirReglages,
              child: const Text(AppUpdateDialog.ouvrirReglages),
            ),
          ],
          _Etape.telechargement => [
            TextButton(
              onPressed: () => _suivi?.annuler(),
              child: const Text(AppUpdateDialog.annuler),
            ),
          ],
          _Etape.installation => const [],
          _Etape.echec => [
            TextButton(
              onPressed: _fermer,
              child: const Text(AppUpdateDialog.plusTard),
            ),
            FilledButton(
              onPressed: _commencer,
              child: const Text(AppUpdateDialog.reessayer),
            ),
          ],
        },
      ),
    );
  }

  void _fermer() => Navigator.of(context).pop();

  void _echouer(String message) {
    if (!mounted) return;
    setState(() {
      _etape = _Etape.echec;
      _echec = message;
      _suivi = null;
    });
  }

  /// L'autorisation se lit avant le téléchargement : un APK reçu puis refusé
  /// à l'installation serait transféré pour rien.
  Future<void> _commencer() async {
    final permis = await widget.service.peutInstaller();
    if (!mounted) return;
    if (!permis) {
      setState(() => _etape = _Etape.autorisation);
      return;
    }
    final suivi = ApkDownload();
    setState(() {
      _etape = _Etape.telechargement;
      _suivi = suivi;
      _recus = 0;
    });
    final issue = await widget.service.telecharger(
      _manifeste,
      suivi: suivi,
      progression: (recus, _) {
        if (mounted) setState(() => _recus = recus);
      },
    );
    if (!mounted) return;
    switch (issue) {
      case Telechargement.interrompu:
        return _echouer(AppUpdateDialog.echecReseau);
      case Telechargement.annule:
        return _echouer(AppUpdateDialog.echecAnnule);
      case Telechargement.refuse:
        return _echouer(AppUpdateDialog.echecFichier);
      case Telechargement.impossible:
        return _echouer(AppUpdateDialog.echecAppareil);
      case Telechargement.pret:
        break;
    }
    setState(() {
      _etape = _Etape.installation;
      _suivi = null;
    });
    final installation = await widget.service.installer(_manifeste);
    if (!mounted) return;
    switch (installation) {
      case Installation.ouverte:
        // L'écran d'installation d'Android est passé devant.
        _fermer();
      case Installation.refusee:
        _echouer(AppUpdateDialog.echecFichier);
      case Installation.impossible:
        _echouer(AppUpdateDialog.echecInstallateur);
    }
  }

  /// Ouvre le réglage, puis relit l'autorisation au retour dans Kass'Beer.
  Future<void> _ouvrirReglages() async {
    _retour ??= AppLifecycleListener(onResume: _auRetour);
    final ouvert = await widget.service.ouvrirReglages();
    if (!ouvert) _echouer(AppUpdateDialog.echecReglages);
  }

  void _auRetour() {
    if (!mounted || _etape != _Etape.autorisation) return;
    unawaited(_relireAutorisation());
  }

  Future<void> _relireAutorisation() async {
    final permis = await widget.service.peutInstaller();
    if (!mounted || !permis || _etape != _Etape.autorisation) return;
    await _commencer();
  }
}
