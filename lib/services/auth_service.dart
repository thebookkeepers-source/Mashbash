import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';

class AuthService {
  AuthService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  String staffEmail(String phone) => '${phone.replaceAll(RegExp(r'\D'), '')}@staff.mashbash.app';
  String loginEmail(String identifier) => identifier.contains('@') ? identifier.trim() : staffEmail(identifier);

  Future<AuthResponse> signIn(String identifier, String password) => _client.auth.signInWithPassword(email: loginEmail(identifier), password: password);

  Future<AuthResponse> registerCustomer({required String email, required String password, required String name, required String phone, required String address}) =>
      _client.auth.signUp(email: email.trim(), password: password, data: {'name': name, 'phone': phone, 'address': address});

  Future<bool> signInWithGoogle() => _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.mashbash.app://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  Future<String> createStaffAccount({required String name, required String phone, required String password, required UserRole role, required Map<String, bool> rights}) async {
    final response = await _client.functions.invoke('create-staff', body: {
      'action': 'create',
      'name': name,
      'phone': phone,
      'password': password,
      'role': role.name,
      'permissions': rights,
    });
    if (response.status >= 300 || response.data is! Map) {
      final message = response.data is Map ? (response.data as Map)['error'] as String? : null;
      throw Exception(message ?? 'Staff account could not be created.');
    }
    return (response.data as Map)['id'] as String;
  }

  Future<void> updateStaffAccount({required String id, required String name, required String phone, required String password, required UserRole role, required Map<String, bool> rights}) async {
    final response = await _client.functions.invoke('create-staff', body: {
      'action': 'update',
      'user_id': id,
      'name': name,
      'phone': phone,
      'password': password,
      'role': role.name,
      'permissions': rights,
    });
    if (response.status >= 300) {
      final message = response.data is Map ? (response.data as Map)['error'] as String? : null;
      throw Exception(message ?? 'Staff account could not be updated.');
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
