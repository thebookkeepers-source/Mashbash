import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';

class NotificationDeliveryException implements Exception {
  const NotificationDeliveryException(this.message);
  final String message;
}

class SupabaseService {
  SupabaseService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  final StreamController<Object> _connectionFailures = StreamController<Object>.broadcast();
  static const requestTimeout = Duration(seconds: 15);
  static const _orderSelect =
      'id, customer_id, customer_name, phone, address, payment_method, subtotal, delivery_fee, status, assigned_rider_id, accepted_by, assigned_at, delivered_at, created_at, order_items(id, product_id, deal_id, item_type, name, price, quantity, image_url, category_name, line_total), assigned_rider:profiles!orders_assigned_rider_id_fkey(name)';

  Stream<Object> get connectionFailures => _connectionFailures.stream;

  Future<AppUser?> getUser(String uid) async {
    final row = await _client
        .from('profiles')
        .select('id, name, phone, address, email, role, active, rider_available, staff_permissions(view_orders, update_order_status, assign_riders, manage_menu, manage_deals, manage_slides, view_reports)')
        .eq('id', uid)
        .maybeSingle()
        .timeout(requestTimeout);
    return row == null ? null : AppUser.fromMap(row);
  }

  Future<void> saveUser(AppUser user) => _client.from('profiles').update(user.toMap()).eq('id', user.id);

  Stream<List<AppUser>> staff() => _poll(() async {
        final rows = await _client
            .from('profiles')
            .select('id, name, phone, address, email, role, active, rider_available, staff_permissions(view_orders, update_order_status, assign_riders, manage_menu, manage_deals, manage_slides, view_reports)')
            .inFilter('role', ['manager', 'counter', 'rider'])
            .order('name');
        return rows.map(AppUser.fromMap).toList();
      }, interval: const Duration(seconds: 10));

  Stream<List<AppUser>> availableRiders() => _poll(() async {
        final rows = await _client.from('profiles').select('id, name, phone, address, email, role, active, rider_available').eq('role', 'rider').eq('active', true).eq('rider_available', true).order('name');
        return rows.map(AppUser.fromMap).toList();
      }, interval: const Duration(seconds: 5));

  Stream<List<MenuCategory>> categories() => _poll(() async {
        final rows = await _client.from('categories').select('id, name, image_url, sort_order, active, archived_at').order('sort_order').order('name');
        return rows.map(MenuCategory.fromMap).toList();
      }, interval: const Duration(seconds: 10));

  Stream<List<Product>> products() => _poll(() async {
        final rows = await _client
            .from('products')
            .select('id, category_id, name, description, price, image_url, available, sort_order, archived_at, categories(name, active, archived_at)')
            .order('sort_order')
            .order('name');
        return rows.map(Product.fromMap).toList();
      }, interval: const Duration(seconds: 10));

  Stream<List<Deal>> deals() => _poll(() async {
        final rows = await _client.from('deals').select('id, name, item_names, original_price, deal_price, image_url, active, archived_at').order('name');
        return rows.map(Deal.fromMap).toList();
      }, interval: const Duration(seconds: 10));

  Stream<List<HomeSlide>> slides() => _poll(() async {
        final rows = await _client.from('home_slides').select('id, title, subtitle, image_url, link_type, link_id, sort_order, active').order('sort_order').order('created_at');
        return rows.map(HomeSlide.fromMap).toList();
      }, interval: const Duration(seconds: 10));

  Stream<RestaurantSettings> settings() => _poll(() async {
        final row = await _client.from('app_settings').select('id, delivery_fee, new_order_notifications, order_status_notifications, pending_alert_minutes, daily_sales_summary').eq('id', 'main').maybeSingle();
        return [RestaurantSettings.fromMap(row)];
      }, interval: const Duration(seconds: 15)).map((values) => values.first);

  Future<List<MashOrder>> fetchOrders({String? customerId, bool riderOnly = false}) async {
    var query = _client.from('orders').select(_orderSelect);
    if (customerId != null) query = query.eq(riderOnly ? 'assigned_rider_id' : 'customer_id', customerId);
    final rows = await query.order('created_at', ascending: false).timeout(requestTimeout);
    return rows.map(MashOrder.fromMap).toList();
  }

  Future<MashOrder?> fetchOrder(String orderId, {String? customerId, bool riderOnly = false}) async {
    var query = _client.from('orders').select(_orderSelect).eq('id', orderId);
    if (customerId != null) query = query.eq(riderOnly ? 'assigned_rider_id' : 'customer_id', customerId);
    final row = await query.maybeSingle().timeout(requestTimeout);
    return row == null ? null : MashOrder.fromMap(row);
  }

  RealtimeChannel subscribeToOrderChanges({
    required void Function(String orderId, String source) onChanged,
    required void Function(bool connected) onConnectionChanged,
  }) {
    void handleOrder(PostgresChangePayload payload) {
      final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
      final id = record['id'] as String?;
      if (id != null) onChanged(id, 'orders.${payload.eventType.name}');
    }

    void handleOrderItem(PostgresChangePayload payload) {
      final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
      final id = record['order_id'] as String?;
      if (id != null) onChanged(id, 'order_items.${payload.eventType.name}');
    }

    final channel = _client
        .channel('mashbash-orders-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'orders', callback: handleOrder)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'order_items', callback: handleOrderItem);
    channel.subscribe((status, error) {
      onConnectionChanged(status == RealtimeSubscribeStatus.subscribed);
      if (error != null && !_connectionFailures.isClosed) _connectionFailures.add(error);
    });
    return channel;
  }

  Future<void> removeOrderChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }

  Future<String> placeOrder({
    required List<CartLine> lines,
    required String address,
    required String phone,
    required String paymentMethod,
    required int deliveryFee,
  }) async {
    final id = await _client.rpc('place_order', params: {
      'p_address': address,
      'p_phone': phone,
      'p_payment_method': paymentMethod,
      'p_delivery_fee': deliveryFee,
      'p_items': lines.map((line) => {'product_id': line.product.id, 'quantity': line.quantity}).toList(),
    });
    return id as String;
  }

  Future<void> updateOrderStatus(String id, OrderStatus status) =>
      _client.rpc('update_order_status', params: {'p_order_id': id, 'p_status': status.dbValue});

  Future<void> assignRider(String orderId, String riderId) =>
      _client.rpc('assign_order_rider', params: {'p_order_id': orderId, 'p_rider_id': riderId});

  Future<void> setRiderAvailability(bool available) => _client.rpc('set_rider_availability', params: {'p_available': available});

  Future<void> saveCategory(MenuCategory category) async {
    final values = category.toMap();
    if (category.id.isEmpty) values.remove('id');
    await _client.from('categories').upsert(values);
  }
  Future<void> setCategoryActive(String id, bool active) => _client.from('categories').update({'active': active}).eq('id', id);
  Future<void> archiveCategory(String id, bool archived) => _client.from('categories').update({'active': false, 'archived_at': archived ? DateTime.now().toIso8601String() : null}).eq('id', id);

  Future<void> saveProduct(Product product) async {
    var categoryId = product.categoryId;
    if (categoryId.isEmpty) {
      final category = await _client.from('categories').select('id').eq('name', product.category).single();
      categoryId = category['id'] as String;
    }
    await _client.from('products').upsert({...product.toMap(), 'id': product.id, 'category_id': categoryId});
  }

  Future<void> setProductAvailable(String id, bool available) => _client.from('products').update({'available': available}).eq('id', id);
  Future<void> archiveProduct(String id, bool archived) => _client.from('products').update({'available': false, 'archived_at': archived ? DateTime.now().toIso8601String() : null}).eq('id', id);

  Future<void> saveDeal(Deal deal) => _client.from('deals').upsert({
        'id': deal.id,
        'name': deal.name,
        'item_names': deal.itemNames,
        'original_price': deal.originalPrice,
        'deal_price': deal.dealPrice,
        'image_url': deal.imageUrl,
        'active': deal.active,
        'archived_at': deal.archivedAt?.toIso8601String(),
      });

  Future<void> setDealActive(String id, bool active) => _client.from('deals').update({'active': active}).eq('id', id);
  Future<void> archiveDeal(String id, bool archived) => _client.from('deals').update({'active': false, 'archived_at': archived ? DateTime.now().toIso8601String() : null}).eq('id', id);
  Future<void> saveSlide(HomeSlide slide) => _client.from('home_slides').upsert(slide.toMap());
  Future<void> deleteSlide(String id) => _client.from('home_slides').delete().eq('id', id);
  Future<void> saveSettings(RestaurantSettings settings) => _client.from('app_settings').upsert(settings.toMap());

  Future<void> saveDeviceToken(String token, String platform) =>
      _client.rpc('register_device_token', params: {'p_token': token, 'p_platform': platform});

  Future<void> deactivateDeviceToken(String token) =>
      _client.rpc('deactivate_device_token', params: {'p_token': token});

  Future<void> notifyOrderEvent(String event, String orderId) async {
    await _invokeNotification({'event': event, 'order_id': orderId});
  }

  Future<void> sendCustomNotification({required String title, required String body}) async {
    await _invokeNotification({'event': 'custom', 'title': title, 'body': body, 'all_customers': true});
  }

  Future<void> sendTestNotification() async {
    final data = await _invokeNotification({'event': 'test'});
    if (data is Map && (data['sent'] as num? ?? 0) == 0) {
      throw const NotificationDeliveryException('No active notification token was found for this device. Sign out, sign in, and allow notifications.');
    }
  }

  Future<dynamic> _invokeNotification(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke('send-notification', body: body);
    if (response.status >= 300) {
      throw NotificationDeliveryException(_functionMessage(response.data, 'Notification delivery is temporarily unavailable. Please try again.'));
    }
    return response.data;
  }

  Future<void> healthCheck() async {
    await _client.from('app_settings').select('id').eq('id', 'main').limit(1).timeout(requestTimeout);
  }

  Future<void> manageStaff({required String action, required String userId}) async {
    final response = await _client.functions.invoke('create-staff', body: {'action': action, 'user_id': userId});
    if (response.status >= 300) throw Exception(_functionMessage(response.data, 'Staff account could not be updated.'));
  }

  Stream<List<T>> _poll<T>(Future<List<T>> Function() fetch, {Duration interval = const Duration(seconds: 5)}) async* {
    while (true) {
      try {
        yield await fetch().timeout(requestTimeout);
      } catch (exception) {
        if (!_connectionFailures.isClosed) _connectionFailures.add(exception);
      }
      await Future<void>.delayed(interval);
    }
  }

  void dispose() => _connectionFailures.close();
}

String _functionMessage(dynamic data, String fallback) {
  if (data is Map && data['error'] is String) return data['error'] as String;
  return fallback;
}
