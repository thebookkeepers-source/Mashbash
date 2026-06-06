class Validators {
  static String? requiredText(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? phone(String? value) {
    final phone = value?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (phone.length < 10 || phone.length > 15) return 'Enter a valid mobile number';
    return null;
  }

  static String? password(String? value) {
    if ((value ?? '').length < 8) return 'Password must contain at least 8 characters';
    return null;
  }
}
