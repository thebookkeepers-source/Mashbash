enum UserRole { customer, owner, manager, counter }

enum OrderStatus { received, processing, outForDelivery, delivered }

class AppUser {
  const AppUser({required this.id, required this.name, required this.phone, required this.address, required this.role, this.email = '', this.rights = const {}});

  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final UserRole role;
  final Map<String, bool> rights;

  bool can(String right) => role == UserRole.owner || rights[right] == true;
  bool get profileComplete => name.trim().isNotEmpty && phone.trim().isNotEmpty && address.trim().isNotEmpty;

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        address: map['address'] as String? ?? '',
        email: map['email'] as String? ?? '',
        role: UserRole.values.firstWhere((role) => role.name == map['role'], orElse: () => UserRole.customer),
        rights: _permissions(map),
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'phone': phone, 'address': address, 'email': email, 'role': role.name, 'updated_at': DateTime.now().toIso8601String()};

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
  const Product({required this.id, required this.name, required this.category, required this.description, required this.price, this.imageUrl = '', this.available = true});

  final String id;
  final String name;
  final String category;
  final String description;
  final int price;
  final String imageUrl;
  final bool available;

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        category: map['category'] as String? ?? ((map['categories'] as Map?)?['name'] as String? ?? ''),
        description: map['description'] as String? ?? '',
        price: (map['price'] as num?)?.round() ?? 0,
        imageUrl: map['image_url'] as String? ?? '',
        available: map['available'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {'name': name, 'description': description, 'price': price, 'image_url': imageUrl, 'available': available};
}

class CartLine {
  const CartLine({required this.product, required this.quantity});
  final Product product;
  final int quantity;
  int get total => product.price * quantity;
}

class MashOrder {
  const MashOrder({required this.id, required this.customerId, required this.customerName, required this.phone, required this.address, required this.paymentMethod, required this.items, required this.subtotal, required this.deliveryFee, required this.status, required this.createdAt});

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

  factory MashOrder.fromMap(Map<String, dynamic> map) => MashOrder(
        id: map['id'] as String,
        customerId: map['customer_id'] as String? ?? '',
        customerName: map['customer_name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        address: map['address'] as String? ?? '',
        paymentMethod: map['payment_method'] as String? ?? '',
        items: List<Map<String, dynamic>>.from(map['order_items'] as List? ?? const []),
        subtotal: (map['subtotal'] as num?)?.round() ?? 0,
        deliveryFee: (map['delivery_fee'] as num?)?.round() ?? 0,
        status: OrderStatus.values.firstWhere((status) => status.name == map['status'], orElse: () => OrderStatus.received),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class Deal {
  const Deal({required this.id, required this.name, required this.itemNames, required this.originalPrice, required this.dealPrice, this.imageUrl = '', this.active = true});

  final String id;
  final String name;
  final List<String> itemNames;
  final int originalPrice;
  final int dealPrice;
  final String imageUrl;
  final bool active;

  factory Deal.fromMap(Map<String, dynamic> map) => Deal(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        itemNames: List<String>.from(map['item_names'] as List? ?? const []),
        originalPrice: (map['original_price'] as num?)?.round() ?? 0,
        dealPrice: (map['deal_price'] as num?)?.round() ?? 0,
        imageUrl: map['image_url'] as String? ?? '',
        active: map['active'] as bool? ?? true,
      );
}

Map<String, bool> _permissions(Map<String, dynamic> map) {
  final raw = map['staff_permissions'];
  final permission = raw is List && raw.isNotEmpty ? raw.first as Map : raw is Map ? raw : const {};
  return {
    'viewOrders': permission['view_orders'] as bool? ?? false,
    'updateOrderStatus': permission['update_order_status'] as bool? ?? false,
    'manageMenu': permission['manage_menu'] as bool? ?? false,
    'manageDeals': permission['manage_deals'] as bool? ?? false,
    'viewReports': permission['view_reports'] as bool? ?? false,
  };
}
