import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({AuthService? auth, SupabaseService? data, ConnectivityService? connectivity, NotificationService? notifications})
      : auth = auth ?? AuthService(),
        data = data ?? SupabaseService(),
        connectivity = connectivity ?? ConnectivityService() {
    notification = notifications ?? NotificationService(data: this.data);
  }

  final AuthService auth;
  final SupabaseService data;
  final ConnectivityService connectivity;
  late final NotificationService notification;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<Object>? _connectionFailureSubscription;
  final List<StreamSubscription<dynamic>> _dataSubscriptions = [];
  StreamSubscription<List<MashOrder>>? _ordersSubscription;

  AppUser? user;
  List<MenuCategory> categories = const [];
  List<Product> products = const [];
  List<Deal> deals = const [];
  List<HomeSlide> slides = const [];
  List<MashOrder> orders = const [];
  RestaurantSettings settings = const RestaurantSettings();
  final Map<String, int> _cart = {};
  final Set<String> busyOrders = {};
  final Set<String> _pendingAlertsSent = {};
  bool initializing = true;
  bool connectionError = false;
  bool retryingConnection = false;
  bool hasNetwork = true;
  bool busy = false;
  String? error;
  String? message;

  List<CartLine> get cartLines => _cart.entries
      .map((entry) => CartLine(product: _findCartProduct(entry.key), quantity: entry.value))
      .toList();
  int get cartCount => _cart.values.fold(0, (sum, quantity) => sum + quantity);
  int get subtotal => cartLines.fold(0, (sum, line) => sum + line.total);
  int get deliveryFee => _cart.isEmpty ? 0 : settings.deliveryFee;
  int get configuredDeliveryFee => settings.deliveryFee;
  bool get hasUsableData => products.isNotEmpty || categories.isNotEmpty || user != null;
  List<MenuCategory> get activeCategories => categories.where((item) => item.customerVisible).toList();
  List<HomeSlide> get activeSlides => slides.where((item) => item.active).toList();

  Product _findCartProduct(String id) {
    if (id.startsWith('deal:')) return deals.firstWhere((deal) => 'deal:${deal.id}' == id).asProduct();
    return products.firstWhere((product) => product.id == id);
  }

  Future<void> initialize() async {
    _connectivitySubscription = connectivity.changes.listen((connected) {
      hasNetwork = connected;
      if (!connected) {
        connectionError = true;
        notifyListeners();
      } else if (connectionError) {
        unawaited(retryConnection());
      }
    });
    _connectionFailureSubscription = data.connectionFailures.listen(_handleConnectionFailure);
    _authSubscription = auth.authChanges.listen((state) => unawaited(_loadSessionSafely(state.session?.user)));
    _dataSubscriptions.addAll([
      data.categories().listen((value) {
        categories = value;
        notifyListeners();
      }),
      data.products().listen((value) {
        products = value;
        notifyListeners();
      }),
      data.deals().listen((value) {
        deals = value;
        notifyListeners();
      }),
      data.slides().listen((value) {
        slides = value;
        notifyListeners();
      }),
      data.settings().listen((value) {
        settings = value;
        notifyListeners();
      }),
    ]);
    try {
      hasNetwork = await connectivity.check();
      await notification.initialize();
      await _loadSession(auth.currentUser);
      connectionError = !hasNetwork;
    } catch (_) {
      _markConnectionError();
      initializing = false;
      notifyListeners();
    }
  }

  Future<void> _loadSession(User? authUser) async {
    await _ordersSubscription?.cancel();
    user = authUser == null ? null : await data.getUser(authUser.id).timeout(SupabaseService.requestTimeout);
    if (user != null) {
      _ordersSubscription = data
          .orders(
            customerId: user!.role == UserRole.customer || user!.role == UserRole.rider ? user!.id : null,
            riderOnly: user!.role == UserRole.rider,
          )
          .listen((value) {
        orders = value;
        _checkPendingAlerts();
        notifyListeners();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastRole', user!.role.name);
      final notificationStatus = await notification.activate(user!);
      if (notificationStatus == NotificationActivationStatus.denied) {
        message = 'Notifications are disabled. Enable them in Android settings to receive order updates.';
      }
    } else {
      orders = const [];
    }
    initializing = false;
    notifyListeners();
  }

  Future<void> _loadSessionSafely(User? authUser) async {
    try {
      await _loadSession(authUser);
    } catch (_) {
      _markConnectionError();
    }
  }

  Future<bool> run(Future<void> Function() action, {String? success}) async {
    busy = true;
    error = null;
    message = null;
    notifyListeners();
    try {
      await action();
      message = success;
      return true;
    } catch (exception) {
      if (isConnectionException(exception)) _handleConnectionFailure(exception);
      error = friendlyError(exception);
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> login(String identifier, String password) => run(() => auth.signIn(identifier, password));
  Future<bool> googleLogin() => run(auth.signInWithGoogle);

  Future<bool> register({required String email, required String name, required String phone, required String address, required String password}) => run(() async {
        final response = await auth.registerCustomer(email: email, password: password, name: name, phone: phone, address: address);
        if (response.user != null && response.session != null) {
          final customer = AppUser(id: response.user!.id, name: name, phone: phone, address: address, email: email, role: UserRole.customer);
          await data.saveUser(customer);
          user = customer;
        }
      }, success: 'Account created. Check your email to confirm it if requested, then sign in.');

  Future<bool> saveProfile({required String name, required String phone, required String address}) => run(() async {
        final authUser = auth.currentUser!;
        final updated = AppUser(
          id: authUser.id,
          name: name,
          phone: phone,
          address: address,
          email: authUser.email ?? '',
          role: user?.role ?? UserRole.customer,
          rights: user?.rights ?? const {},
          available: user?.available ?? false,
        );
        await data.saveUser(updated);
        user = updated;
      }, success: 'Profile saved.');

  void add(Product product) {
    _cart[product.id] = (_cart[product.id] ?? 0) + 1;
    notifyListeners();
  }

  void addDeal(Deal deal) => add(deal.asProduct());

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
      id = await data.placeOrder(lines: cartLines, address: address, phone: phone, paymentMethod: paymentMethod, deliveryFee: deliveryFee);
      _cart.clear();
      await _notifyOrderEventSafely('order_placed', id!);
    }, success: 'Order placed successfully.');
    return id;
  }

  Future<bool> updateOrderStatus(String orderId, OrderStatus status) => _runOrder(orderId, () async {
        await data.updateOrderStatus(orderId, status);
        await _notifyOrderEventSafely('order_status', orderId);
      }, 'Order marked ${statusLabelText(status)}.');
  Future<bool> assignRider(String orderId, String riderId) => _runOrder(orderId, () async {
        await data.assignRider(orderId, riderId);
        await _notifyOrderEventSafely('rider_assigned', orderId);
      }, 'Rider assigned.');

  Future<bool> setRiderAvailability(bool available) => run(() async {
        await data.setRiderAvailability(available);
        user = user?.copyWith(available: available);
      }, success: available ? 'You are available for deliveries.' : 'You are not accepting new deliveries.');

  Future<bool> saveSettings(RestaurantSettings value) => run(() => data.saveSettings(value), success: 'Restaurant settings saved.');

  Future<bool> sendCustomNotification({required String title, required String body}) =>
      run(() => data.sendCustomNotification(title: title, body: body), success: 'Notification sent to active customer devices.');

  Future<bool> sendTestNotification() =>
      run(data.sendTestNotification, success: 'Test notification sent. Check this device notification bar.');

  void _checkPendingAlerts() {
    if (user == null || !const [UserRole.owner, UserRole.manager, UserRole.counter].contains(user!.role)) return;
    final cutoff = DateTime.now().subtract(Duration(minutes: settings.pendingAlertMinutes));
    for (final order in orders) {
      final pending = const [OrderStatus.received, OrderStatus.accepted, OrderStatus.preparing].contains(order.status);
      if (pending && order.createdAt.isBefore(cutoff) && _pendingAlertsSent.add(order.id)) {
        unawaited(_notifyOrderEventSafely('pending_order', order.id));
      }
    }
  }

  Future<void> _notifyOrderEventSafely(String event, String orderId) async {
    try {
      await data.notifyOrderEvent(event, orderId);
    } catch (exception) {
      debugPrint('Notification event $event failed: ${exception.runtimeType}');
    }
  }

  Future<bool> _runOrder(String id, Future<void> Function() action, String success) async {
    busyOrders.add(id);
    error = null;
    notifyListeners();
    try {
      await action();
      message = success;
      return true;
    } catch (exception) {
      if (isConnectionException(exception)) _handleConnectionFailure(exception);
      error = friendlyError(exception);
      return false;
    } finally {
      busyOrders.remove(id);
      notifyListeners();
    }
  }

  void clearNotice() {
    error = null;
    message = null;
    notifyListeners();
  }

  Future<bool> logout() => run(() async {
        await notification.deactivate();
        await auth.signOut();
      });

  Future<void> retryConnection() async {
    if (retryingConnection) return;
    retryingConnection = true;
    notifyListeners();
    try {
      hasNetwork = await connectivity.check();
      if (!hasNetwork) throw SocketException('No internet connection');
      await data.healthCheck();
      await _loadSession(auth.currentUser);
      connectionError = false;
      error = null;
    } catch (_) {
      connectionError = true;
    } finally {
      retryingConnection = false;
      initializing = false;
      notifyListeners();
    }
  }

  void _handleConnectionFailure(Object exception) {
    if (!isConnectionException(exception) && !_isServerFailure(exception)) return;
    _markConnectionError();
  }

  void _markConnectionError() {
    connectionError = true;
    error = null;
    initializing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _connectionFailureSubscription?.cancel();
    for (final subscription in _dataSubscriptions) {
      subscription.cancel();
    }
    _ordersSubscription?.cancel();
    unawaited(notification.dispose());
    super.dispose();
  }
}

String statusLabelText(OrderStatus status) => switch (status) {
      OrderStatus.received => 'received',
      OrderStatus.accepted => 'accepted',
      OrderStatus.preparing => 'preparing',
      OrderStatus.readyForDelivery => 'ready for delivery',
      OrderStatus.assignedToRider => 'assigned to rider',
      OrderStatus.outForDelivery => 'out for delivery',
      OrderStatus.delivered => 'delivered',
      OrderStatus.cancelled => 'cancelled',
    };

String friendlyError(Object exception) {
  if (isConnectionException(exception)) return 'There is an error connecting to the server. Please check your internet connection and try again.';
  if (exception is AuthException) {
    if (exception.message.toLowerCase().contains('invalid login')) return 'Incorrect email/mobile number or password.';
    if (exception.message.toLowerCase().contains('email not confirmed')) return 'Confirm your email before signing in.';
    return 'Authentication could not be completed. Please try again.';
  }
  if (exception is FunctionException) return 'The secure server action could not be completed. Please try again.';
  if (exception is NotificationDeliveryException) return exception.message;
  if (exception is StorageException) return 'The image could not be uploaded. Check the file and try again.';
  if (exception is PostgrestException) {
    final message = exception.message.toLowerCase();
    if (message.contains('permission') || message.contains('policy')) return 'You do not have permission to perform this action.';
    if (message.contains('duplicate')) return 'That record already exists.';
    return 'The request could not be saved. Please check the details and try again.';
  }
  return 'Something went wrong. Please try again.';
}

bool isConnectionException(Object exception) {
  if (exception is TimeoutException || exception is SocketException) return true;
  final message = exception.toString().toLowerCase();
  return message.contains('socket') ||
      message.contains('network') ||
      message.contains('connection') ||
      message.contains('failed host lookup') ||
      message.contains('timed out') ||
      message.contains('clientexception');
}

bool _isServerFailure(Object exception) {
  if (exception is! PostgrestException) return false;
  final message = exception.message.toLowerCase();
  return !message.contains('permission') && !message.contains('policy') && !message.contains('duplicate');
}
