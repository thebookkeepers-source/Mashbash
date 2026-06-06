import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { customer, owner, manager, counter }

enum OrderStatus { received, processing, outForDelivery, delivered }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.role,
    this.email = '',
    this.rights = const {},
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final UserRole role;
  final Map<String, bool> rights;

  bool can(String right) => role == UserRole.owner || rights[right] == true;
  bool get profileComplete => name.trim().isNotEmpty && phone.trim().isNotEmpty && address.trim().isNotEmpty;

  factory AppUser.fromMap(String id, Map<String, dynamic> map) => AppUser(
        id: id,
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        address: map['address'] as String? ?? '',
        email: map['email'] as String? ?? '',
        role: UserRole.values.firstWhere(
          (role) => role.name == map['role'],
          orElse: () => UserRole.customer,
        ),
        rights: Map<String, bool>.from(map['rights'] as Map? ?? const {}),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'address': address,
        'email': email,
        'role': role.name,
        'rights': rights,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  AppUser copyWith({String? name, String? phone, String? address, Map<String, bool>? rights}) => AppUser(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        email: email,
        role: role,
        rights: rights ?? this.rights,
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    this.imageUrl = '',
    this.available = true,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final int price;
  final String imageUrl;
  final bool available;

  factory Product.fromMap(String id, Map<String, dynamic> map) => Product(
        id: id,
        name: map['name'] as String? ?? '',
        category: map['category'] as String? ?? '',
        description: map['description'] as String? ?? '',
        price: (map['price'] as num?)?.round() ?? 0,
        imageUrl: map['imageUrl'] as String? ?? '',
        available: map['available'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'category': category,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'available': available,
      };
}

class CartLine {
  const CartLine({required this.product, required this.quantity});
  final Product product;
  final int quantity;
  int get total => product.price * quantity;
}

class MashOrder {
  const MashOrder({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.paymentMethod,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String phone;
  final String address;
  final String paymentMethod;
  final List<Map<String, dynamic>> items;
  final int subtotal;
  final int deliveryFee;
  final OrderStatus status;
  final DateTime createdAt;
  int get total => subtotal + deliveryFee;

  factory MashOrder.fromMap(String id, Map<String, dynamic> map) => MashOrder(
        id: id,
        customerId: map['customerId'] as String? ?? '',
        customerName: map['customerName'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        address: map['address'] as String? ?? '',
        paymentMethod: map['paymentMethod'] as String? ?? '',
        items: List<Map<String, dynamic>>.from(map['items'] as List? ?? const []),
        subtotal: (map['subtotal'] as num?)?.round() ?? 0,
        deliveryFee: (map['deliveryFee'] as num?)?.round() ?? 0,
        status: OrderStatus.values.firstWhere(
          (status) => status.name == map['status'],
          orElse: () => OrderStatus.received,
        ),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

class Deal {
  const Deal({
    required this.id,
    required this.name,
    required this.itemNames,
    required this.originalPrice,
    required this.dealPrice,
    this.imageUrl = '',
    this.active = true,
  });

  final String id;
  final String name;
  final List<String> itemNames;
  final int originalPrice;
  final int dealPrice;
  final String imageUrl;
  final bool active;

  factory Deal.fromMap(String id, Map<String, dynamic> map) => Deal(
        id: id,
        name: map['name'] as String? ?? '',
        itemNames: List<String>.from(map['itemNames'] as List? ?? const []),
        originalPrice: (map['originalPrice'] as num?)?.round() ?? 0,
        dealPrice: (map['dealPrice'] as num?)?.round() ?? 0,
        imageUrl: map['imageUrl'] as String? ?? '',
        active: map['active'] as bool? ?? true,
      );
}
