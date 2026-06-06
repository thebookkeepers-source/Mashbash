import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({AuthService? auth, FirestoreService? firestore})
      : auth = auth ?? AuthService(),
        firestore = firestore ?? FirestoreService();

  final AuthService auth;
  final FirestoreService firestore;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<Product>>? _productsSubscription;
  StreamSubscription<List<Deal>>? _dealsSubscription;
  StreamSubscription<List<MashOrder>>? _ordersSubscription;

  AppUser? user;
  List<Product> products = const [];
  List<Deal> deals = const [];
  List<MashOrder> orders = const [];
  final Map<String, int> _cart = {};
  bool initializing = true;
  bool busy = false;
  String? error;

  List<CartLine> get cartLines => _cart.entries
      .map((entry) => CartLine(product: products.firstWhere((product) => product.id == entry.key), quantity: entry.value))
      .toList();
  int get cartCount => _cart.values.fold(0, (sum, quantity) => sum + quantity);
  int get subtotal => cartLines.fold(0, (sum, line) => sum + line.total);
  int get deliveryFee => _cart.isEmpty ? 0 : 120;

  Future<void> initialize() async {
    _authSubscription = auth.authChanges.listen(_loadSession);
    _productsSubscription = firestore.products().listen((value) {
      products = value;
      notifyListeners();
    });
    _dealsSubscription = firestore.deals().listen((value) {
      deals = value;
      notifyListeners();
    });
  }

  Future<void> _loadSession(User? firebaseUser) async {
    await _ordersSubscription?.cancel();
    user = firebaseUser == null ? null : await firestore.getUser(firebaseUser.uid);
    if (user != null) {
      try {
        await firestore.seedMenu();
      } catch (_) {
        error = 'The live menu could not be synchronized. Please try again.';
      }
      _ordersSubscription = firestore.orders(customerId: user!.role == UserRole.customer ? user!.id : null).listen((value) {
        orders = value;
        notifyListeners();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastRole', user!.role.name);
    } else {
      orders = const [];
    }
    initializing = false;
    notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on FirebaseAuthException catch (exception) {
      error = exception.message ?? 'Authentication could not be completed.';
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> login(String phone, String password) => run(() async {
        await auth.signInWithPhonePassword(phone, password);
      });

  Future<void> googleLogin() => run(() async {
        final credential = await auth.signInWithGoogle();
        if (credential == null) return;
        user = await firestore.getUser(credential.user!.uid);
        notifyListeners();
      });

  Future<void> register({required String name, required String phone, required String address, required String password}) => run(() async {
        final credential = await auth.registerCustomer(phone, password);
        final customer = AppUser(id: credential.user!.uid, name: name, phone: phone, address: address, role: UserRole.customer);
        await firestore.saveUser(customer);
        user = customer;
      });

  Future<void> saveProfile({required String name, required String phone, required String address}) => run(() async {
        final firebaseUser = auth.currentUser!;
        final updated = AppUser(
          id: firebaseUser.uid,
          name: name,
          phone: phone,
          address: address,
          email: firebaseUser.email ?? '',
          role: user?.role ?? UserRole.customer,
          rights: user?.rights ?? const {},
        );
        await firestore.saveUser(updated);
        user = updated;
      });

  void add(Product product) {
    _cart[product.id] = (_cart[product.id] ?? 0) + 1;
    notifyListeners();
  }

  void decrement(Product product) {
    final quantity = _cart[product.id] ?? 0;
    if (quantity <= 1) {
      _cart.remove(product.id);
    } else {
      _cart[product.id] = quantity - 1;
    }
    notifyListeners();
  }

  void remove(Product product) {
    _cart.remove(product.id);
    notifyListeners();
  }

  Future<String?> checkout({required String address, required String phone, required String paymentMethod}) async {
    String? id;
    await run(() async {
      id = await firestore.placeOrder(
        user: user!,
        lines: cartLines,
        address: address,
        phone: phone,
        paymentMethod: paymentMethod,
        deliveryFee: deliveryFee,
      );
      _cart.clear();
    });
    return id;
  }

  Future<void> logout() => run(auth.signOut);

  @override
  void dispose() {
    _authSubscription?.cancel();
    _productsSubscription?.cancel();
    _dealsSubscription?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }
}
