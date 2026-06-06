import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_models.dart';

class SupabaseService {
  SupabaseService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<AppUser?> getUser(String uid) async {
    final row = await _client.from('profiles').select('*, staff_permissions(*)').eq('id', uid).maybeSingle();
    return row == null ? null : AppUser.fromMap(row);
  }

  Future<void> saveUser(AppUser user) async {
    await _client.from('profiles').update(user.toMap()).eq('id', user.id);
  }

  Stream<List<AppUser>> staff() => _poll(() async {
        final rows = await _client.from('profiles').select('*, staff_permissions(*)').inFilter('role', ['manager', 'counter']).order('name');
        return rows.map(AppUser.fromMap).toList();
      });

  Stream<List<Product>> products() => _poll(() async {
        final rows = await _client.from('products').select('*, categories(name)').order('name');
        return rows.map(Product.fromMap).toList();
      });

  Stream<List<Deal>> deals() => _poll(() async {
        final rows = await _client.from('deals').select().order('name');
        return rows.map(Deal.fromMap).toList();
      });

  Stream<List<MashOrder>> orders({String? customerId}) => _poll(() async {
        var query = _client.from('orders').select('*, order_items(*)');
        if (customerId != null) query = query.eq('customer_id', customerId);
        final rows = await query.order('created_at', ascending: false);
        return rows.map(MashOrder.fromMap).toList();
      }, interval: const Duration(seconds: 3));

  Future<String> placeOrder({required AppUser user, required List<CartLine> lines, required String address, required String phone, required String paymentMethod, required int deliveryFee}) async {
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
      _client.from('orders').update({'status': status.name, 'updated_at': DateTime.now().toIso8601String()}).eq('id', id);

  Future<void> saveProduct(Product product) async {
    final category = await _client.from('categories').select('id').eq('name', product.category).single();
    await _client.from('products').upsert({...product.toMap(), 'id': product.id, 'category_id': category['id']});
  }

  Future<void> deleteProduct(String id) => _client.from('products').delete().eq('id', id);

  Future<void> saveDeal(Deal deal) => _client.from('deals').upsert({
        'id': deal.id,
        'name': deal.name,
        'item_names': deal.itemNames,
        'original_price': deal.originalPrice,
        'deal_price': deal.dealPrice,
        'image_url': deal.imageUrl,
        'active': deal.active,
      });

  Future<void> deleteDeal(String id) => _client.from('deals').delete().eq('id', id);

  Future<void> deleteStaff(String id) async {
    final response = await _client.functions.invoke('create-staff', body: {'action': 'delete', 'user_id': id});
    if (response.status >= 300) throw Exception('Staff account could not be deleted.');
  }

  Stream<List<T>> _poll<T>(Future<List<T>> Function() fetch, {Duration interval = const Duration(seconds: 5)}) async* {
    while (true) {
      yield await fetch();
      await Future<void>.delayed(interval);
    }
  }
}
