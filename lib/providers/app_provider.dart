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
  RealtimeChannel? _ordersChannel;
  Timer? _ordersFallbackTimer;
  final Map<String, int> _orderRequestVersions = {};
  int _sessionVersion = 0;
  int _ordersRevision = 0;
  int _refreshTicket = 0;
  bool _disposed = false;

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
  bool ordersLoading = false;
  bool ordersRefreshing = false;
  bool ordersRealtimeConnected = false;
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
  List<MashOrder> get activeOrders => orders.where((order) => order.status.isActive).toList();
  List<MashOrder> get historyOrders => orders.where((order) => order.status.isTerminal).toList();

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
    _authSubscription = auth.authChanges.listen((state) {
      final authUser = state.session?.user;
      if (!initializing && authUser?.id == user?.id) return;
      unawaited(_loadSessionSafely(authUser));
    });
    _dataSubscriptions.addAll([
      data.categories().listen((value) {
        _dataSucceeded();
        categories = value;
        notifyListeners();
      }),
      data.products().listen((value) {
        _dataSucceeded();
        products = value;
        notifyListeners();
      }),
      data.deals().listen((value) {
        _dataSucceeded();
        deals = value;
        notifyListeners();
      }),
      data.slides().listen((value) {
        _dataSucceeded();
        slides = value;
        notifyListeners();
      }),
      data.settings().listen((value) {
        _dataSucceeded();
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
    final version = ++_sessionVersion;
    await _stopOrdersFeed();
    if (!_sessionIsCurrent(version)) return;

    if (authUser == null) {
      await notification.deactivate();
      if (!_sessionIsCurrent(version)) return;
      user = null;
      orders = const [];
      ordersLoading = false;
      initializing = false;
      _notifyListenersSafely();
      return;
    }

    final loadedUser = await data.getUser(authUser.id).timeout(SupabaseService.requestTimeout);
    if (!_sessionIsCurrent(version)) return;
    if (user?.id != loadedUser?.id) orders = const [];
    user = loadedUser;
    if (loadedUser != null) {
      ordersLoading = orders.isEmpty;
      _notifyListenersSafely();
      await _startOrdersFeed(loadedUser, version);
      if (!_sessionIsCurrent(version)) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastRole', loadedUser.role.name);
      final notificationStatus = await notification.activate(loadedUser);
      if (!_sessionIsCurrent(version)) return;
      if (notificationStatus == NotificationActivationStatus.denied) {
        message = 'Notifications are disabled. Enable them in Android settings to receive order updates.';
      }
    } else {
      orders = const [];
      ordersLoading = false;
    }
    initializing = false;
    _notifyListenersSafely();
  }

  Future<void> _startOrdersFeed(AppUser account, int version) async {
    if (!_sessionIsCurrent(version)) return;
    final scope = _orderScope(account);
    _ordersChannel = data.subscribeToOrderChanges(
      onChanged: (orderId, source) {
        if (!_sessionIsCurrent(version)) return;
        _debugOrders('event $source for $orderId');
        unawaited(_refreshOrder(orderId, account, version));
      },
      onConnectionChanged: (connected) {
        if (!_sessionIsCurrent(version)) return;
        ordersRealtimeConnected = connected;
        _debugOrders(connected ? 'realtime connected' : 'realtime disconnected; fallback refresh enabled');
        _notifyListenersSafely();
      },
    );
    _ordersFallbackTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!ordersRealtimeConnected && _sessionIsCurrent(version)) {
        unawaited(_refreshOrders(account, version));
      }
    });
    _debugOrders('starting feed refresh for ${scope.riderOnly ? 'rider' : scope.customerId == null ? 'staff' : 'customer'}');
    await _refreshOrders(account, version, initial: orders.isEmpty);
  }

  Future<void> _stopOrdersFeed() async {
    _ordersFallbackTimer?.cancel();
    _ordersFallbackTimer = null;
    final channel = _ordersChannel;
    _ordersChannel = null;
    ordersRealtimeConnected = false;
    ordersRefreshing = false;
    _refreshTicket++;
    _ordersRevision++;
    _orderRequestVersions.clear();
    if (channel != null) {
      try {
        await data.removeOrderChannel(channel);
      } catch (exception) {
        _debugOrders('realtime disposal failed: ${exception.runtimeType}');
      }
      _debugOrders('realtime subscription disposed');
    }
  }

  Future<void> _refreshOrders(AppUser account, int version, {bool initial = false}) async {
    if (!_sessionIsCurrent(version) || user?.id != account.id || ordersRefreshing || busyOrders.isNotEmpty) return;
    final ticket = ++_refreshTicket;
    final revisionAtStart = _ordersRevision;
    final scope = _orderScope(account);
    var retryAfter = false;
    ordersRefreshing = true;
    if (initial && orders.isEmpty) ordersLoading = true;
    _debugOrders('refresh start; initial=$initial');
    _notifyListenersSafely();
    try {
      final fresh = await data.fetchOrders(customerId: scope.customerId, riderOnly: scope.riderOnly);
      if (!_sessionIsCurrent(version) || ticket != _refreshTicket || user?.id != account.id) return;
      if (revisionAtStart != _ordersRevision) {
        retryAfter = true;
        _debugOrders('discarded stale full refresh after an incremental update');
        return;
      }
      if (!initial && fresh.isEmpty && orders.isNotEmpty) {
        _debugOrders('ignored empty fallback refresh while visible orders are retained');
        return;
      }
      orders = fresh;
      _ordersRevision++;
      _dataSucceeded();
      _checkPendingAlerts();
      _debugOrderCounts('refresh end');
    } catch (exception) {
      if (_sessionIsCurrent(version)) {
        _handleConnectionFailure(exception);
        _debugOrders('refresh failed: ${exception.runtimeType}');
      }
    } finally {
      if (ticket == _refreshTicket) {
        ordersRefreshing = false;
        ordersLoading = false;
        _notifyListenersSafely();
      }
      if (retryAfter && _sessionIsCurrent(version)) {
        unawaited(Future<void>.delayed(Duration.zero, () => _refreshOrders(account, version, initial: initial)));
      }
    }
  }

  Future<void> _refreshOrder(String orderId, AppUser account, int version) async {
    if (!_sessionIsCurrent(version) || user?.id != account.id) return;
    final requestVersion = (_orderRequestVersions[orderId] ?? 0) + 1;
    _orderRequestVersions[orderId] = requestVersion;
    _ordersRevision++;
    final scope = _orderScope(account);
    try {
      final fresh = await data.fetchOrder(orderId, customerId: scope.customerId, riderOnly: scope.riderOnly);
      if (!_sessionIsCurrent(version) || _orderRequestVersions[orderId] != requestVersion || user?.id != account.id) return;
      if (fresh == null) {
        _removeOrder(orderId);
      } else {
        _upsertOrder(fresh);
      }
      _dataSucceeded();
      _checkPendingAlerts();
      _debugOrderCounts('incremental update');
      _notifyListenersSafely();
    } catch (exception) {
      if (_sessionIsCurrent(version)) {
        _handleConnectionFailure(exception);
        _debugOrders('incremental refresh failed for $orderId: ${exception.runtimeType}');
      }
    }
  }

  void _upsertOrder(MashOrder order) {
    final updated = [...orders.where((item) => item.id != order.id), order]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    orders = updated;
    _ordersRevision++;
  }

  void _removeOrder(String orderId) {
    final updated = orders.where((order) => order.id != orderId).toList();
    if (updated.length == orders.length) return;
    orders = updated;
    _ordersRevision++;
  }

  ({String? customerId, bool riderOnly}) _orderScope(AppUser account) => (
        customerId: account.role == UserRole.customer || account.role == UserRole.rider ? account.id : null,
        riderOnly: account.role == UserRole.rider,
      );

  bool _sessionIsCurrent(int version) => !_disposed && version == _sessionVersion;

  void _debugOrders(String value) {
    if (kDebugMode) debugPrint('[Orders] $value');
  }

  void _debugOrderCounts(String source) {
    if (!kDebugMode) return;
    final active = orders.where((order) => order.status.isActive).length;
    final history = orders.where((order) => order.status.isTerminal).length;
    debugPrint('[Orders] $source; total=${orders.length}, active=$active, history=$history');
  }

  void _notifyListenersSafely() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadSessionSafely(User? authUser) async {
    final expectedVersion = _sessionVersion + 1;
    try {
      await _loadSession(authUser);
    } catch (_) {
      if (_sessionIsCurrent(expectedVersion)) _markConnectionError();
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
      final account = user;
      if (account != null) await _refreshOrder(id!, account, _sessionVersion);
      await _notifyOrderEventSafely('order_placed', id!);
    }, success: 'Order placed successfully.');
    return id;
  }

  Future<bool> updateOrderStatus(String orderId, OrderStatus status) {
    final previous = _findOrder(orderId);
    if (previous != null) {
      _upsertOrder(previous.copyWith(status: status, deliveredAt: status.isCompleted ? DateTime.now() : previous.deliveredAt));
      _debugOrderCounts('optimistic status ${status.dbValue}');
      _notifyListenersSafely();
    }
    return _runOrder(orderId, () async {
      try {
        await data.updateOrderStatus(orderId, status);
        final account = user;
        if (account != null) await _refreshOrder(orderId, account, _sessionVersion);
        await _notifyOrderEventSafely('order_status', orderId);
      } catch (_) {
        if (previous != null) {
          _upsertOrder(previous);
          _notifyListenersSafely();
        }
        rethrow;
      }
    }, 'Order marked ${statusLabelText(status)}.');
  }

  Future<bool> assignRider(String orderId, String riderId) => _runOrder(orderId, () async {
        await data.assignRider(orderId, riderId);
        final account = user;
        if (account != null) await _refreshOrder(orderId, account, _sessionVersion);
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
      if (kDebugMode) debugPrint('Notification event $event failed: ${exception.runtimeType}');
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
    _notifyListenersSafely();
    try {
      hasNetwork = await connectivity.check();
      if (!hasNetwork) throw SocketException('No internet connection');
      await data.healthCheck();
      final account = user;
      final version = _sessionVersion;
      if (account != null) {
        if (ordersRealtimeConnected) {
          await _refreshOrders(account, version);
        } else {
          await _stopOrdersFeed();
          if (_sessionIsCurrent(version)) await _startOrdersFeed(account, version);
        }
      }
      connectionError = false;
      error = null;
    } catch (_) {
      connectionError = true;
    } finally {
      retryingConnection = false;
      initializing = false;
      _notifyListenersSafely();
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
    _notifyListenersSafely();
  }

  void _dataSucceeded() {
    hasNetwork = true;
    connectionError = false;
  }

  MashOrder? _findOrder(String id) {
    for (final order in orders) {
      if (order.id == id) return order;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionVersion++;
    _ordersFallbackTimer?.cancel();
    _authSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _connectionFailureSubscription?.cancel();
    for (final subscription in _dataSubscriptions) {
      subscription.cancel();
    }
    final channel = _ordersChannel;
    if (channel != null) unawaited(data.removeOrderChannel(channel));
    unawaited(notification.dispose());
    data.dispose();
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
