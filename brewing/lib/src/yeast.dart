import 'errors.dart';
import 'gravity.dart';

/// Densité finale prévue (SG) d'après l'atténuation de la levure.
///
/// FG = 1 + (OG − 1) × (1 − atténuation / 100). [attenuationPercent] est
/// l'atténuation apparente annoncée par le fabricant de la levure, de 0 à 100 %.
/// Lève [BrewingInputException] si [originalGravity] est sous 1.000 : la FG
/// prévue dépasserait alors l'OG.
double predictedFinalGravity({
  required double originalGravity,
  required double attenuationPercent,
}) {
  requireRange('originalGravity', originalGravity, 1, maxGravity);
  requireRange('attenuationPercent', attenuationPercent, 0, 100);
  return 1 + (originalGravity - 1) * (1 - attenuationPercent / 100);
}
