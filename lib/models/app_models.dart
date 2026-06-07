enum UserRole { customer, owner, manager, counter, rider }

enum OrderStatus {
  received('received'),
  accepted('accepted'),
  preparing('preparing'),
  readyForDelivery('ready_for_delivery'),
  assignedToRider('assigned_to_rider'),
  outForDelivery('out_for_delivery'),
  delivered('delivered'),
  cancelled('cancelled');

  const OrderStatus(this.dbValue);
  final String dbValue;

  static OrderStatus fromDb(String? value) => values.firstWhere(
        (status) => status.dbValue == value || status.name == value,
        orElse: () => value == 'processing' ? preparing : received,
      );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.role,
    this.email = '',
    this.rights = const {},
    this.active = true,
    this.available = false,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String email;
  final UserRole role;
  final Map<String, bool> rights;
  final bool active;
  final bool available;

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
        active: map['active'] as bool? ?? true,
        available: map['rider_available'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'email': email,
        'updated_at': DateTime.now().toIso8601String(),
      };

  AppUser copyWith({String? name, String? phone, String? address, Map<String, bool>? rights, bool? active, bool? available}) => AppUser(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        email: email,
        role: role,
        rights: rights ?? this.rights,
        active: active ?? this.active,
        available: available ?? this.available,
      );
}

class MenuCategory {
  const MenuCategory({required this.id, required this.name, this.imageUrl = '', this.sortOrder = 0, this.active = true, this.archivedAt});
  final String id;
  final String name;
  final String imageUrl;
  final int sortOrder;
  final bool active;
  final DateTime? archivedAt;
  bool get archived => archivedAt != null;
  bool get customerVisible => active && !archived;

  factory MenuCategory.fromMap(Map<String, dynamic> map) => MenuCategory(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        imageUrl: map['image_url'] as String? ?? map['icon_url'] as String? ?? '',
        sortOrder: (map['sort_order'] as num?)?.round() ?? 0,
        active: map['active'] as bool? ?? map['is_active'] as bool? ?? true,
        archivedAt: DateTime.tryParse(map['archived_at'] as String? ?? ''),
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'image_url': imageUrl, 'sort_order': sortOrder, 'active': active, 'archived_at': archivedAt?.toIso8601String()};
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    this.categoryId = '',
    this.imageUrl = '',
    this.available = true,
    this.sortOrder = 0,
    this.categoryVisible = true,
    this.archivedAt,
  });

  final String id;
  final String categoryId;
  final String name;
  final String category;
  final String description;
  final int price;
  final String imageUrl;
  final bool available;
  final int sortOrder;
  final bool categoryVisible;
  final DateTime? archivedAt;
  bool get archived => archivedAt != null;
  bool get customerVisible => available && categoryVisible && !archived;

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        categoryId: map['category_id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        category: map['category'] as String? ?? ((map['categories'] as Map?)?['name'] as String? ?? ''),
        description: map['description'] as String? ?? '',
        price: (map['price'] as num?)?.round() ?? 0,
        imageUrl: map['image_url'] as String? ?? '',
        available: map['available'] as bool? ?? map['is_available'] as bool? ?? true,
        sortOrder: (map['sort_order'] as num?)?.round() ?? 0,
        categoryVisible: ((map['categories'] as Map?)?['active'] as bool? ?? true) && (map['categories'] as Map?)?['archived_at'] == null,
        archivedAt: DateTime.tryParse(map['archived_at'] as String? ?? ''),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'price': price,
        'image_url': imageUrl,
        'available': available,
        'sort_order': sortOrder,
        'archived_at': archivedAt?.toIso8601String(),
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
    this.assignedRiderId,
    this.assignedRiderName = '',
    this.acceptedBy,
    this.assignedAt,
    this.deliveredAt,
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
  final String? assignedRiderId;
  final String assignedRiderName;
  final String? acceptedBy;
  final DateTime? assignedAt;
  final DateTime? deliveredAt;
  int get total => subtotal + deliveryFee;

  factory MashOrder.fromMap(Map<String, dynamic> map) {
    final rider = map['assigned_rider'] as Map?;
    return MashOrder(
      id: map['id'] as String,
      customerId: map['customer_id'] as String? ?? '',
      customerName: map['customer_name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String? ?? '',
      paymentMethod: map['payment_method'] as String? ?? '',
      items: List<Map<String, dynamic>>.from(map['order_items'] as List? ?? const []),
      subtotal: (map['subtotal'] as num?)?.round() ?? 0,
      deliveryFee: (map['delivery_fee'] as num?)?.round() ?? 0,
      status: OrderStatus.fromDb(map['status'] as String?),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      assignedRiderId: map['assigned_rider_id'] as String?,
      assignedRiderName: rider?['name'] as String? ?? '',
      acceptedBy: map['accepted_by'] as String?,
      assignedAt: DateTime.tryParse(map['assigned_at'] as String? ?? ''),
      deliveredAt: DateTime.tryParse(map['delivered_at'] as String? ?? ''),
    );
  }
}

class Deal {
  const Deal({required this.id, required this.name, required this.itemNames, required this.originalPrice, required this.dealPrice, this.imageUrl = '', this.active = true, this.archivedAt});
  final String id;
  final String name;
  final List<String> itemNames;
  final int originalPrice;
  final int dealPrice;
  final String imageUrl;
  final bool active;
  final DateTime? archivedAt;
  bool get archived => archivedAt != null;
  bool get customerVisible => active && !archived;

  factory Deal.fromMap(Map<String, dynamic> map) => Deal(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        itemNames: List<String>.from(map['item_names'] as List? ?? const []),
        originalPrice: (map['original_price'] as num?)?.round() ?? 0,
        dealPrice: (map['deal_price'] as num?)?.round() ?? 0,
        imageUrl: map['image_url'] as String? ?? '',
        active: map['active'] as bool? ?? true,
        archivedAt: DateTime.tryParse(map['archived_at'] as String? ?? ''),
      );

  Product asProduct() => Product(id: 'deal:$id', name: name, category: 'Deals', description: itemNames.join(' + '), price: dealPrice, imageUrl: imageUrl, available: customerVisible, archivedAt: archivedAt);
}

class RestaurantSettings {
  const RestaurantSettings({
    this.deliveryFee = 120,
    this.newOrderNotifications = true,
    this.pendingAlertMinutes = 15,
    this.dailySalesSummary = false,
  });

  final int deliveryFee;
  final bool newOrderNotifications;
  final int pendingAlertMinutes;
  final bool dailySalesSummary;

  factory RestaurantSettings.fromMap(Map<String, dynamic>? map) => RestaurantSettings(
        deliveryFee: (map?['delivery_fee'] as num?)?.round() ?? 120,
        newOrderNotifications: map?['new_order_notifications'] as bool? ?? true,
        pendingAlertMinutes: (map?['pending_alert_minutes'] as num?)?.round() ?? 15,
        dailySalesSummary: map?['daily_sales_summary'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': 'main',
        'delivery_fee': deliveryFee,
        'new_order_notifications': newOrderNotifications,
        'pending_alert_minutes': pendingAlertMinutes,
        'daily_sales_summary': dailySalesSummary,
        'updated_at': DateTime.now().toIso8601String(),
      };
}

class HomeSlide {
  const HomeSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.linkType = 'none',
    this.linkId = '',
    this.sortOrder = 0,
    this.active = true,
  });
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String linkType;
  final String linkId;
  final int sortOrder;
  final bool active;

  factory HomeSlide.fromMap(Map<String, dynamic> map) => HomeSlide(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        subtitle: map['subtitle'] as String? ?? '',
        imageUrl: map['image_url'] as String? ?? '',
        linkType: map['link_type'] as String? ?? 'none',
        linkId: map['link_id'] as String? ?? '',
        sortOrder: (map['sort_order'] as num?)?.round() ?? 0,
        active: map['active'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'image_url': imageUrl,
        'link_type': linkType,
        'link_id': linkId.isEmpty ? null : linkId,
        'sort_order': sortOrder,
        'active': active,
      };
}

bool productMatchesQuery(Product product, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return '${product.name} ${product.description} ${product.category}'.toLowerCase().contains(needle);
}

bool dealMatchesQuery(Deal deal, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return '${deal.name} ${deal.itemNames.join(' ')} deals'.toLowerCase().contains(needle);
}

Map<String, bool> _permissions(Map<String, dynamic> map) {
  final raw = map['staff_permissions'];
  final permission = raw is List && raw.isNotEmpty ? raw.first as Map : raw is Map ? raw : const {};
  return {
    'viewOrders': permission['view_orders'] as bool? ?? false,
    'updateOrderStatus': permission['update_order_status'] as bool? ?? false,
    'assignRiders': permission['assign_riders'] as bool? ?? false,
    'manageMenu': permission['manage_menu'] as bool? ?? false,
    'manageDeals': permission['manage_deals'] as bool? ?? false,
    'manageSlides': permission['manage_slides'] as bool? ?? false,
    'viewReports': permission['view_reports'] as bool? ?? false,
  };
}
