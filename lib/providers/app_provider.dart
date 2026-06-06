import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({AuthService? auth, SupabaseService? data})
      : auth = auth ?? AuthService(),
        data = data ?? SupabaseService();

  final AuthService auth;
  final SupabaseService data;
  StreamSubscription<AuthState>? _authSubscription;
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
    _authSubscription = auth.authChanges.listen((state) => _loadSession(state.session?.user));
    _productsSubscription = data.products().listen((value) {
      products = value;
      notifyListeners();
    });
    _dealsSubscription = data.deals().listen((value) {
      deals = value;
      notifyListeners();
    });
  }

  Future<void> _loadSession(User? authUser) async {
    await _ordersSubscription?.cancel();
    user = authUser == null ? null : await data.getUser(authUser.id);
    if (user != null) {
      _ordersSubscription = data.orders(customerId: user!.role == UserRole.customer ? user!.id : null).listen((value) {
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
    } on AuthException catch (exception) {
      error = exception.message;
    } catch (exception) {
      error = exception.toString().replaceFirst('Exception: ', '');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> login(String identifier, String password) => run(() async {
        await auth.signIn(identifier, password);
      });

  Future<void> googleLogin() => run(() async {
        await auth.signInWithGoogle();
      });

  Future<void> register({required String email, required String name, required String phone, required String address, required String password}) => run(() async {
        final response = await auth.registerCustomer(email: email, password: password, name: name, phone: phone, address: address);
        if (response.user != null && response.session != null) {
          final customer = AppUser(id: response.user!.id, name: name, phone: phone, address: address, email: email, role: UserRole.customer);
          await data.saveUser(customer);
          user = customer;
        }
      });

  Future<void> saveProfile({required String name, required String phone, required String address}) => run(() async {
        final authUser = auth.currentUser!;
        final updated = AppUser(
          id: authUser.id,
          name: name,
          phone: phone,
          address: address,
          email: authUser.email ?? '',
          role: user?.role ?? UserRole.customer,
          rights: user?.rights ?? const {},
        );
        await data.saveUser(updated);
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
      id = await data.placeOrder(
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
