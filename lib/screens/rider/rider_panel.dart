import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_models.dart';
import '../../providers/app_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/mash_widgets.dart';

class RiderPanel extends StatefulWidget {
  const RiderPanel({super.key});

  @override
  State<RiderPanel> createState() => _RiderPanelState();
}

class _RiderPanelState extends State<RiderPanel> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final user = app.user!;
    final active = app.orders.where((order) => order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled).toList();
    final history = app.orders.where((order) => order.status == OrderStatus.delivered || order.status == OrderStatus.cancelled).toList();
    return Scaffold(
      appBar: AppBar(
        title: const MashLogo(compact: true),
        actions: [IconButton(onPressed: app.logout, icon: const Icon(Icons.logout_rounded))],
      ),
      body: IndexedStack(
        index: index,
        children: [
          _RiderOrders(orders: active, user: user),
          _RiderOrders(orders: history, user: user, history: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.delivery_dining_rounded), label: 'Deliveries'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
        ],
      ),
    );
  }
}

class _RiderOrders extends StatelessWidget {
  const _RiderOrders({required this.orders, required this.user, this.history = false});
  final List<MashOrder> orders;
  final AppUser user;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ErrorBanner(),
        if (!history)
          MashPanel(
            color: user.available ? const Color(0xFFE2F5E9) : const Color(0xFFFFECE8),
            child: Row(children: [
              Icon(user.available ? Icons.check_circle_rounded : Icons.pause_circle_rounded, color: user.available ? MashColors.success : MashColors.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(user.available ? 'Available for deliveries' : 'Not accepting new deliveries', style: const TextStyle(fontWeight: FontWeight.w800))),
              Switch(value: user.available, onChanged: app.busy ? null : app.setRiderAvailability),
            ]),
          ),
        const SizedBox(height: 16),
        SectionHeading(history ? 'Delivery history' : 'Assigned deliveries'),
        const SizedBox(height: 10),
        if (orders.isEmpty)
          EmptyState(
            icon: history ? Icons.history_rounded : Icons.delivery_dining_rounded,
            title: history ? 'No delivery history' : 'No assigned deliveries',
            message: history ? 'Completed deliveries will appear here.' : 'New assigned orders will appear automatically.',
          )
        else
          ...orders.map((order) => _RiderOrderCard(order: order)),
      ],
    );
  }
}

class _RiderOrderCard extends StatelessWidget {
  const _RiderOrderCard({required this.order});
  final MashOrder order;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final next = switch (order.status) {
      OrderStatus.assignedToRider => OrderStatus.outForDelivery,
      OrderStatus.outForDelivery => OrderStatus.delivered,
      _ => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(order.customerName, style: Theme.of(context).textTheme.titleLarge)), OrderStatusChip(status: order.status)]),
          const SizedBox(height: 8),
          Text(order.items.map((item) => '${item['quantity']} x ${item['name']}').join(', ')),
          const Divider(height: 24),
          _Detail(Icons.phone_rounded, order.phone),
          _Detail(Icons.location_on_rounded, order.address),
          _Detail(Icons.payments_rounded, '${order.paymentMethod} - ${money(order.total)}'),
          if (next != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: app.busyOrders.contains(order.id) ? null : () => app.updateOrderStatus(order.id, next),
              icon: app.busyOrders.contains(order.id)
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(next == OrderStatus.delivered ? Icons.check_circle_rounded : Icons.delivery_dining_rounded),
              label: Text(next == OrderStatus.delivered ? 'Mark Delivered' : 'Picked up - Start delivery'),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 18, color: MashColors.primary), const SizedBox(width: 8), Expanded(child: Text(text))]),
      );
}
