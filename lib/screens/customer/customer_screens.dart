import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../models/app_models.dart';
import '../../providers/app_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/seed_data.dart';
import '../../utils/validators.dart';
import '../../widgets/mash_widgets.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const HomeScreen(), const OrderHistoryScreen(), const ProfileScreen()];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.restaurant_menu_rounded), label: 'Menu'),
          NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String category = mashCategories.first;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final filtered = app.products
        .where((product) => product.available && product.category == category && product.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const MashLogo(compact: true),
        actions: [
          Badge(
            isLabelVisible: app.cartCount > 0,
            label: Text('${app.cartCount}'),
            child: IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())), icon: const Icon(Icons.shopping_bag_rounded)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (app.deals.any((deal) => deal.active))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [MashColors.primary, Color(0xFFCF2D20)]),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TODAY AT MASHBASH', style: TextStyle(color: MashColors.secondary, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          Text(app.deals.firstWhere((deal) => deal.active).name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          Text('${app.deals.firstWhere((deal) => deal.active).itemNames.join(' + ')} • ${money(app.deals.firstWhere((deal) => deal.active).dealPrice)}', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(hintText: 'Search the Mashbash menu', prefixIcon: Icon(Icons.search_rounded))),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: mashCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final item = mashCategories[index];
                        return ChoiceChip(label: Text(item), selected: category == item, onSelected: (_) => setState(() => category = item));
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            const SliverFillRemaining(child: EmptyState(icon: Icons.search_off_rounded, title: 'Nothing found', message: 'Try another menu category or search phrase.'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, mainAxisExtent: 295, crossAxisSpacing: 12, mainAxisSpacing: 12),
                delegate: SliverChildBuilderDelegate((context, index) => ProductCard(product: filtered[index]), childCount: filtered.length),
              ),
            ),
        ],
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductImage(product: product, height: 145),
                const SizedBox(height: 10),
                Text(product.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(product.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const Spacer(),
                Row(
                  children: [
                    Text(money(product.price), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: MashColors.primary)),
                    const Spacer(),
                    FilledButton.tonalIcon(onPressed: () => context.read<AppProvider>().add(product), icon: const Icon(Icons.add), label: const Text('Add')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(product.name)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ProductImage(product: product, height: 280),
            const SizedBox(height: 20),
            Text(product.category.toUpperCase(), style: const TextStyle(color: MashColors.primary, fontWeight: FontWeight.w900, letterSpacing: 1)),
            Text(product.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(product.description, style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 18),
            Text(money(product.price), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: MashColors.primary)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                context.read<AppProvider>().add(product);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} added to your cart')));
              },
              icon: const Icon(Icons.shopping_bag_rounded),
              label: const Text('Add to cart'),
            ),
          ],
        ),
      );
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Your Cart')),
      body: app.cartLines.isEmpty
          ? const EmptyState(icon: Icons.shopping_bag_outlined, title: 'Your cart is hungry', message: 'Add a Mashbash favorite and it will appear here.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...app.cartLines.map((line) => Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: const Color(0xFFFFE0B2), child: const Icon(Icons.lunch_dining_rounded, color: MashColors.primary)),
                        title: Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${money(line.product.price)} × ${line.quantity}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(onPressed: () => app.decrement(line.product), icon: const Icon(Icons.remove_circle_outline)),
                          Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(onPressed: () => app.add(line.product), icon: const Icon(Icons.add_circle_outline)),
                          IconButton(onPressed: () => app.remove(line.product), icon: const Icon(Icons.delete_outline, color: MashColors.primary)),
                        ]),
                      ),
                    )),
                _TotalRow(label: 'Subtotal', value: app.subtotal),
                _TotalRow(label: 'Delivery', value: app.deliveryFee),
                _TotalRow(label: 'Total', value: app.subtotal + app.deliveryFee, strong: true),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen())),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Proceed to Checkout'),
                ),
              ],
            ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.strong = false});
  final String label;
  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(children: [Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w500, fontSize: strong ? 18 : 14)), const Spacer(), Text(money(value), style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w600, fontSize: strong ? 18 : 14, color: strong ? MashColors.primary : null))]),
      );
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _address;
  late final TextEditingController _phone;
  String payment = 'Cash on Delivery';

  @override
  void initState() {
    super.initState();
    final user = context.read<AppProvider>().user!;
    _address = TextEditingController(text: user.address);
    _phone = TextEditingController(text: user.phone);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const ErrorBanner(),
            Text('Delivery details', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextFormField(controller: _address, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Delivery address'), decoration: const InputDecoration(labelText: 'Delivery address', prefixIcon: Icon(Icons.location_on_rounded))),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_rounded))),
            const SizedBox(height: 20),
            Text('Payment method', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            ...['Cash on Delivery', 'JazzCash', 'Easypaisa'].map((method) => RadioListTile<String>(value: method, groupValue: payment, onChanged: (value) => setState(() => payment = value!), title: Text(method), secondary: Icon(method == 'Cash on Delivery' ? Icons.payments_rounded : Icons.account_balance_wallet_rounded))),
            const Divider(),
            _TotalRow(label: 'Order total', value: app.subtotal + app.deliveryFee, strong: true),
            const SizedBox(height: 16),
            AsyncButton(
              label: 'Place Order',
              icon: Icons.check_circle_rounded,
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                final id = await context.read<AppProvider>().checkout(address: _address.text, phone: _phone.text, paymentMethod: payment);
                if (id != null && context.mounted) {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => OrderConfirmationScreen(orderId: id)), (route) => route.isFirst);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 180,
                    child: Lottie.network(
                      'https://assets10.lottiefiles.com/packages/lf20_jbrw3hcz.json',
                      errorBuilder: (_, __, ___) => const Icon(Icons.check_circle_rounded, size: 150, color: MashColors.success),
                    ),
                  ),
                  Text('Order placed!', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Order #${orderId.substring(0, orderId.length > 8 ? 8 : orderId.length).toUpperCase()}'),
                  const Text('Estimated delivery: 35–45 minutes'),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId))), icon: const Icon(Icons.delivery_dining_rounded), label: const Text('Track order')),
                ],
              ),
            ),
          ),
        ),
      );
}

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final matches = context.watch<AppProvider>().orders.where((order) => order.id == orderId);
    final order = matches.isEmpty ? null : matches.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Track Order')),
      body: order == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                OrderStatusChip(status: order.status),
                const SizedBox(height: 20),
                ...OrderStatus.values.map((status) {
                  final complete = status.index <= order.status.index;
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: complete ? MashColors.primary : Colors.black12, child: Icon(complete ? Icons.check : Icons.circle_outlined, color: Colors.white)),
                    title: Text(statusLabel(status), style: TextStyle(fontWeight: complete ? FontWeight.w900 : FontWeight.w500)),
                    subtitle: Text(complete ? 'Completed' : 'Waiting'),
                  );
                }),
                const Divider(),
                Text('Delivering to', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                Text(order.address),
                const SizedBox(height: 12),
                _TotalRow(label: 'Total', value: order.total, strong: true),
              ],
            ),
    );
  }
}

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<AppProvider>().orders;
    return Scaffold(
      appBar: AppBar(title: const Text('Order History')),
      body: orders.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', message: 'Your Mashbash orders will be saved here.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (_, index) {
                final order = orders[index];
                return Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id))),
                    title: Text(order.items.map((item) => '${item['quantity']}× ${item['name']}').join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year} • ${money(order.total)}'),
                    trailing: OrderStatusChip(status: order.status),
                  ),
                );
              },
            ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppProvider>().user!;
    _name = TextEditingController(text: user.name);
    _phone = TextEditingController(text: user.phone);
    _address = TextEditingController(text: user.address);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Center(child: CircleAvatar(radius: 48, backgroundColor: MashColors.secondary, child: Icon(Icons.person_rounded, color: MashColors.primary, size: 58))),
              const SizedBox(height: 20),
              const ErrorBanner(),
              TextFormField(controller: _name, validator: (value) => Validators.requiredText(value, 'Name'), decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
              const SizedBox(height: 12),
              TextFormField(controller: _address, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Address'), decoration: const InputDecoration(labelText: 'Delivery address')),
              const SizedBox(height: 18),
              AsyncButton(label: 'Save profile', icon: Icons.save_rounded, onPressed: () {
                if (_form.currentState!.validate()) context.read<AppProvider>().saveProfile(name: _name.text, phone: _phone.text, address: _address.text);
              }),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: context.read<AppProvider>().logout, icon: const Icon(Icons.logout_rounded), label: const Text('Logout'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50))),
            ],
          ),
        ),
      );
}
