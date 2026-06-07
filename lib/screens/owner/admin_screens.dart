import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/app_models.dart';
import '../../providers/app_provider.dart';
import '../../services/storage_service.dart';
import '../../utils/app_theme.dart';
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
      const _Destination('Home', Icons.dashboard_rounded, StaffDashboard()),
      if (user.can('viewOrders')) const _Destination('Orders', Icons.receipt_long_rounded, StaffOrdersScreen()),
      if (user.can('manageMenu')) const _Destination('Menu', Icons.restaurant_menu_rounded, MenuManagementScreen()),
      if (user.can('manageDeals')) const _Destination('Deals', Icons.local_offer_rounded, DealsManagementScreen()),
      if (user.can('manageSlides')) const _Destination('Slides', Icons.view_carousel_rounded, SlidesManagementScreen()),
      if (widget.role == UserRole.owner) const _Destination('Team', Icons.groups_rounded, UserManagementScreen()),
      if (user.can('viewReports')) const _Destination('Reports', Icons.bar_chart_rounded, ReportsScreen()),
      if (widget.role == UserRole.owner) const _Destination('Settings', Icons.settings_rounded, OwnerSettingsScreen()),
    ];
    if (index >= destinations.length) index = 0;
    return Scaffold(
      appBar: AppBar(
        title: const MashLogo(compact: true, onDark: true),
        actions: [IconButton(onPressed: context.read<AppProvider>().logout, icon: const Icon(Icons.logout_rounded), tooltip: 'Sign out')],
      ),
      body: Column(children: [const ErrorBanner(), Expanded(child: destinations[index].screen)]),
      bottomNavigationBar: _StaffBottomNav(destinations: destinations, selected: index, onSelected: (value) => setState(() => index = value)),
    );
  }
}

class _StaffBottomNav extends StatelessWidget {
  const _StaffBottomNav({required this.destinations, required this.selected, required this.onSelected});
  final List<_Destination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          height: 66,
          color: Colors.white,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: destinations.length,
            itemBuilder: (context, index) {
              final item = destinations[index];
              final active = index == selected;
              return SizedBox(
                width: 72,
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(item.icon, color: active ? MashColors.primary : Colors.black54),
                      const SizedBox(height: 3),
                      Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.w900 : FontWeight.w600, color: active ? MashColors.primary : Colors.black54)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class _Destination {
  const _Destination(this.label, this.icon, this.screen);
  final String label;
  final IconData icon;
  final Widget screen;
}

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  String period = 'This Week';
  DateTimeRange? custom;

  @override
  Widget build(BuildContext context) {
    final allOrders = context.watch<AppProvider>().orders;
    final now = DateTime.now();
    final range = _periodRange(period, custom);
    final orders = allOrders.where((order) => !order.createdAt.isBefore(range.start) && order.createdAt.isBefore(range.end)).toList();
    final sales = orders.where((order) => order.status == OrderStatus.delivered).fold<int>(0, (sum, order) => sum + order.total);
    final active = orders.where((order) => order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled).length;
    final start = DateTime(now.year, now.month, now.day);
    final bars = List.generate(7, (index) {
      final day = start.subtract(Duration(days: 6 - index));
      final total = allOrders.where((order) => order.status == OrderStatus.delivered && _sameDay(order.createdAt, day)).fold<int>(0, (sum, order) => sum + order.total);
      return BarChartGroupData(x: index, barRods: [BarChartRodData(toY: total.toDouble(), color: MashColors.primary, width: 15, borderRadius: BorderRadius.circular(6))]);
    });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeading('Restaurant overview'),
        const SizedBox(height: 14),
        _PeriodField(
          value: period,
          onChanged: (value, range) => setState(() {
            period = value;
            custom = range;
          }),
        ),
        const SizedBox(height: 14),
        _MetricGrid(metrics: [
          _Metric('$period sales', money(sales), Icons.payments_rounded),
          _Metric('$period orders', '${orders.length}', Icons.receipt_long_rounded),
          _Metric('Active orders', '$active', Icons.delivery_dining_rounded),
          _Metric('Completed', '${orders.where((order) => order.status == OrderStatus.delivered).length}', Icons.check_circle_rounded),
        ]),
        const SizedBox(height: 16),
        MashPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Revenue · Last 7 days', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 18),
            SizedBox(height: 210, child: BarChart(BarChartData(barGroups: bars, borderData: FlBorderData(show: false), gridData: const FlGridData(show: false), titlesData: const FlTitlesData(topTitles: AxisTitles(), rightTitles: AxisTitles())))),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionHeading('Recent orders'),
        ...allOrders.take(5).map((order) => Card(child: ListTile(title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${order.items.length} items · ${money(order.total)}'), trailing: OrderStatusChip(status: order.status)))),
        if (allOrders.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', message: 'Incoming customer orders will appear here in real time.'),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: MediaQuery.sizeOf(context).width > 760 ? 4 : 2,
        childAspectRatio: MediaQuery.textScalerOf(context).scale(1) > 1.1 ? 1.05 : 1.25,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: metrics
            .map((metric) => MashPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(metric.icon, color: MashColors.primary),
                    const SizedBox(height: 7),
                    Text(metric.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                  ]),
                ))
            .toList(),
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
    final app = context.watch<AppProvider>();
    final user = app.user!;
    final orders = app.orders.where((order) => filter == null || order.status == filter).toList();
    return Column(children: [
      SizedBox(
        height: 58,
        child: ListView(
          padding: const EdgeInsets.all(8),
          scrollDirection: Axis.horizontal,
          children: [
            ChoiceChip(label: const Text('All'), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
            const SizedBox(width: 6),
            ...OrderStatus.values.map((status) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(statusLabel(status)), selected: filter == status, onSelected: (_) => setState(() => filter = status)))),
          ],
        ),
      ),
      Expanded(
        child: orders.isEmpty
            ? const EmptyState(icon: Icons.inbox_rounded, title: 'No matching orders', message: 'Orders matching this filter will appear automatically.')
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                itemBuilder: (_, index) => _OrderOperationsCard(order: orders[index], canUpdate: user.can('updateOrderStatus'), canAssign: user.can('assignRiders')),
              ),
      ),
    ]);
  }
}

class _OrderOperationsCard extends StatelessWidget {
  const _OrderOperationsCard({required this.order, required this.canUpdate, required this.canAssign});
  final MashOrder order;
  final bool canUpdate;
  final bool canAssign;

  @override
  Widget build(BuildContext context) {
    final next = _nextStaffStatus(order.status);
    final busy = context.watch<AppProvider>().busyOrders.contains(order.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('${order.customerName} · #${order.id.substring(0, 6).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))), OrderStatusChip(status: order.status)]),
          const SizedBox(height: 5),
          Text(order.items.map((item) => '${item['quantity']}× ${item['name']}').join(', ')),
          const SizedBox(height: 8),
          Text(order.address),
          Text('${order.phone} · ${order.paymentMethod} · ${money(order.total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (order.assignedRiderName.isNotEmpty) Text('Rider: ${order.assignedRiderName}', style: const TextStyle(color: MashColors.success, fontWeight: FontWeight.w700)),
          if (!busy && order.status == OrderStatus.readyForDelivery && canAssign) ...[
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => showDialog(context: context, builder: (_) => _RiderAssignmentDialog(order: order)), icon: const Icon(Icons.delivery_dining_rounded), label: const Text('Assign available rider')),
          ] else if (!busy && next != null && canUpdate) ...[
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => context.read<AppProvider>().updateOrderStatus(order.id, next), icon: const Icon(Icons.arrow_forward_rounded), label: Text('Mark ${statusLabel(next)}')),
          ],
          if (!busy && canUpdate && order.status != OrderStatus.cancelled && order.status != OrderStatus.delivered)
            TextButton.icon(onPressed: () => context.read<AppProvider>().updateOrderStatus(order.id, OrderStatus.cancelled), icon: const Icon(Icons.cancel_outlined), label: const Text('Cancel order')),
          if (busy) const Padding(padding: EdgeInsets.all(10), child: LinearProgressIndicator()),
        ]),
      ),
    );
  }
}

class _RiderAssignmentDialog extends StatelessWidget {
  const _RiderAssignmentDialog({required this.order});
  final MashOrder order;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Assign available rider'),
        content: SizedBox(
          width: 440,
          child: StreamBuilder<List<AppUser>>(
            stream: context.read<AppProvider>().data.availableRiders(),
            builder: (context, snapshot) {
              final riders = snapshot.data ?? const [];
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (riders.isEmpty) return const Text('No riders are available. Ask a rider to switch on availability.');
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: riders
                    .map((rider) => ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.delivery_dining_rounded)),
                          title: Text(rider.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(rider.phone),
                          onTap: () async {
                            final assigned = await context.read<AppProvider>().assignRider(order.id, rider.id);
                            if (assigned && context.mounted) Navigator.pop(context);
                          },
                        ))
                    .toList(),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
}

class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  bool categories = false;
  bool showArchived = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final categoryItems = app.categories.where((item) => item.archived == showArchived);
    final productItems = app.products.where((item) => item.archived == showArchived);
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Products'), icon: Icon(Icons.lunch_dining_rounded)), ButtonSegment(value: true, label: Text('Categories'), icon: Icon(Icons.category_rounded))], selected: {categories}, onSelectionChanged: (value) => setState(() => categories = value.first)),
        ),
        SwitchListTile(
          dense: true,
          value: showArchived,
          onChanged: (value) => setState(() => showArchived = value),
          title: const Text('Show archived items'),
          secondary: const Icon(Icons.archive_outlined),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: categories
                ? categoryItems.map((category) => _CategoryTile(category: category)).toList()
                : productItems.map((product) => _ProductTile(product: product)).toList(),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(context: context, builder: (_) => categories ? const CategoryEditor() : const ProductEditor()),
        icon: const Icon(Icons.add),
        label: Text(categories ? 'Add category' : 'Add product'),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final MenuCategory category;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundImage: category.imageUrl.isEmpty ? null : NetworkImage(category.imageUrl), child: category.imageUrl.isEmpty ? const Icon(Icons.category_rounded) : null),
          title: Row(children: [Expanded(child: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w900))), _StateBadge(label: category.archived ? 'Archived' : category.active ? 'Active' : 'Disabled')]),
          subtitle: Text('Sort ${category.sortOrder} · ${category.active ? 'Active' : 'Hidden'}'),
          trailing: _MenuActions(
            active: category.active,
            archived: category.archived,
            onEdit: () => showDialog(context: context, builder: (_) => CategoryEditor(category: category)),
            onToggle: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.setCategoryActive(category.id, !category.active), success: category.active ? 'Category hidden from customers.' : 'Category visible to customers.'),
            onArchive: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.archiveCategory(category.id, !category.archived), success: category.archived ? 'Category restored.' : 'Category archived without changing order history.'),
          ),
        ),
      );
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundImage: product.imageUrl.isEmpty ? null : NetworkImage(product.imageUrl), child: product.imageUrl.isEmpty ? const Icon(Icons.lunch_dining_rounded) : null),
          title: Row(children: [Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900))), _StateBadge(label: product.archived ? 'Archived' : product.available ? 'Active' : 'Disabled')]),
          subtitle: Text('${product.category} · ${money(product.price)} · ${product.available ? 'Available' : 'Unavailable'}'),
          trailing: _MenuActions(
            active: product.available,
            archived: product.archived,
            onEdit: () => showDialog(context: context, builder: (_) => ProductEditor(product: product)),
            onToggle: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.setProductAvailable(product.id, !product.available), success: product.available ? 'Product hidden from customers.' : 'Product available to customers.'),
            onArchive: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.archiveProduct(product.id, !product.archived), success: product.archived ? 'Product restored.' : 'Product archived without changing order history.'),
          ),
        ),
      );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onEdit, required this.onDelete});
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        onSelected: (action) => action == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
      );
}

class _MenuActions extends StatelessWidget {
  const _MenuActions({required this.active, required this.archived, required this.onEdit, required this.onToggle, required this.onArchive});
  final bool active;
  final bool archived;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        onSelected: (action) {
          if (action == 'edit') onEdit();
          if (action == 'toggle') onToggle();
          if (action == 'archive') onArchive();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (!archived) PopupMenuItem(value: 'toggle', child: Text(active ? 'Disable / Hide from customer' : 'Enable / Show to customer')),
          PopupMenuItem(value: 'archive', child: Text(archived ? 'Restore' : 'Archive / Delete')),
        ],
      );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: label == 'Active' ? const Color(0xFFE2F5E9) : const Color(0xFFFFE3E3), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(fontSize: 10, color: MashColors.primary, fontWeight: FontWeight.w900)),
      );
}

class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, this.category});
  final MenuCategory? category;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.category?.name ?? '');
  late final image = TextEditingController(text: widget.category?.imageUrl ?? '');
  late final sort = TextEditingController(text: '${widget.category?.sortOrder ?? 0}');
  late bool active = widget.category?.active ?? true;
  File? pickedImage;

  @override
  Widget build(BuildContext context) => _EditorDialog(
        title: widget.category == null ? 'Add category' : 'Edit category',
        form: form,
        fields: [
          TextFormField(controller: name, validator: (value) => Validators.requiredText(value, 'Category name'), decoration: const InputDecoration(labelText: 'Category name')),
          _ImageUploadField(controller: image, pickedImage: pickedImage, onPick: (file) => setState(() => pickedImage = file)),
          TextFormField(controller: sort, keyboardType: TextInputType.number, validator: _number, decoration: const InputDecoration(labelText: 'Sort order', helperText: 'Lower numbers appear first on customer home.')),
          SwitchListTile(value: active, onChanged: (value) => setState(() => active = value), title: const Text('Visible to customers')),
        ],
        onSave: () async {
          if (!form.currentState!.validate()) return;
          final id = widget.category?.id ?? '';
          var imageUrl = image.text.trim();
          final app = context.read<AppProvider>();
          final saved = await app.run(() async {
            if (pickedImage != null) imageUrl = await StorageService().uploadImage('categories', id.isEmpty ? _id(name.text) : id, pickedImage!);
            await app.data.saveCategory(MenuCategory(id: id, name: name.text.trim(), imageUrl: imageUrl, sortOrder: int.parse(sort.text), active: active, archivedAt: widget.category?.archivedAt));
          }, success: 'Category saved.');
          if (saved && context.mounted) Navigator.pop(context);
        },
      );
}

class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, this.product});
  final Product? product;

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.product?.name ?? '');
  late final description = TextEditingController(text: widget.product?.description ?? '');
  late final price = TextEditingController(text: '${widget.product?.price ?? ''}');
  late final image = TextEditingController(text: widget.product?.imageUrl ?? '');
  late final sort = TextEditingController(text: '${widget.product?.sortOrder ?? 0}');
  String? categoryId;
  late bool available = widget.product?.available ?? true;
  File? pickedImage;

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppProvider>().categories;
    categoryId ??= widget.product?.categoryId.isNotEmpty == true ? widget.product!.categoryId : (categories.isEmpty ? null : categories.first.id);
    return _EditorDialog(
      title: widget.product == null ? 'Add product' : 'Edit product',
      form: form,
      fields: [
        TextFormField(controller: name, validator: (value) => Validators.requiredText(value, 'Product name'), decoration: const InputDecoration(labelText: 'Product name')),
        DropdownButtonFormField<String>(value: categoryId, items: categories.map((category) => DropdownMenuItem(value: category.id, child: Text(category.name))).toList(), onChanged: (value) => setState(() => categoryId = value), decoration: const InputDecoration(labelText: 'Category')),
        TextFormField(controller: description, maxLines: 3, validator: (value) => Validators.requiredText(value, 'Description'), decoration: const InputDecoration(labelText: 'Description')),
        TextFormField(controller: price, keyboardType: TextInputType.number, validator: _number, decoration: const InputDecoration(labelText: 'Price')),
        _ImageUploadField(controller: image, pickedImage: pickedImage, onPick: (file) => setState(() => pickedImage = file)),
        TextFormField(controller: sort, keyboardType: TextInputType.number, validator: _number, decoration: const InputDecoration(labelText: 'Sort order')),
        SwitchListTile(value: available, onChanged: (value) => setState(() => available = value), title: const Text('Available')),
      ],
      onSave: () async {
        if (!form.currentState!.validate() || categoryId == null) return;
        final category = categories.firstWhere((item) => item.id == categoryId);
        final id = widget.product?.id ?? _id(name.text);
        var imageUrl = image.text.trim();
        final app = context.read<AppProvider>();
        final saved = await app.run(
              () async {
                if (pickedImage != null) imageUrl = await StorageService().uploadImage('products', id, pickedImage!);
                await app.data.saveProduct(Product(id: id, categoryId: category.id, name: name.text.trim(), category: category.name, description: description.text.trim(), price: int.parse(price.text), imageUrl: imageUrl, available: available, sortOrder: int.parse(sort.text), archivedAt: widget.product?.archivedAt));
              },
              success: 'Product saved.',
            );
        if (saved && context.mounted) Navigator.pop(context);
      },
    );
  }
}

class DealsManagementScreen extends StatefulWidget {
  const DealsManagementScreen({super.key});

  @override
  State<DealsManagementScreen> createState() => _DealsManagementScreenState();
}

class _DealsManagementScreenState extends State<DealsManagementScreen> {
  bool showArchived = false;

  @override
  Widget build(BuildContext context) {
    final deals = context.watch<AppProvider>().deals.where((deal) => deal.archived == showArchived).toList();
    return _CrudScaffold(
      empty: deals.isEmpty,
      emptyState: const EmptyState(icon: Icons.local_offer_outlined, title: 'No deals active', message: 'Create a value-packed Mashbash deal.'),
      children: [
        SwitchListTile(value: showArchived, onChanged: (value) => setState(() => showArchived = value), title: const Text('Show archived deals'), secondary: const Icon(Icons.archive_outlined)),
        ...deals
          .map((deal) => Card(
                child: ListTile(
                  title: Row(children: [Expanded(child: Text(deal.name, style: const TextStyle(fontWeight: FontWeight.w900))), _StateBadge(label: deal.archived ? 'Archived' : deal.active ? 'Active' : 'Disabled')]),
                  subtitle: Text('${deal.itemNames.join(' + ')}\n${money(deal.dealPrice)} · ${deal.active ? 'Active' : 'Inactive'}'),
                  isThreeLine: true,
                  trailing: _MenuActions(
                    active: deal.active,
                    archived: deal.archived,
                    onEdit: () => showDialog(context: context, builder: (_) => DealEditor(deal: deal)),
                    onToggle: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.setDealActive(deal.id, !deal.active), success: deal.active ? 'Deal hidden from customers.' : 'Deal visible to customers.'),
                    onArchive: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.archiveDeal(deal.id, !deal.archived), success: deal.archived ? 'Deal restored.' : 'Deal archived without changing order history.'),
                  ),
                ),
              ))
      ],
      buttonLabel: 'Create deal',
      onAdd: () => showDialog(context: context, builder: (_) => const DealEditor()),
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
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.deal?.name ?? '');
  late final items = TextEditingController(text: widget.deal?.itemNames.join(', ') ?? '');
  late final original = TextEditingController(text: '${widget.deal?.originalPrice ?? ''}');
  late final price = TextEditingController(text: '${widget.deal?.dealPrice ?? ''}');
  late final image = TextEditingController(text: widget.deal?.imageUrl ?? '');
  late bool active = widget.deal?.active ?? true;
  File? pickedImage;

  @override
  Widget build(BuildContext context) => _EditorDialog(
        title: widget.deal == null ? 'Create deal' : 'Edit deal',
        form: form,
        fields: [
          TextFormField(controller: name, validator: (value) => Validators.requiredText(value, 'Deal name'), decoration: const InputDecoration(labelText: 'Deal name')),
          TextFormField(controller: items, validator: (value) => Validators.requiredText(value, 'Included items'), decoration: const InputDecoration(labelText: 'Items, separated by commas')),
          TextFormField(controller: original, keyboardType: TextInputType.number, validator: _number, decoration: const InputDecoration(labelText: 'Original price')),
          TextFormField(controller: price, keyboardType: TextInputType.number, validator: _number, decoration: const InputDecoration(labelText: 'Deal price')),
          _ImageUploadField(controller: image, pickedImage: pickedImage, onPick: (file) => setState(() => pickedImage = file)),
          SwitchListTile(value: active, onChanged: (value) => setState(() => active = value), title: const Text('Active')),
        ],
        onSave: () async {
          if (!form.currentState!.validate()) return;
          final id = widget.deal?.id ?? _id(name.text);
          var imageUrl = image.text.trim();
          final app = context.read<AppProvider>();
          final saved = await app.run(
                () async {
                  if (pickedImage != null) imageUrl = await StorageService().uploadImage('deals', id, pickedImage!);
                  await app.data.saveDeal(Deal(id: id, name: name.text.trim(), itemNames: items.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(), originalPrice: int.parse(original.text), dealPrice: int.parse(price.text), imageUrl: imageUrl, active: active, archivedAt: widget.deal?.archivedAt));
                },
                success: 'Deal saved.',
              );
          if (saved && context.mounted) Navigator.pop(context);
        },
      );
}

class SlidesManagementScreen extends StatelessWidget {
  const SlidesManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final slides = context.watch<AppProvider>().slides;
    return _CrudScaffold(
      empty: slides.isEmpty,
      emptyState: const EmptyState(icon: Icons.view_carousel_outlined, title: 'No home slides', message: 'Create the first customer home promotion.'),
      children: slides
          .map((slide) => Card(
                child: ListTile(
                  title: Text(slide.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text('${slide.subtitle}\nSort ${slide.sortOrder} · ${slide.active ? 'Active' : 'Hidden'}'),
                  isThreeLine: true,
                  trailing: _Actions(onEdit: () => showDialog(context: context, builder: (_) => SlideEditor(slide: slide)), onDelete: () => context.read<AppProvider>().run(() => context.read<AppProvider>().data.deleteSlide(slide.id), success: 'Slide deleted.')),
                ),
              ))
          .toList(),
      buttonLabel: 'Create slide',
      onAdd: () => showDialog(context: context, builder: (_) => const SlideEditor()),
    );
  }
}

class SlideEditor extends StatefulWidget {
  const SlideEditor({super.key, this.slide});
  final HomeSlide? slide;

  @override
  State<SlideEditor> createState() => _SlideEditorState();
}

class _SlideEditorState extends State<SlideEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.slide?.title ?? '');
  late final subtitle = TextEditingController(text: widget.slide?.subtitle ?? '');
  late final image = TextEditingController(text: widget.slide?.imageUrl ?? '');
  late final linkId = TextEditingController(text: widget.slide?.linkId ?? '');
  late final sort = TextEditingController(text: '${widget.slide?.sortOrder ?? 0}');
  late String linkType = widget.slide?.linkType ?? 'none';
  late bool active = widget.slide?.active ?? true;
  File? pickedImage;

  @override
  Widget build(BuildContext context) => _EditorDialog(
        title: widget.slide == null ? 'Create slide' : 'Edit slide',
        form: form,
        fields: [
          TextFormField(controller: title, validator: (value) => Validators.requiredText(value, 'Title'), decoration: const InputDecoration(labelText: 'Title')),
          TextFormField(controller: subtitle, decoration: const InputDecoration(labelText: 'Subtitle')),
          _ImageUploadField(controller: image, pickedImage: pickedImage, onPick: (file) => setState(() => pickedImage = file), imageRequired: true),
          DropdownButtonFormField<String>(value: linkType, items: const ['none', 'deal', 'product', 'category'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(), onChanged: (value) => setState(() => linkType = value!), decoration: const InputDecoration(labelText: 'Link type')),
          TextFormField(controller: linkId, decoration: const InputDecoration(labelText: 'Link ID')),
          TextFormField(controller: sort, keyboardType: TextInputType.number, validator: _number, decoration: const InputDecoration(labelText: 'Sort order')),
          SwitchListTile(value: active, onChanged: (value) => setState(() => active = value), title: const Text('Active')),
        ],
        onSave: () async {
          if (!form.currentState!.validate()) return;
          final id = widget.slide?.id ?? _id(title.text);
          var imageUrl = image.text.trim();
          final app = context.read<AppProvider>();
          final saved = await app.run(
                () async {
                  if (pickedImage != null) imageUrl = await StorageService().uploadImage('slides', id, pickedImage!);
                  await app.data.saveSlide(HomeSlide(id: id, title: title.text.trim(), subtitle: subtitle.text.trim(), imageUrl: imageUrl, linkType: linkType, linkId: linkId.text.trim(), sortOrder: int.parse(sort.text), active: active));
                },
                success: 'Home slide saved.',
              );
          if (saved && context.mounted) Navigator.pop(context);
        },
      );
}

class _CrudScaffold extends StatelessWidget {
  const _CrudScaffold({required this.empty, required this.emptyState, required this.children, required this.buttonLabel, required this.onAdd});
  final bool empty;
  final Widget emptyState;
  final List<Widget> children;
  final String buttonLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: empty ? emptyState : ListView(padding: const EdgeInsets.all(12), children: children),
        floatingActionButton: FloatingActionButton.extended(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(buttonLabel)),
      );
}

class _EditorDialog extends StatelessWidget {
  const _EditorDialog({required this.title, required this.form, required this.fields, required this.onSave});
  final String title;
  final GlobalKey<FormState> form;
  final List<Widget> fields;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: fields.expand((field) => [field, const SizedBox(height: 10)]).toList()),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: onSave, child: const Text('Save'))],
      );
}

class _ImageUploadField extends StatelessWidget {
  const _ImageUploadField({required this.controller, required this.pickedImage, required this.onPick, this.imageRequired = false});
  final TextEditingController controller;
  final File? pickedImage;
  final ValueChanged<File> onPick;
  final bool imageRequired;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) => Container(
          height: 130,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: const Color(0xFFFFE0B2), borderRadius: BorderRadius.circular(16)),
          child: pickedImage != null
              ? Image.file(pickedImage!, fit: BoxFit.cover)
              : value.text.trim().isNotEmpty
                  ? CachedNetworkImage(imageUrl: value.text.trim(), fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: MashColors.primary))
                  : const Center(child: Icon(Icons.image_outlined, size: 44, color: MashColors.primary)),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () async {
          final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
          if (image != null) onPick(File(image.path));
        },
        icon: const Icon(Icons.upload_rounded),
        label: Text(pickedImage == null ? 'Upload image' : 'Choose another image'),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        validator: imageRequired ? (value) => (value ?? '').trim().isEmpty && pickedImage == null ? 'Upload an image or enter an image URL' : null : null,
        decoration: const InputDecoration(labelText: 'Image URL (optional fallback)', prefixIcon: Icon(Icons.link_rounded)),
      ),
    ]);
  }
}

class OwnerSettingsScreen extends StatefulWidget {
  const OwnerSettingsScreen({super.key});

  @override
  State<OwnerSettingsScreen> createState() => _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends State<OwnerSettingsScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController deliveryFee;
  late final TextEditingController pendingMinutes;
  final notificationTitle = TextEditingController();
  final notificationBody = TextEditingController();
  late bool newOrderNotifications;
  late bool orderStatusNotifications;
  late bool dailySalesSummary;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppProvider>().settings;
    deliveryFee = TextEditingController(text: '${settings.deliveryFee}');
    pendingMinutes = TextEditingController(text: '${settings.pendingAlertMinutes}');
    newOrderNotifications = settings.newOrderNotifications;
    orderStatusNotifications = settings.orderStatusNotifications;
    dailySalesSummary = settings.dailySalesSummary;
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeading('Restaurant settings'),
          const SizedBox(height: 14),
          MashPanel(
            child: Form(
              key: form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Delivery charge', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 5),
                const Text('This amount is added to every non-empty customer order. The safe default is Rs. 120.'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: deliveryFee,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final amount = int.tryParse(value ?? '');
                    if (amount == null) return 'Enter a whole number';
                    if (amount < 0 || amount > 10000) return 'Enter an amount from 0 to 10,000';
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'Delivery charge', prefixText: 'Rs. '),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: newOrderNotifications,
                  onChanged: (value) => setState(() => newOrderNotifications = value),
                  title: const Text('New order notifications'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: orderStatusNotifications,
                  onChanged: (value) => setState(() => orderStatusNotifications = value),
                  title: const Text('Order status notifications'),
                  subtitle: const Text('Notify customers when their order changes.'),
                ),
                TextFormField(
                  controller: pendingMinutes,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final minutes = int.tryParse(value ?? '');
                    if (minutes == null || minutes < 1 || minutes > 180) return 'Enter minutes from 1 to 180';
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'Pending order alert minutes'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: dailySalesSummary,
                  onChanged: (value) => setState(() => dailySalesSummary = value),
                  title: const Text('Daily sales summary'),
                  subtitle: const Text('Ready for a scheduled Edge Function or Supabase Cron job.'),
                ),
                const SizedBox(height: 14),
                AsyncButton(
                  label: 'Save restaurant settings',
                  icon: Icons.save_rounded,
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    context.read<AppProvider>().saveSettings(RestaurantSettings(
                          deliveryFee: int.parse(deliveryFee.text),
                          newOrderNotifications: newOrderNotifications,
                          orderStatusNotifications: orderStatusNotifications,
                          pendingAlertMinutes: int.parse(pendingMinutes.text),
                          dailySalesSummary: dailySalesSummary,
                        ));
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          MashPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Test this device', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 5),
              const Text('Checks this signed-in device token, the Supabase Edge Function, and FCM delivery.'),
              const SizedBox(height: 12),
              AsyncButton(
                label: 'Send test notification to me',
                icon: Icons.notifications_active_rounded,
                onPressed: context.read<AppProvider>().sendTestNotification,
              ),
            ]),
          ),
          const SizedBox(height: 18),
          MashPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Notify all customers', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 10),
              TextField(controller: notificationTitle, decoration: const InputDecoration(labelText: 'Notification title')),
              const SizedBox(height: 10),
              TextField(controller: notificationBody, maxLines: 3, decoration: const InputDecoration(labelText: 'Notification message')),
              const SizedBox(height: 12),
              AsyncButton(
                label: 'Send notification',
                icon: Icons.campaign_rounded,
                onPressed: () {
                  if (notificationTitle.text.trim().isEmpty || notificationBody.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a title and message.')));
                    return;
                  }
                  context.read<AppProvider>().sendCustomNotification(title: notificationTitle.text.trim(), body: notificationBody.text.trim());
                },
              ),
            ]),
          ),
        ],
      );
}

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<List<AppUser>>(
          stream: context.read<AppProvider>().data.staff(),
          builder: (context, snapshot) {
            final users = snapshot.data ?? const [];
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (users.isEmpty) return const EmptyState(icon: Icons.groups_rounded, title: 'No staff accounts', message: 'Create manager, counter, and rider accounts.');
            return ListView(
              padding: const EdgeInsets.all(12),
              children: users
                  .map((user) => Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(user.role == UserRole.rider ? Icons.delivery_dining_rounded : Icons.badge_rounded)),
                          title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text('${user.role.name.toUpperCase()} · ${user.phone}\n${user.active ? 'Active' : 'Disabled'}${user.role == UserRole.rider ? ' · ${user.available ? 'Available' : 'Unavailable'}' : ''}'),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                showDialog(context: context, builder: (_) => StaffEditor(user: user));
                              } else {
                                context.read<AppProvider>().run(() => context.read<AppProvider>().data.manageStaff(action: action, userId: user.id), success: action == 'delete' ? 'Staff account deleted.' : 'Staff account updated.');
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Edit account')),
                              PopupMenuItem(value: user.active ? 'disable' : 'enable', child: Text(user.active ? 'Disable account' : 'Enable account')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete account')),
                            ],
                          ),
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
  const StaffEditor({super.key, this.user});
  final AppUser? user;

  @override
  State<StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<StaffEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController phone;
  final password = TextEditingController();
  late UserRole role;
  final rights = {'viewOrders': true, 'updateOrderStatus': true, 'assignRiders': false, 'manageMenu': false, 'manageDeals': false, 'manageSlides': false, 'viewReports': false};

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.user?.name ?? '');
    phone = TextEditingController(text: widget.user?.phone ?? '');
    role = widget.user?.role ?? UserRole.manager;
    if (widget.user != null) rights.addAll(widget.user!.rights);
  }

  @override
  Widget build(BuildContext context) {
    final locked = role == UserRole.counter;
    return _EditorDialog(
      title: widget.user == null ? 'Create staff account' : 'Edit staff account',
      form: form,
      fields: [
        TextFormField(controller: name, validator: (value) => Validators.requiredText(value, 'Name'), decoration: const InputDecoration(labelText: 'Full name')),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, validator: Validators.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
        TextFormField(controller: password, obscureText: true, validator: (value) => widget.user != null && (value ?? '').isEmpty ? null : Validators.password(value), decoration: InputDecoration(labelText: widget.user == null ? 'Temporary password' : 'New password (optional)')),
        DropdownButtonFormField<UserRole>(
          value: role,
          items: const [DropdownMenuItem(value: UserRole.manager, child: Text('Manager')), DropdownMenuItem(value: UserRole.counter, child: Text('Counter')), DropdownMenuItem(value: UserRole.rider, child: Text('Rider'))],
          onChanged: (value) => setState(() {
            role = value!;
            if (role == UserRole.counter) {
              rights['viewOrders'] = true;
              rights['updateOrderStatus'] = true;
              rights['assignRiders'] = true;
            }
          }),
          decoration: const InputDecoration(labelText: 'Role'),
        ),
        if (role != UserRole.rider)
          ...rights.keys.map((right) {
            final requiredRight = locked && const ['viewOrders', 'updateOrderStatus', 'assignRiders'].contains(right);
            return CheckboxListTile(value: rights[right], onChanged: requiredRight ? null : (value) => setState(() => rights[right] = value ?? false), title: Text(_rightLabel(right)), subtitle: requiredRight ? const Text('Required for counter accounts') : null);
          }),
        if (role == UserRole.rider) const ListTile(leading: Icon(Icons.info_outline), title: Text('Riders only see deliveries assigned to them.')),
      ],
      onSave: () async {
        if (!form.currentState!.validate()) return;
        final app = context.read<AppProvider>();
        final saved = await app.run(
          () => widget.user == null
              ? app.auth.createStaffAccount(name: name.text.trim(), phone: phone.text.trim(), password: password.text, role: role, rights: Map.from(rights)).then((_) {})
              : app.auth.updateStaffAccount(id: widget.user!.id, name: name.text.trim(), phone: phone.text.trim(), password: password.text, role: role, rights: Map.from(rights)),
          success: widget.user == null ? 'Staff account created.' : 'Staff account updated.',
        );
        if (saved && context.mounted) Navigator.pop(context);
      },
    );
  }
}

String _rightLabel(String right) => switch (right) {
      'viewOrders' => 'View orders',
      'updateOrderStatus' => 'Update order status',
      'assignRiders' => 'Assign riders',
      'manageMenu' => 'Manage menu and categories',
      'manageDeals' => 'Manage deals',
      'manageSlides' => 'Manage home slides',
      'viewReports' => 'View reports',
      _ => right,
    };

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String period = 'Today';
  DateTimeRange? custom;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final range = _periodRange(period, custom);
    final orders = app.orders.where((order) => !order.createdAt.isBefore(range.start) && order.createdAt.isBefore(range.end)).toList();
    final delivered = orders.where((order) => order.status == OrderStatus.delivered).toList();
    final revenue = delivered.fold<int>(0, (sum, order) => sum + order.total);
    final counts = <String, int>{};
    final categorySales = <String, int>{};
    for (final order in delivered) {
      for (final item in order.items) {
        final name = item['name'] as String? ?? 'Item';
        final quantity = (item['quantity'] as num? ?? 0).round();
        final lineTotal = (item['line_total'] as num?)?.round() ?? (item['price'] as num? ?? 0).round() * quantity;
        counts[name] = (counts[name] ?? 0) + quantity;
        final category = item['category_name'] as String? ?? 'Deals / Other';
        categorySales[category] = (categorySales[category] ?? 0) + lineTotal;
      }
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final categories = categorySales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final pending = orders.where((order) => order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled).length;
    final summary = 'Mashbash $period report\nRevenue: ${money(revenue)}\nOrders: ${orders.length}\nCompleted: ${delivered.length}\nPending: $pending\nCancelled: ${orders.where((order) => order.status == OrderStatus.cancelled).length}\nTop items: ${top.take(5).map((item) => '${item.key} (${item.value})').join(', ')}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PeriodField(
          value: period,
          onChanged: (value, range) => setState(() {
            period = value;
            custom = range;
          }),
        ),
        const SizedBox(height: 16),
        _MetricGrid(metrics: [
          _Metric('Revenue', money(revenue), Icons.payments_rounded),
          _Metric('All orders', '${orders.length}', Icons.receipt_long_rounded),
          _Metric('Completed', '${delivered.length}', Icons.check_circle_rounded),
          _Metric('Pending', '$pending', Icons.timelapse_rounded),
          _Metric('Cancelled', '${orders.where((order) => order.status == OrderStatus.cancelled).length}', Icons.cancel_rounded),
        ]),
        const SizedBox(height: 16),
        MashPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Category sales', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            if (categories.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No completed sales in this period.')) else ...categories.map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item.key), trailing: Text(money(item.value), style: const TextStyle(fontWeight: FontWeight.w900)))),
          ]),
        ),
        const SizedBox(height: 16),
        MashPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Top selling items', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            if (top.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No completed sales in this period.')) else ...top.take(8).map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item.key), trailing: Text('${item.value}', style: const TextStyle(fontWeight: FontWeight.w900)))),
          ]),
        ),
        const SizedBox(height: 12),
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

OrderStatus? _nextStaffStatus(OrderStatus status) => switch (status) {
      OrderStatus.received => OrderStatus.accepted,
      OrderStatus.accepted => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.readyForDelivery,
      OrderStatus.readyForDelivery || OrderStatus.assignedToRider || OrderStatus.outForDelivery || OrderStatus.delivered || OrderStatus.cancelled => null,
    };

class _PeriodField extends StatelessWidget {
  const _PeriodField({required this.value, required this.onChanged});
  final String value;
  final void Function(String value, DateTimeRange? custom) onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        items: const ['Today', 'Yesterday', 'This Week', 'This Month', 'Last Month', 'Custom'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
        onChanged: (selected) async {
          if (selected == null) return;
          DateTimeRange? custom;
          if (selected == 'Custom') {
            final picked = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
            if (picked == null) return;
            custom = DateTimeRange(start: DateTime(picked.start.year, picked.start.month, picked.start.day), end: DateTime(picked.end.year, picked.end.month, picked.end.day).add(const Duration(days: 1)));
          }
          onChanged(selected, custom);
        },
        decoration: const InputDecoration(labelText: 'Period', prefixIcon: Icon(Icons.date_range_rounded)),
      );
}

DateTimeRange _periodRange(String period, DateTimeRange? custom) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (period) {
    'Yesterday' => DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today),
    'This Week' => DateTimeRange(start: today.subtract(Duration(days: now.weekday - 1)), end: today.add(const Duration(days: 1))),
    'This Month' => DateTimeRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month + 1)),
    'Last Month' => DateTimeRange(start: DateTime(now.year, now.month - 1), end: DateTime(now.year, now.month)),
    'Custom' => custom ?? DateTimeRange(start: today, end: today.add(const Duration(days: 1))),
    _ => DateTimeRange(start: today, end: today.add(const Duration(days: 1))),
  };
}

bool _sameDay(DateTime left, DateTime right) => left.year == right.year && left.month == right.month && left.day == right.day;
String _id(String value) => '${value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${DateTime.now().millisecondsSinceEpoch}';
String? _number(String? value) => int.tryParse(value ?? '') == null ? 'Enter a whole number' : null;
