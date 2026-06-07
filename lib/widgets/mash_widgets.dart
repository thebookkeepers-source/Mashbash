import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_models.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';

String money(num value) => 'Rs. ${value.round()}';

String statusLabel(OrderStatus status) => switch (status) {
      OrderStatus.received => 'Order Received',
      OrderStatus.accepted => 'Accepted',
      OrderStatus.preparing => 'Preparing',
      OrderStatus.readyForDelivery => 'Ready for Delivery',
      OrderStatus.assignedToRider => 'Assigned to Rider',
      OrderStatus.outForDelivery => 'Out for Delivery',
      OrderStatus.delivered => 'Completed',
      OrderStatus.cancelled => 'Cancelled',
    };

class MashLogo extends StatelessWidget {
  const MashLogo({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 42 : 62,
            height: compact ? 42 : 62,
            decoration: const BoxDecoration(color: MashColors.secondary, shape: BoxShape.circle),
            child: Icon(Icons.lunch_dining_rounded, color: MashColors.primary, size: compact ? 26 : 38),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MASHBASH', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: compact ? 20 : 30, color: compact ? Colors.white : MashColors.primary, letterSpacing: 1)),
              Text('Meet.Eat.Repeat', style: TextStyle(fontSize: compact ? 10 : 13, fontWeight: FontWeight.w600, color: MashColors.primary)),
            ],
          ),
        ],
      );
}

class AsyncButton extends StatelessWidget {
  const AsyncButton({required this.label, required this.onPressed, super.key, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AppProvider>().busy;
    return ElevatedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon ?? Icons.arrow_forward_rounded),
      label: Text(busy ? 'Please wait' : label),
    );
  }
}

class ProductImage extends StatelessWidget {
  const ProductImage({required this.product, super.key, this.height = 160});
  final Product product;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: product.imageUrl.isEmpty
            ? Container(
                height: height,
                color: const Color(0xFFFFE0B2),
                child: Center(
                  child: Icon(
                    product.category == 'Dips' ? Icons.soup_kitchen_rounded : Icons.lunch_dining_rounded,
                    size: height * .42,
                    color: MashColors.primary,
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: product.imageUrl,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: height, color: const Color(0xFFFFE0B2)),
                errorWidget: (_, __, ___) => Container(height: height, color: const Color(0xFFFFE0B2), child: const Icon(Icons.lunch_dining_rounded)),
              ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, required this.message, super.key});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: MashColors.primary.withValues(alpha: .55)),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final error = app.error;
    final message = app.message;
    if (error == null && message == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: error == null ? const Color(0xFFE2F5E9) : const Color(0xFFFFE3E3), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(error == null ? Icons.check_circle_outline : Icons.error_outline, color: error == null ? MashColors.success : MashColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(error ?? message!)),
        IconButton(onPressed: app.clearNotice, icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(status == OrderStatus.delivered ? Icons.check_circle : Icons.timelapse, size: 18, color: status == OrderStatus.delivered ? MashColors.success : MashColors.primary),
        label: Text(statusLabel(status), style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: status == OrderStatus.delivered
            ? const Color(0xFFE2F5E9)
            : status == OrderStatus.cancelled
                ? const Color(0xFFFFE3E3)
                : const Color(0xFFFFECE8),
        side: BorderSide.none,
      );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: MashColors.primary))),
          if (action != null) action!,
        ],
      );
}

class MashPanel extends StatelessWidget {
  const MashPanel({required this.child, super.key, this.color = Colors.white, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MashColors.primary.withValues(alpha: .08)),
          boxShadow: [BoxShadow(color: MashColors.primary.withValues(alpha: .08), blurRadius: 18, offset: const Offset(0, 7))],
        ),
        child: child,
      );
}
