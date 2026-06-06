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
}
