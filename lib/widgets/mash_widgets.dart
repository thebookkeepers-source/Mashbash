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
  const MashLogo({super.key, this.compact = false, this.onDark = false});
  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MashMark(size: compact ? 42 : 72),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MASHBASH', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: compact ? 20 : 30, color: onDark ? Colors.white : MashColors.primary, letterSpacing: 1)),
                Text('Meet.Eat.Repeat', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 10 : 13, fontWeight: FontWeight.w700, color: onDark ? MashColors.secondary : MashColors.primary)),
              ],
            ),
          ),
        ],
      );
}

class MashMark extends StatelessWidget {
  const MashMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/branding/logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Mashbash logo',
        ),
      );
}

class AsyncButton extends StatelessWidget {
  const AsyncButton({required this.label, required this.onPressed, super.key, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final busy = context.select<AppProvider, bool>((app) => app.busy);
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
                maxWidthDiskCache: 960,
                maxHeightDiskCache: 960,
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.hasBoundedHeight ? (constraints.maxHeight - 40).clamp(0, double.infinity).toDouble() : 0),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 56, color: MashColors.primary.withValues(alpha: .55)),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ]),
            ),
          ),
        ),
      );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final notice = context.select<AppProvider, ({String? error, String? message})>((app) => (error: app.error, message: app.message));
    final error = notice.error;
    final message = notice.message;
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
        IconButton(onPressed: context.read<AppProvider>().clearNotice, icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(status.isCompleted ? Icons.check_circle : Icons.timelapse, size: 18, color: status.isCompleted ? MashColors.success : MashColors.primary),
        label: Text(statusLabel(status), style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: status.isCompleted
            ? const Color(0xFFE2F5E9)
            : status.isCancelled
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
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: MashColors.primary))),
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

class ConnectionGuard extends StatelessWidget {
  const ConnectionGuard({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = context.select<AppProvider, ({bool error, bool usable})>((app) => (error: app.connectionError, usable: app.hasUsableData));
    if (status.error && !status.usable) return const ConnectionErrorScreen();
    return Stack(children: [
      child,
      if (status.error)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 12,
          right: 12,
          child: const Material(color: Colors.transparent, child: OfflineBanner()),
        ),
    ]);
  }
}

class ConnectionErrorScreen extends StatelessWidget {
  const ConnectionErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Material(
      color: MashColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const MashLogo(),
              const SizedBox(height: 28),
              const Icon(Icons.cloud_off_rounded, size: 76, color: MashColors.primary),
              const SizedBox(height: 14),
              Text('Connection Error', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: MashColors.primary)),
              const SizedBox(height: 8),
              const Text(
                'There is an error connecting to the server. Please check your internet connection and try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: app.retryingConnection ? null : app.retryConnection,
                icon: app.retryingConnection
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded),
                label: Text(app.retryingConnection ? 'Checking connection' : 'Retry'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: MashColors.secondary, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]),
      child: Row(children: [
        const MashMark(size: 30),
        const SizedBox(width: 9),
        const Expanded(child: Text('Offline mode. Some information may be out of date.', style: TextStyle(color: MashColors.primary, fontWeight: FontWeight.w800))),
        TextButton(onPressed: app.retryingConnection ? null : app.retryConnection, child: const Text('Retry')),
      ]),
    );
  }
}
