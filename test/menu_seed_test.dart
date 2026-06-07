import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mashbash/models/app_models.dart';
import 'package:mashbash/providers/app_provider.dart';
import 'package:mashbash/services/supabase_service.dart';
import 'package:mashbash/utils/feature_flags.dart';
import 'package:mashbash/utils/seed_data.dart';

void main() {
  test('Mashbash launcher and in-app branding assets are available', () {
    expect(File('assets/branding/app_icon_source.png').existsSync(), isTrue);
    expect(File('assets/branding/app_icon_foreground.png').existsSync(), isTrue);
    expect(File('assets/branding/logo.png').existsSync(), isTrue);
    expect(File('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png').existsSync(), isTrue);
    expect(File('flutter_launcher_icons.yaml').existsSync(), isTrue);
  });

  test('Android release configuration stays minimal and production-ready', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final customerScreens = File('lib/screens/customer/customer_screens.dart').readAsStringSync();

    expect(pubspec, contains('version: 1.0.0+1'));
    expect(manifest, contains('android:label="Mashbash"'));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    for (final permission in ['REQUEST_INSTALL_PACKAGES', 'READ_SMS', 'SEND_SMS', 'READ_CONTACTS', 'ACCESS_FINE_LOCATION', 'ACCESS_BACKGROUND_LOCATION', 'MANAGE_EXTERNAL_STORAGE', 'SYSTEM_ALERT_WINDOW']) {
      expect(manifest, isNot(contains(permission)));
    }
    expect(pubspec, isNot(contains('lottie:')));
    expect(customerScreens, isNot(contains('Lottie.network')));
    expect(File('.github/workflows/release.yml').existsSync(), isTrue);
  });

  test('Google login remains hidden until OAuth setup is enabled', () {
    final authScreen = File('lib/screens/auth/auth_screens.dart').readAsStringSync();
    final authService = File('lib/services/auth_service.dart').readAsStringSync();

    expect(FeatureFlags.googleSignIn, isFalse);
    expect(authScreen, contains('FeatureFlags.googleSignIn'));
    expect(authService, contains('signInWithGoogle'));
  });

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

  test('global search matches product details, category, and deals case-insensitively', () {
    const product = Product(id: 'murgh-masti', name: 'Murgh Masti', category: 'Chickbash', description: 'Single chicken patty', price: 500);
    const deal = Deal(id: 'lunch', name: 'Lunch Bash', itemNames: ['Murgh Masti'], originalPrice: 700, dealPrice: 600);

    expect(productMatchesQuery(product, 'masti'), isTrue);
    expect(productMatchesQuery(product, 'CHICKBASH'), isTrue);
    expect(productMatchesQuery(product, 'chicken patty'), isTrue);
    expect(dealMatchesQuery(deal, 'lunch'), isTrue);
    expect(dealMatchesQuery(deal, 'masti'), isTrue);
  });

  test('disabled and archived menu records are hidden without losing owner models', () {
    final archived = DateTime(2026, 6, 7);
    final category = MenuCategory.fromMap({'id': 'cat', 'name': 'Beefbash', 'active': true, 'archived_at': archived.toIso8601String()});
    final product = Product.fromMap({
      'id': 'burger',
      'name': 'Burger',
      'price': 500,
      'available': true,
      'categories': {'name': 'Beefbash', 'active': false},
    });
    final deal = Deal.fromMap({'id': 'deal', 'name': 'Deal', 'original_price': 600, 'deal_price': 500, 'active': false});

    expect(category.archived, isTrue);
    expect(category.customerVisible, isFalse);
    expect(product.customerVisible, isFalse);
    expect(deal.customerVisible, isFalse);
  });

  test('order item snapshot remains readable without current menu records', () {
    final order = MashOrder.fromMap({
      'id': 'order-1',
      'customer_id': 'customer-1',
      'customer_name': 'Customer',
      'order_items': [
        {'product_id': null, 'name': 'Archived Burger', 'price': 550, 'quantity': 2, 'line_total': 1100, 'category_name': 'Beefbash'}
      ],
      'subtotal': 1100,
      'delivery_fee': 120,
      'status': 'delivered',
      'created_at': '2026-06-07T00:00:00Z',
    });

    expect(order.items.single['name'], 'Archived Burger');
    expect(order.items.single['line_total'], 1100);
    expect(order.total, 1220);
  });

  test('connection failures never expose raw exception text', () {
    expect(friendlyError(SocketException('failed host lookup')), contains('error connecting to the server'));
    expect(friendlyError(const NotificationDeliveryException('Notification delivery is temporarily unavailable. Please try again.')), 'Notification delivery is temporarily unavailable. Please try again.');
    expect(friendlyError(Exception('secret database detail')), 'Something went wrong. Please try again.');
  });

  test('notification preferences default on and map to Supabase settings', () {
    const defaults = RestaurantSettings();
    final mapped = RestaurantSettings.fromMap({'delivery_fee': 150});

    expect(defaults.newOrderNotifications, isTrue);
    expect(defaults.orderStatusNotifications, isTrue);
    expect(mapped.orderStatusNotifications, isTrue);
    expect(defaults.toMap()['order_status_notifications'], isTrue);
  });
}
