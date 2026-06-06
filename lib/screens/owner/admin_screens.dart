import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/app_models.dart';
import '../../providers/app_provider.dart';
import '../../services/storage_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/seed_data.dart';
import '../../utils/validators.dart';
import '../../widgets/mash_widgets.dart';

class StaffPanel extends StatefulWidget {
  const StaffPanel({required this.role, super.key});
  final UserRole role;

  @override
  State<StaffPanel> createState() => _StaffPanelState();
}

class _StaffPanelState extends State<StaffPanel> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user!;
    final destinations = <_Destination>[
      const _Destination('Dashboard', Icons.dashboard_rounded, StaffDashboard()),
      if (user.can('viewOrders')) const _Destination('Orders', Icons.receipt_long_rounded, StaffOrdersScreen()),
      if (user.can('manageMenu')) const _Destination('Menu', Icons.restaurant_menu_rounded, MenuManagementScreen()),
      if (user.can('manageDeals')) const _Destination('Deals', Icons.local_offer_rounded, DealsManagementScreen()),
      if (widget.role == UserRole.owner) const _Destination('Team', Icons.groups_rounded, UserManagementScreen()),
      if (user.can('viewReports')) const _Destination('Reports', Icons.bar_chart_rounded, ReportsScreen()),
    ];
    if (index >= destinations.length) index = 0;
    return Scaffold(
      appBar: AppBar(
        title: const MashLogo(compact: true),
        actions: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Center(child: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700)))),
          IconButton(onPressed: context.read<AppProvider>().logout, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: destinations[index].screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: destinations.map((item) => NavigationDestination(icon: Icon(item.icon), label: item.label)).toList(),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.screen);
  final String label;
  final IconData icon;
  final Widget screen;
}

class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<AppProvider>().orders;
    final now = DateTime.now();
    final today = orders.where((order) => order.createdAt.year == now.year && order.createdAt.month == now.month && order.createdAt.day == now.day).toList();
    final sales = today.where((order) => order.status == OrderStatus.delivered).fold<int>(0, (sum, order) => sum + order.total);
    final bars = List.generate(7, (index) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - index));
      final total = orders
          .where((order) => order.status == OrderStatus.delivered && order.createdAt.year == day.year && order.createdAt.month == day.month && order.createdAt.day == day.day)
          .fold<int>(0, (sum, order) => sum + order.total);
      return BarChartGroupData(x: index, barRods: [BarChartRodData(toY: total.toDouble(), color: MashColors.primary, width: 18, borderRadius: BorderRadius.circular(6))]);
    });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Restaurant overview', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _MetricCard(label: "Today's sales", value: money(sales), icon: Icons.payments_rounded)),
          const SizedBox(width: 12),
          Expanded(child: _MetricCard(label: "Today's orders", value: '${today.length}', icon: Icons.receipt_long_rounded)),
        ]),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Revenue • Last 7 days', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 20),
                SizedBox(
                  height: 220,
                  child: BarChart(BarChartData(
                    barGroups: bars,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(topTitles: AxisTitles(), rightTitles: AxisTitles()),
                  )),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Recent orders', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        if (orders.isEmpty)
          const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', message: 'Incoming customer orders will appear here in real time.')
        else
          ...orders.take(5).map((order) => Card(child: ListTile(title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${order.items.length} items • ${money(order.total)}'), trailing: OrderStatusChip(status: order.status)))),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: MashColors.primary),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ]),
        ),
      );
}

class StaffOrdersScreen extends StatefulWidget {
  const StaffOrdersScreen({super.key});

  @override
  State<StaffOrdersScreen> createState() => _StaffOrdersScreenState();
}

class _StaffOrdersScreenState extends State<StaffOrdersScreen> {
  OrderStatus? filter;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppProvider>().user!;
    final orders = context.watch<AppProvider>().orders.where((order) => filter == null || order.status == filter).toList();
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            padding: const EdgeInsets.all(8),
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(label: const Text('All'), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
              const SizedBox(width: 6),
              ...OrderStatus.values.map((status) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(statusLabel(status)), selected: filter == status, onSelected: (_) => setState(() => filter = status)),
                  )),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? const EmptyState(icon: Icons.inbox_rounded, title: 'No matching orders', message: 'New orders matching this filter will appear automatically.')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (_, index) {
                    final order = orders[index];
                    final nextIndex = order.status.index + 1;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [Expanded(child: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))), OrderStatusChip(status: order.status)]),
                            Text(order.items.map((item) => '${item['quantity']}× ${item['name']}').join(', ')),
                            const SizedBox(height: 8),
                            Text(order.address),
                            Text('${order.phone} • ${order.paymentMethod} • ${money(order.total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            if (nextIndex < OrderStatus.values.length && user.can('updateOrderStatus')) ...[
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () => context.read<AppProvider>().firestore.updateOrderStatus(order.id, OrderStatus.values[nextIndex]),
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: Text('Mark ${statusLabel(OrderStatus.values[nextIndex])}'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class MenuManagementScreen extends StatelessWidget {
  const MenuManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final products = context.watch<AppProvider>().products;
    return Scaffold(
      body: products.isEmpty
          ? const EmptyState(icon: Icons.restaurant_menu_rounded, title: 'Menu is loading', message: 'The complete Mashbash menu will appear after Firebase connects.')
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: products.length,
              itemBuilder: (_, index) {
                final product = products[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: const Color(0xFFFFE0B2), child: Icon(product.available ? Icons.lunch_dining_rounded : Icons.block, color: MashColors.primary)),
                    title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('${product.category} • ${money(product.price)} • ${product.available ? 'Available' : 'Unavailable'}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') showDialog(context: context, builder: (_) => ProductEditor(product: product));
                        if (action == 'toggle') context.read<AppProvider>().firestore.saveProduct(Product(id: product.id, name: product.name, category: product.category, description: product.description, price: product.price, imageUrl: product.imageUrl, available: !product.available));
                        if (action == 'delete') context.read<AppProvider>().firestore.deleteProduct(product.id);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'toggle', child: Text('Toggle availability')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showDialog(context: context, builder: (_) => const ProductEditor()), icon: const Icon(Icons.add), label: const Text('Add product')),
    );
  }
}

class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, this.product});
  final Product? product;

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late String category;
  late bool available;
  File? image;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _description = TextEditingController(text: widget.product?.description ?? '');
    _price = TextEditingController(text: widget.product?.price.toString() ?? '');
    category = widget.product?.category ?? mashCategories.first;
    available = widget.product?.available ?? true;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product == null ? 'Add product' : 'Edit product'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(controller: _name, validator: (value) => Validators.requiredText(value, 'Name'), decoration: const InputDecoration(labelText: 'Product name')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField(value: category, items: mashCategories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => category = value!, decoration: const InputDecoration(labelText: 'Category')),
                  const SizedBox(height: 10),
                  TextFormField(controller: _description, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Description'), decoration: const InputDecoration(labelText: 'Description')),
                  const SizedBox(height: 10),
                  TextFormField(controller: _price, keyboardType: TextInputType.number, validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a valid price' : null, decoration: const InputDecoration(labelText: 'Price')),
                  SwitchListTile(value: available, onChanged: (value) => setState(() => available = value), title: const Text('Available')),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
                      if (picked != null) setState(() => image = File(picked.path));
                    },
                    icon: const Icon(Icons.image_rounded),
                    label: Text(image == null ? 'Choose product image' : 'Image selected'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final id = widget.product?.id ?? '${_name.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch}';
              var imageUrl = widget.product?.imageUrl ?? '';
              if (image != null) imageUrl = await StorageService().uploadProductImage(id, image!);
              await context.read<AppProvider>().firestore.saveProduct(Product(id: id, name: _name.text.trim(), category: category, description: _description.text.trim(), price: int.parse(_price.text), imageUrl: imageUrl, available: available));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      );
}

class DealsManagementScreen extends StatelessWidget {
  const DealsManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deals = context.watch<AppProvider>().deals;
    return Scaffold(
      body: deals.isEmpty
          ? const EmptyState(icon: Icons.local_offer_outlined, title: 'No deals active', message: 'Create a value-packed Mashbash deal for customers.')
          : ListView(
              padding: const EdgeInsets.all(12),
              children: deals
                  .map((deal) => Card(
                        child: ListTile(
                          title: Text(deal.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${deal.itemNames.join(' + ')}\n${money(deal.dealPrice)} • ${deal.active ? 'Active' : 'Inactive'}'),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') showDialog(context: context, builder: (_) => DealEditor(deal: deal));
                              if (action == 'toggle') context.read<AppProvider>().firestore.saveDeal(Deal(id: deal.id, name: deal.name, itemNames: deal.itemNames, originalPrice: deal.originalPrice, dealPrice: deal.dealPrice, imageUrl: deal.imageUrl, active: !deal.active));
                              if (action == 'delete') context.read<AppProvider>().firestore.deleteDeal(deal.id);
                            },
                            itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'toggle', child: Text('Toggle active')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                          ),
                        ),
                      ))
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showDialog(context: context, builder: (_) => const DealEditor()), icon: const Icon(Icons.add), label: const Text('Create deal')),
    );
  }
}

class DealEditor extends StatefulWidget {
  const DealEditor({super.key, this.deal});
  final Deal? deal;

  @override
  State<DealEditor> createState() => _DealEditorState();
}

class _DealEditorState extends State<DealEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController items;
  late final TextEditingController original;
  late final TextEditingController price;
  late bool active;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.deal?.name ?? '');
    items = TextEditingController(text: widget.deal?.itemNames.join(', ') ?? '');
    original = TextEditingController(text: widget.deal?.originalPrice.toString() ?? '');
    price = TextEditingController(text: widget.deal?.dealPrice.toString() ?? '');
    active = widget.deal?.active ?? true;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.deal == null ? 'Create deal' : 'Edit deal'),
        content: SizedBox(
          width: 500,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: name, validator: (value) => Validators.requiredText(value, 'Deal name'), decoration: const InputDecoration(labelText: 'Deal name')),
                const SizedBox(height: 10),
                TextFormField(controller: items, validator: (value) => Validators.requiredText(value, 'Included items'), decoration: const InputDecoration(labelText: 'Items, separated by commas')),
                const SizedBox(height: 10),
                TextFormField(controller: original, keyboardType: TextInputType.number, validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a valid price' : null, decoration: const InputDecoration(labelText: 'Original price')),
                const SizedBox(height: 10),
                TextFormField(controller: price, keyboardType: TextInputType.number, validator: (value) => int.tryParse(value ?? '') == null ? 'Enter a valid price' : null, decoration: const InputDecoration(labelText: 'Deal price')),
                SwitchListTile(value: active, onChanged: (value) => setState(() => active = value), title: const Text('Active')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if (!_form.currentState!.validate()) return;
            final id = widget.deal?.id ?? '${name.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch}';
            await context.read<AppProvider>().firestore.saveDeal(Deal(id: id, name: name.text.trim(), itemNames: items.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(), originalPrice: int.parse(original.text), dealPrice: int.parse(price.text), active: active));
            if (context.mounted) Navigator.pop(context);
          }, child: const Text('Save')),
        ],
      );
}

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<List<AppUser>>(
          stream: context.read<AppProvider>().firestore.staff(),
          builder: (context, snapshot) {
            final users = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (users.isEmpty) return const EmptyState(icon: Icons.groups_rounded, title: 'No staff accounts', message: 'Create manager and counter accounts with the rights they need.');
            return ListView(
              padding: const EdgeInsets.all(12),
              children: users
                  .map((user) => Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase())),
                          title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${user.role.name.toUpperCase()} • ${user.phone}\n${user.rights.entries.where((right) => right.value).map((right) => right.key).join(', ')}'),
                          isThreeLine: true,
                          trailing: IconButton(onPressed: () => context.read<AppProvider>().firestore.deleteStaff(user.id), icon: const Icon(Icons.delete_outline, color: MashColors.primary)),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => showDialog(context: context, builder: (_) => const StaffEditor()), icon: const Icon(Icons.person_add_rounded), label: const Text('Create staff')),
      );
}

class StaffEditor extends StatefulWidget {
  const StaffEditor({super.key});

  @override
  State<StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<StaffEditor> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  UserRole role = UserRole.manager;
  final rights = {'viewOrders': true, 'updateOrderStatus': true, 'manageMenu': false, 'manageDeals': false, 'viewReports': false};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create staff account'),
        content: SizedBox(
          width: 500,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(controller: name, validator: (value) => Validators.requiredText(value, 'Name'), decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 10),
                  TextFormField(controller: phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
                  const SizedBox(height: 10),
                  TextFormField(controller: password, obscureText: true, validator: Validators.password, decoration: const InputDecoration(labelText: 'Temporary password')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<UserRole>(
                    value: role,
                    items: const [DropdownMenuItem(value: UserRole.manager, child: Text('Manager')), DropdownMenuItem(value: UserRole.counter, child: Text('Counter'))],
                    onChanged: (value) => setState(() {
                      role = value!;
                      if (role == UserRole.counter) {
                        rights['viewOrders'] = true;
                        rights['updateOrderStatus'] = true;
                      }
                    }),
                    decoration: const InputDecoration(labelText: 'Role'),
                  ),
                  ...rights.keys.map((right) {
                    final locked = role == UserRole.counter && (right == 'viewOrders' || right == 'updateOrderStatus');
                    return CheckboxListTile(
                      value: rights[right],
                      onChanged: locked ? null : (value) => setState(() => rights[right] = value ?? false),
                      title: Text(_rightLabel(right)),
                      subtitle: locked ? const Text('Required for counter accounts') : null,
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final app = context.read<AppProvider>();
              final firebaseUser = await app.auth.createStaffAccount(phone.text, password.text);
              await app.firestore.saveUser(AppUser(id: firebaseUser.uid, name: name.text.trim(), phone: phone.text.trim(), address: 'Mashbash restaurant', role: role, rights: Map.from(rights)));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      );
}

String _rightLabel(String right) => switch (right) {
      'viewOrders' => 'View Orders',
      'updateOrderStatus' => 'Update Order Status',
      'manageMenu' => 'Manage Menu',
      'manageDeals' => 'Manage Deals',
      'viewReports' => 'View Reports',
      _ => right,
    };

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String period = 'Today';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final allOrders = context.watch<AppProvider>().orders;
    final orders = allOrders.where((order) {
      if (period == 'Today') return order.createdAt.year == now.year && order.createdAt.month == now.month && order.createdAt.day == now.day;
      if (period == 'This Week') return order.createdAt.isAfter(now.subtract(const Duration(days: 7)));
      return order.createdAt.isAfter(DateTime(now.year, now.month, 1));
    }).toList();
    final revenue = orders.where((order) => order.status == OrderStatus.delivered).fold<int>(0, (sum, order) => sum + order.total);
    final counts = <String, int>{};
    for (final order in orders) {
      for (final item in order.items) {
        counts[item['name'] as String] = (counts[item['name'] as String] ?? 0) + (item['quantity'] as num).round();
      }
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final summary = 'Mashbash $period Report\nRevenue: ${money(revenue)}\nOrders: ${orders.length}\nTop items: ${top.take(5).map((item) => '${item.key} (${item.value})').join(', ')}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'Today', label: Text('Today')), ButtonSegment(value: 'This Week', label: Text('Week')), ButtonSegment(value: 'This Month', label: Text('Month'))], selected: {period}, onSelectionChanged: (value) => setState(() => period = value.first)),
        const SizedBox(height: 16),
        Row(children: [Expanded(child: _MetricCard(label: 'Revenue', value: money(revenue), icon: Icons.payments_rounded)), const SizedBox(width: 12), Expanded(child: _MetricCard(label: 'Orders', value: '${orders.length}', icon: Icons.receipt_long_rounded))]),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Top selling items', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 8),
              if (top.isEmpty) const Text('No sales recorded for this period.') else ...top.take(5).map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item.key), trailing: Text('${item.value}', style: const TextStyle(fontWeight: FontWeight.w900)))),
            ]),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: summary));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report summary copied')));
          },
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Export summary'),
        ),
      ],
    );
  }
}
