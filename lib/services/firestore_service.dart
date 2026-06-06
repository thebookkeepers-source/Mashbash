import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_models.dart';
import '../utils/seed_data.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<AppUser?> getUser(String uid) async {
    final snapshot = await _db.collection('users').doc(uid).get();
    return snapshot.exists ? AppUser.fromMap(snapshot.id, snapshot.data()!) : null;
  }

  Future<void> saveUser(AppUser user) => _db.collection('users').doc(user.id).set(user.toMap(), SetOptions(merge: true));

  Stream<List<AppUser>> staff() => _db
      .collection('users')
      .where('role', whereIn: ['manager', 'counter'])
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => AppUser.fromMap(doc.id, doc.data())).toList());

  Stream<List<Product>> products() => _db.collection('products').snapshots().map(
        (snapshot) => snapshot.docs.map((doc) => Product.fromMap(doc.id, doc.data())).toList(),
      );

  Stream<List<Deal>> deals() => _db.collection('deals').snapshots().map(
        (snapshot) => snapshot.docs.map((doc) => Deal.fromMap(doc.id, doc.data())).toList(),
      );

  Stream<List<MashOrder>> orders({String? customerId}) {
    Query<Map<String, dynamic>> query = _db.collection('orders');
    if (customerId != null) query = query.where('customerId', isEqualTo: customerId);
    return query.snapshots().map((snapshot) {
      final orders = snapshot.docs.map((doc) => MashOrder.fromMap(doc.id, doc.data())).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  Future<String> placeOrder({
    required AppUser user,
    required List<CartLine> lines,
    required String address,
    required String phone,
    required String paymentMethod,
    required int deliveryFee,
  }) async {
    final subtotal = lines.fold<int>(0, (sum, line) => sum + line.total);
    final ref = await _db.collection('orders').add({
      'customerId': user.id,
      'customerName': user.name,
      'phone': phone,
      'address': address,
      'paymentMethod': paymentMethod,
      'items': lines
          .map((line) => {'productId': line.product.id, 'name': line.product.name, 'price': line.product.price, 'quantity': line.quantity})
          .toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'status': OrderStatus.received.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateOrderStatus(String id, OrderStatus status) =>
      _db.collection('orders').doc(id).update({'status': status.name, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> saveProduct(Product product) =>
      _db.collection('products').doc(product.id).set(product.toMap(), SetOptions(merge: true));
  Future<void> deleteProduct(String id) => _db.collection('products').doc(id).delete();

  Future<void> saveDeal(Deal deal) => _db.collection('deals').doc(deal.id).set({
        'name': deal.name,
        'itemNames': deal.itemNames,
        'originalPrice': deal.originalPrice,
        'dealPrice': deal.dealPrice,
        'imageUrl': deal.imageUrl,
        'active': deal.active,
      }, SetOptions(merge: true));
  Future<void> deleteDeal(String id) => _db.collection('deals').doc(id).delete();
  Future<void> deleteStaff(String id) => _db.collection('users').doc(id).delete();

  Future<void> seedMenu() async {
    final marker = _db.collection('appConfig').doc('seed');
    if ((await marker.get()).exists) return;
    final batch = _db.batch();
    for (final product in mashMenu) {
      batch.set(_db.collection('products').doc(product.id), product.toMap());
    }
    batch.set(_db.collection('deals').doc('repeat-feast'), {
      'name': 'Repeat Feast',
      'itemNames': ['Sada Wala', 'Murgh Masti', 'Classy Fries'],
      'originalPrice': 1200,
      'dealPrice': 999,
      'imageUrl': '',
      'active': true,
    });
    batch.set(marker, {'version': 1, 'seededAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }
}
