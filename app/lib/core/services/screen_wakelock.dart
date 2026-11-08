import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../providers.dart';
import 'error_report_service.dart';

/// Applique ou relâche le maintien de l'écran auprès de la plateforme.
typedef WakelockToggle = Future<void> Function({required bool enable});

/// Maintient l'écran allumé tant qu'au moins un écran le demande : le compteur
/// évite qu'un écran refermé éteigne celui qui reste.
///
/// Sur le web, `no_sleep.js` se charge au premier appel : le verrou est pris à
/// l'ouverture de « Préparer » et de l'écran du jour, avant de couper le réseau
/// (CLAUDE.md, P2).
class ScreenWakelock {
  ScreenWakelock({
    required ErrorReportService errorReportService,
    WakelockToggle? toggle,
  }) : _errors = errorReportService,
       _toggle = toggle ?? _platformToggle;

  static Future<void> _platformToggle({required bool enable}) =>
      WakelockPlus.toggle(enable: enable);

  final ErrorReportService _errors;
  final WakelockToggle _toggle;
  int _holders = 0;
  bool _failureReported = false;

  /// Vrai si la plateforme a refusé le verrou : l'écran l'affiche.
  final ValueNotifier<bool> failed = ValueNotifier(false);

  @visibleForTesting
  int get holders => _holders;

  Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _apply(enable: true);
  }

  Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _apply(enable: false);
  }

  /// Reprend le verrou au retour d'arrière-plan : Android et les navigateurs le
  /// relâchent sans le rendre.
  Future<void> refresh() async {
    if (_holders > 0) await _apply(enable: true);
  }

  Future<void> _apply({required bool enable}) async {
    try {
      await _toggle(enable: enable);
      if (enable) failed.value = false;
    } catch (error, stackTrace) {
      if (enable) failed.value = true;
      // Une seule remontée par session : l'échec se reproduirait à chaque
      // ouverture de l'écran.
      if (_failureReported) return;
      _failureReported = true;
      _errors.reportError(
        feature: 'brew_day.wakelock',
        error: error,
        stackTrace: stackTrace,
        context: 'enable=$enable holders=$_holders',
      );
    }
  }
}

/// Garde l'écran allumé tant que l'écran qui mixe ceci est monté.
mixin KeepScreenAwake<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final ScreenWakelock wakelock;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    wakelock = ref.read(screenWakelockProvider);
    unawaited(wakelock.acquire());
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(wakelock.refresh()),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(wakelock.release());
    super.dispose();
  }
}
