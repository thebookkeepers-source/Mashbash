import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  String phoneEmail(String phone) => '${phone.replaceAll(RegExp(r'\D'), '')}@phone.mashbash.app';

  Future<UserCredential> signInWithPhonePassword(String phone, String password) =>
      _auth.signInWithEmailAndPassword(email: phoneEmail(phone), password: password);

  Future<UserCredential> registerCustomer(String phone, String password) =>
      _auth.createUserWithEmailAndPassword(email: phoneEmail(phone), password: password);

  Future<UserCredential?> signInWithGoogle() async {
    final account = await GoogleSignIn().signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return _auth.signInWithCredential(GoogleAuthProvider.credential(accessToken: auth.accessToken, idToken: auth.idToken));
  }

  Future<User> createStaffAccount(String phone, String password) async {
    final secondary = await Firebase.initializeApp(
      name: 'staff-${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      final result = await FirebaseAuth.instanceFor(app: secondary)
          .createUserWithEmailAndPassword(email: phoneEmail(phone), password: password);
      return result.user!;
    } finally {
      await secondary.delete();
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}
