import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../models/app_models.dart';
import '../../providers/app_provider.dart';
import '../../utils/app_theme.dart';
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
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: index, children: const [HomeScreen(), OrderHistoryScreen(), ProfileScreen()]),
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _page = PageController();
  Timer? _timer;
  String? categoryId;
  String query = '';
  int slideIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final count = context.read<AppProvider>().activeSlides.length;
      if (count > 1 && _page.hasClients) _page.animateToPage((slideIndex + 1) % count, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final activeCategories = app.activeCategories;
    categoryId ??= activeCategories.isEmpty ? null : activeCategories.first.id;
    final selected = activeCategories.where((item) => item.id == categoryId).firstOrNull;
    final isSearching = query.trim().isNotEmpty;
    final showingDeals = !isSearching && categoryId == 'deals';
    final filtered = isSearching
        ? <Product>[
            ...app.products.where((product) => product.customerVisible && productMatchesQuery(product, query)),
            ...app.deals.where((deal) => deal.customerVisible && dealMatchesQuery(deal, query)).map((deal) => deal.asProduct()),
          ]
        : app.products.where((product) => product.customerVisible && (selected == null || product.categoryId == selected.id)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const MashLogo(compact: true, onDark: true),
        actions: [
          Badge(
            isLabelVisible: app.cartCount > 0,
            label: Text('${app.cartCount}'),
            child: IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())), icon: const Icon(Icons.shopping_bag_rounded)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ErrorBanner(),
              _SlideCarousel(
                controller: _page,
                slides: app.activeSlides,
                current: slideIndex,
                onChanged: (value) => setState(() => slideIndex = value),
                onTap: (slide) => _openSlide(context, slide),
              ),
              const SizedBox(height: 18),
              Text('AJ KIA CHALAY GA?', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: MashColors.primary)),
              const Text('Jigarr, zara menu check kar.', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(hintText: 'Search burgers, wraps, fries...', prefixIcon: Icon(Icons.search_rounded))),
              const SizedBox(height: 16),
              SizedBox(
                height: 94,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ...activeCategories.map((item) => _CategoryTile(category: item, selected: categoryId == item.id, onTap: () => setState(() => categoryId = item.id))),
                    _CategoryTile(
                      category: const MenuCategory(id: 'deals', name: 'Deals', imageUrl: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=300&q=80'),
                      selected: showingDeals,
                      onTap: () => setState(() => categoryId = 'deals'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionHeading(isSearching ? 'Search results' : (showingDeals ? 'Mashbash Deals' : (selected?.name ?? 'Menu'))),
            ]),
          ),
        ),
        if (showingDeals)
          _DealGrid(deals: app.deals.where((deal) => deal.customerVisible).toList())
        else if (filtered.isEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 260, child: EmptyState(icon: Icons.search_off_rounded, title: 'Nothing found', message: 'Try another search phrase.')))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 330, crossAxisSpacing: 10, mainAxisSpacing: 10),
              delegate: SliverChildBuilderDelegate((context, index) => ProductCard(product: filtered[index]), childCount: filtered.length),
            ),
          ),
      ]),
    );
  }

  void _openSlide(BuildContext context, HomeSlide slide) {
    final app = context.read<AppProvider>();
    if (slide.linkType == 'deal') {
      final deal = app.deals.where((item) => item.id == slide.linkId).firstOrNull;
      if (deal != null) showDialog(context: context, builder: (_) => _DealDialog(deal: deal));
    } else if (slide.linkType == 'product') {
      final product = app.products.where((item) => item.id == slide.linkId).firstOrNull;
      if (product != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)));
    } else if (slide.linkType == 'category') {
      setState(() => categoryId = slide.linkId);
    }
  }
}

class _SlideCarousel extends StatelessWidget {
  const _SlideCarousel({required this.controller, required this.slides, required this.current, required this.onChanged, required this.onTap});
  final PageController controller;
  final List<HomeSlide> slides;
  final int current;
  final ValueChanged<int> onChanged;
  final ValueChanged<HomeSlide> onTap;

  @override
  Widget build(BuildContext context) {
    if (slides.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      SizedBox(
        height: 190,
        child: PageView.builder(
          controller: controller,
          itemCount: slides.length,
          onPageChanged: onChanged,
          itemBuilder: (_, index) {
            final slide = slides[index];
            return GestureDetector(
              onTap: () => onTap(slide),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: MashColors.primary),
                child: Stack(fit: StackFit.expand, children: [
                  CachedNetworkImage(imageUrl: slide.imageUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => const ColoredBox(color: MashColors.primary)),
                  const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xE68B0000)]))),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text(slide.title.toUpperCase(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: MashColors.secondary)),
                      Text(slide.subtitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(slides.length, (index) => AnimatedContainer(duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 3), height: 7, width: index == current ? 24 : 7, decoration: BoxDecoration(color: index == current ? MashColors.primary : MashColors.secondary, borderRadius: BorderRadius.circular(9))))),
    ]);
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.selected, required this.onTap});
  final MenuCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 82,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? MashColors.secondary : Colors.white, border: Border.all(color: selected ? MashColors.primary : const Color(0xFFE8DED1), width: selected ? 2 : 1)),
              child: ClipOval(child: CachedNetworkImage(imageUrl: category.imageUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.lunch_dining_rounded, color: MashColors.primary))),
            ),
            const SizedBox(height: 4),
            Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? MashColors.primary : MashColors.ink)),
          ]),
        ),
      );
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
            padding: const EdgeInsets.all(9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ProductImage(product: product, height: 118),
              const SizedBox(height: 8),
              Text(product.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17, color: MashColors.primary)),
              Text(product.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const Spacer(),
              Row(children: List.generate(5, (_) => const Icon(Icons.star_rounded, size: 14, color: MashColors.secondary))),
              const SizedBox(height: 4),
              Text(money(product.price), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: FilledButton.icon(onPressed: () => context.read<AppProvider>().add(product), icon: const Icon(Icons.add_shopping_cart_rounded, size: 17), label: const Text('ADD')),
              ),
            ]),
          ),
        ),
      );
}

class _DealGrid extends StatelessWidget {
  const _DealGrid({required this.deals});
  final List<Deal> deals;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        sliver: deals.isEmpty
            ? const SliverToBoxAdapter(child: SizedBox(height: 260, child: EmptyState(icon: Icons.local_offer_outlined, title: 'No active deals', message: 'Fresh offers are coming soon.')))
            : SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 330, crossAxisSpacing: 10, mainAxisSpacing: 10),
                delegate: SliverChildBuilderDelegate((context, index) => _DealCard(deal: deals[index]), childCount: deals.length),
              ),
      );
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal});
  final Deal deal;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDialog(context: context, builder: (_) => _DealDialog(deal: deal)),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ProductImage(product: deal.asProduct(), height: 116),
              const SizedBox(height: 8),
              Text(deal.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17, color: MashColors.primary)),
              Text(deal.itemNames.join(' + '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              const Spacer(),
              Text(money(deal.originalPrice), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.black45)),
              Text(money(deal.dealPrice), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              SizedBox(width: double.infinity, height: 38, child: FilledButton(onPressed: () => context.read<AppProvider>().addDeal(deal), child: const Text('ADD DEAL'))),
            ]),
          ),
        ),
      );
}

class _DealDialog extends StatelessWidget {
  const _DealDialog({required this.deal});
  final Deal deal;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(deal.name.toUpperCase()),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProductImage(product: deal.asProduct(), height: 180),
            const SizedBox(height: 12),
            Text(deal.itemNames.join(' + ')),
            const SizedBox(height: 8),
            Text(money(deal.dealPrice), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: MashColors.primary)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(onPressed: () {
            context.read<AppProvider>().addDeal(deal);
            Navigator.pop(context);
          }, child: const Text('Add to cart')),
        ],
      );
}

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({required this.product, super.key});
  final Product product;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(product.name)),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          ProductImage(product: product, height: 280),
          const SizedBox(height: 18),
          Text(product.category.toUpperCase(), style: const TextStyle(color: MashColors.primary, fontWeight: FontWeight.w900, letterSpacing: 1)),
          Text(product.name.toUpperCase(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: MashColors.primary)),
          const SizedBox(height: 8),
          Text(product.description, style: const TextStyle(fontSize: 16, height: 1.5)),
          const SizedBox(height: 18),
          Text(money(product.price), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              context.read<AppProvider>().add(product);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product.name} added to cart.')));
            },
            icon: const Icon(Icons.shopping_bag_rounded),
            label: const Text('ADD TO CART'),
          ),
        ]),
      );
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('YOUR CART')),
      body: app.cartLines.isEmpty
          ? const EmptyState(icon: Icons.shopping_bag_outlined, title: 'Your cart is hungry', message: 'Add a Mashbash favorite and it will appear here.')
          : ListView(padding: const EdgeInsets.all(14), children: [
              ...app.cartLines.map((line) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        SizedBox(width: 70, child: ProductImage(product: line.product, height: 68)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w900)), Text(money(line.product.price))])),
                        _QuantityButton(icon: Icons.remove, onTap: () => app.decrement(line.product)),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w900))),
                        _QuantityButton(icon: Icons.add, onTap: () => app.add(line.product)),
                        IconButton(onPressed: () => app.remove(line.product), icon: const Icon(Icons.delete_outline, color: MashColors.primary)),
                      ]),
                    ),
                  )),
              MashPanel(
                child: Column(children: [
                  _TotalRow(label: 'Subtotal', value: app.subtotal),
                  _TotalRow(label: 'Delivery', value: app.deliveryFee),
                  const Divider(),
                  _TotalRow(label: 'Total', value: app.subtotal + app.deliveryFee, strong: true),
                ]),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen())), icon: const Icon(Icons.arrow_forward_rounded), label: const Text('CHECKOUT')),
            ]),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(30), child: Container(width: 30, height: 30, decoration: const BoxDecoration(shape: BoxShape.circle, color: MashColors.secondary), child: Icon(icon, size: 17, color: MashColors.primary)));
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.strong = false});
  final String label;
  final int value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
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
      appBar: AppBar(title: const Text('CHECKOUT')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const ErrorBanner(),
          const SectionHeading('Delivery details'),
          const SizedBox(height: 10),
          TextFormField(controller: _address, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Delivery address'), decoration: const InputDecoration(labelText: 'Delivery address', prefixIcon: Icon(Icons.location_on_rounded))),
          const SizedBox(height: 12),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_rounded))),
          const SizedBox(height: 18),
          const SectionHeading('Payment'),
          ...['Cash on Delivery', 'JazzCash', 'Easypaisa'].map((method) => RadioListTile<String>(value: method, groupValue: payment, onChanged: (value) => setState(() => payment = value!), title: Text(method), secondary: Icon(method == 'Cash on Delivery' ? Icons.payments_rounded : Icons.account_balance_wallet_rounded))),
          MashPanel(child: _TotalRow(label: 'Order total', value: app.subtotal + app.deliveryFee, strong: true)),
          const SizedBox(height: 16),
          AsyncButton(
            label: 'PLACE ORDER',
            icon: Icons.check_circle_rounded,
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final id = await context.read<AppProvider>().checkout(address: _address.text, phone: _phone.text, paymentMethod: payment);
              if (id != null && context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => OrderConfirmationScreen(orderId: id)), (route) => route.isFirst);
            },
          ),
        ]),
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(height: 180, child: Lottie.network('https://assets10.lottiefiles.com/packages/lf20_jbrw3hcz.json', errorBuilder: (_, __, ___) => const Icon(Icons.check_circle_rounded, size: 150, color: MashColors.success))),
                Text('ORDER PLACED!', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: MashColors.primary)),
                const SizedBox(height: 8),
                Text('Order #${orderId.substring(0, orderId.length > 8 ? 8 : orderId.length).toUpperCase()}'),
                const Text('Estimated delivery: 35-45 minutes'),
                const SizedBox(height: 24),
                ElevatedButton.icon(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId))), icon: const Icon(Icons.delivery_dining_rounded), label: const Text('TRACK ORDER')),
              ]),
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
    final order = matches.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('TRACK ORDER')),
      body: order == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              MashPanel(
                color: MashColors.secondary.withValues(alpha: .24),
                child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Order #${order.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(order.assignedRiderName.isEmpty ? 'Your order is moving through the kitchen.' : 'Rider: ${order.assignedRiderName}')])) , OrderStatusChip(status: order.status)]),
              ),
              const SizedBox(height: 16),
              ...OrderStatus.values.where((status) => status != OrderStatus.cancelled).map((status) {
                final complete = order.status != OrderStatus.cancelled && status.index <= order.status.index;
                final current = status == order.status;
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(children: [
                    CircleAvatar(radius: 18, backgroundColor: complete ? MashColors.primary : Colors.black12, child: Icon(complete ? Icons.check : Icons.circle_outlined, color: Colors.white, size: 18)),
                    if (status != OrderStatus.delivered) Container(width: 3, height: 38, color: complete ? MashColors.primary : Colors.black12),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: Padding(padding: const EdgeInsets.only(top: 7), child: Text(statusLabel(status), style: TextStyle(fontWeight: current ? FontWeight.w900 : FontWeight.w600, color: current ? MashColors.primary : MashColors.ink)))),
                ]);
              }),
              if (order.status == OrderStatus.cancelled) const MashPanel(color: Color(0xFFFFE3E3), child: Text('This order was cancelled.', style: TextStyle(fontWeight: FontWeight.w900, color: MashColors.primary))),
              const SizedBox(height: 16),
              MashPanel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Order items', style: TextStyle(fontWeight: FontWeight.w900)),
                  ...order.items.map((item) {
                    final quantity = (item['quantity'] as num? ?? 0).round();
                    final lineTotal = (item['line_total'] as num?)?.round() ?? (item['price'] as num? ?? 0).round() * quantity;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('$quantity x ${item['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: Text(money(lineTotal), style: const TextStyle(fontWeight: FontWeight.w900)),
                    );
                  }),
                ]),
              ),
              const SizedBox(height: 16),
              MashPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Delivering to', style: TextStyle(fontWeight: FontWeight.w900)), Text(order.address), const Divider(), _TotalRow(label: 'Total', value: order.total, strong: true)])),
            ]),
    );
  }
}

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final orders = context.watch<AppProvider>().orders;
    return Scaffold(
      appBar: AppBar(title: const Text('YOUR ORDERS')),
      body: orders.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', message: 'Your Mashbash orders will be saved here.')
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: orders.length,
              itemBuilder: (_, index) {
                final order = orders[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id))),
                    title: Text(order.items.map((item) => '${item['quantity']} x ${item['name']}').join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year} - ${money(order.total)}'),
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
        appBar: AppBar(title: const Text('PROFILE')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Center(child: CircleAvatar(radius: 48, backgroundColor: MashColors.secondary, child: Icon(Icons.person_rounded, color: MashColors.primary, size: 58))),
            const SizedBox(height: 18),
            const ErrorBanner(),
            TextFormField(controller: _name, validator: (value) => Validators.requiredText(value, 'Name'), decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
            const SizedBox(height: 12),
            TextFormField(controller: _address, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Address'), decoration: const InputDecoration(labelText: 'Delivery address')),
            const SizedBox(height: 18),
            AsyncButton(label: 'SAVE PROFILE', icon: Icons.save_rounded, onPressed: () {
              if (_form.currentState!.validate()) context.read<AppProvider>().saveProfile(name: _name.text, phone: _phone.text, address: _address.text);
            }),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: context.read<AppProvider>().logout, icon: const Icon(Icons.logout_rounded), label: const Text('Logout')),
          ]),
        ),
      );
}
