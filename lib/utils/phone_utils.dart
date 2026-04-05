String normalizePhoneNumber(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length > 10) {
    return '+91${digits.substring(digits.length - 10)}';
  }
  if (digits.length == 10) {
    return '+91$digits';
  }
  return '';
}
