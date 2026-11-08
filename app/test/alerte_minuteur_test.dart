import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/features/brew_day/data/alerte_minuteur.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(kCanalAlerte);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('nom du canal et des méthodes : ceux de MainActivity.kt', () {
    expect(kCanalAlerte, 'fr.kassbeer/alert');
    expect(kMethodeBip, 'beep');
    expect(kMethodeVibration, 'vibrate');
  });

  test('déclencher : bip puis vibration, sans erreur', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final errors = RecordingErrorReportService();
    final alerte = AlerteMinuteurPlateforme(errorReportService: errors);
    await alerte.declencher();
    expect(calls, ['beep', 'vibrate']);
    expect(errors.reports, isEmpty);
  });

  test('échec du canal : chaque méthode rapportée une seule fois', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ALERT_FAILED', message: 'non disponible');
    });
    final errors = RecordingErrorReportService();
    final alerte = AlerteMinuteurPlateforme(errorReportService: errors);
    await alerte.declencher();
    await alerte.declencher();
    expect(errors.reports.map((r) => r.feature).toSet(), {
      'brew_day.alert_beep',
      'brew_day.alert_vibrate',
    });
    expect(errors.reports.length, 2);
  });

  test('R3 : le bip échoue, la vibration part quand même', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'beep') {
        throw PlatformException(code: 'ALERT_FAILED');
      }
      return null;
    });
    final errors = RecordingErrorReportService();
    await AlerteMinuteurPlateforme(errorReportService: errors).declencher();
    expect(calls, ['beep', 'vibrate']);
    expect(errors.reports.single.feature, 'brew_day.alert_beep');
  });
}
