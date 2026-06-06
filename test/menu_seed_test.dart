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
        'manage_menu': false,
        'manage_deals': true,
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
    expect(user.can('manageMenu'), isFalse);
    expect(product.category, 'Beefbash');
    expect(product.imageUrl, 'https://example.com/sada.jpg');
  });
}
