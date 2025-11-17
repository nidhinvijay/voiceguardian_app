// lib/utils/respectfulness_utils.dart

String respectfulnessGrade(double percent) {
  final clamped = percent.clamp(0, 100);
  if (clamped >= 90) return 'A+';
  if (clamped >= 80) return 'A';
  if (clamped >= 70) return 'B+';
  if (clamped >= 60) return 'B';
  if (clamped >= 50) return 'C+';
  if (clamped >= 40) return 'C';
  if (clamped >= 30) return 'D';
  return 'F';
}
