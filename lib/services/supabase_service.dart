import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';

class SupabaseService {
  SupabaseService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;
  final StreamController<Object> _connectionFailures = StreamController<Object>.broadcast();
  static const requestTimeout = Duration(seconds: 15);

  Stream<Object> get connectionFailures => _connectionFailures.stream;

  Future<AppUser?> getUser(String uid) async {
    final row = await _client.from('profiles').select('*, staff_permissions(*)').eq('id', uid).maybeSingle().timeout(requestTimeout);
    return row == null ? null : AppUser.fromMap(row);
  }

  Future<void> saveUser(AppUser user) => _client.from('profiles').update(user.toMap()).eq('id', user.id);

  Stream<List<AppUser>> staff() => _poll(() async {
        final rows = await _client.from('profiles').select('*, staff_permissions(*)').inFilter('role', ['manager', 'counter', 'rider']).order('name');
        return rows.map(AppUser.fromMap).toList();
      });

  Stream<List<AppUser>> availableRiders() => _poll(() async {
        final rows = await _client.from('profiles').select().eq('role', 'rider').eq('active', true).eq('rider_available', true).order('name');
        return rows.map(AppUser.fromMap).toList();
      }, interval: const Duration(seconds: 3));

  Stream<List<MenuCategory>> categories() => _poll(() async {
        final rows = await _client.from('categories').select().order('sort_order').order('name');
        return rows.map(MenuCategory.fromMap).toList();
      });

  Stream<List<Product>> products() => _poll(() async {
        final rows = await _client.from('products').select('*, categories(name, active, archived_at)').order('sort_order').order('name');
        return rows.map(Product.fromMap).toList();
      });

  Stream<List<Deal>> deals() => _poll(() async {
        final rows = await _client.from('deals').select().order('name');
        return rows.map(Deal.fromMap).toList();
      });

  Stream<List<HomeSlide>> slides() => _poll(() async {
        final rows = await _client.from('home_slides').select().order('sort_order').order('created_at');
        return rows.map(HomeSlide.fromMap).toList();
      });

  Stream<RestaurantSettings> settings() => _poll(() async {
        final row = await _client.from('app_settings').select().eq('id', 'main').maybeSingle();
        return [RestaurantSettings.fromMap(row)];
      }).map((values) => values.first);

  Stream<List<MashOrder>> orders({String? customerId, bool riderOnly = false}) => _poll(() async {
        var query = _client.from('orders').select('*, order_items(*), assigned_rider:profiles!orders_assigned_rider_id_fkey(name)');
        if (customerId != null) query = query.eq(riderOnly ? 'assigned_rider_id' : 'customer_id', customerId);
        final rows = await query.order('created_at', ascending: false);
        return rows.map(MashOrder.fromMap).toList();
      }, interval: const Duration(seconds: 2));

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
    final response = await _client.functions.invoke('send-notification', body: {'event': event, 'order_id': orderId});
    if (response.status >= 300) throw Exception(_functionMessage(response.data, 'Notification could not be sent.'));
  }

  Future<void> sendCustomNotification({required String title, required String body}) async {
    final response = await _client.functions.invoke('send-notification', body: {'event': 'custom', 'title': title, 'body': body, 'all_customers': true});
    if (response.status >= 300) throw Exception(_functionMessage(response.data, 'Notification could not be sent.'));
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
        _connectionFailures.add(exception);
      }
      await Future<void>.delayed(interval);
    }
  }
}

String _functionMessage(dynamic data, String fallback) {
  if (data is Map && data['error'] is String) return data['error'] as String;
  return fallback;
}
