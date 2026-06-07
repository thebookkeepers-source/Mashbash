import 'package:flutter_test/flutter_test.dart';
import 'package:mashbash/models/app_models.dart';
import 'package:mashbash/utils/seed_data.dart';

void main() {
  test('seed menu contains every Mashbash category and correct totals', () {
    expect(mashMenu.length, 19);
    expect(mashCategories.every((category) => mashMenu.any((product) => product.category == category)), isTrue);
    expect(mashMenu.firstWhere((product) => product.id == 'sada-wala').price, 550);
  });

  test('cart line calculates quantity total', () {
    const product = Product(id: 'test', name: 'Test', category: 'Dips', description: 'Test product', price: 70);
    const line = CartLine(product: product, quantity: 3);
    expect(line.total, 210);
  });

  test('Supabase rows map roles, permissions, and snake case fields', () {
    final user = AppUser.fromMap({
      'id': 'manager-1',
      'name': 'Shift Manager',
      'role': 'manager',
      'staff_permissions': {
        'view_orders': true,
        'update_order_status': true,
        'assign_riders': true,
        'manage_menu': false,
        'manage_deals': true,
        'manage_slides': true,
        'view_reports': true,
      },
    });
    final product = Product.fromMap({
      'id': 'sada-wala',
      'name': 'Sada Wala',
      'price': 550,
      'image_url': 'https://example.com/sada.jpg',
      'categories': {'name': 'Beefbash'},
    });

    expect(user.role, UserRole.manager);
    expect(user.can('manageDeals'), isTrue);
    expect(user.can('assignRiders'), isTrue);
    expect(user.can('manageSlides'), isTrue);
    expect(user.can('manageMenu'), isFalse);
    expect(product.category, 'Beefbash');
    expect(product.imageUrl, 'https://example.com/sada.jpg');
  });

  test('production order statuses map from Supabase snake case', () {
    expect(OrderStatus.fromDb('ready_for_delivery'), OrderStatus.readyForDelivery);
    expect(OrderStatus.fromDb('assigned_to_rider'), OrderStatus.assignedToRider);
    expect(OrderStatus.outForDelivery.dbValue, 'out_for_delivery');
    expect(OrderStatus.fromDb('processing'), OrderStatus.preparing);
  });

  test('rider, category, slide, and deal models support production workflows', () {
    final rider = AppUser.fromMap({'id': 'rider-1', 'name': 'Rider', 'role': 'rider', 'rider_available': true});
    final category = MenuCategory.fromMap({'id': 'category-1', 'name': 'Extras', 'image_url': 'https://example.com/extras.jpg', 'sort_order': 6, 'active': false});
    final slide = HomeSlide.fromMap({'id': 'slide-1', 'title': 'Deal', 'image_url': 'https://example.com/slide.jpg', 'link_type': 'deal', 'link_id': 'deal-1'});
    const deal = Deal(id: 'deal-1', name: 'Deal', itemNames: ['Burger'], originalPrice: 700, dealPrice: 600);

    expect(rider.role, UserRole.rider);
    expect(rider.available, isTrue);
    expect(category.active, isFalse);
    expect(slide.linkType, 'deal');
    expect(deal.asProduct().id, 'deal:deal-1');
  });
}
