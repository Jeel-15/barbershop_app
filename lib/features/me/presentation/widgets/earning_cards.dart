import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/paged_list.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/me/domain/me_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A paged list inside the page's own scroll view.
class PagedRows<T> extends StatelessWidget {
  const PagedRows({
    super.key,
    required this.async,
    required this.empty,
    required this.builder,
    required this.onRetry,
    required this.onMore,
  });

  final AsyncValue<PagedState<T>> async;
  final String empty;
  final Widget Function(T) builder;
  final VoidCallback onRetry;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final s = async.value;
    if (s == null) {
      if (async.hasError) {
        return ErrorState(
          message: async.error is Failure
              ? (async.error! as Failure).userMessage
              : 'Could not load this list.',
          onRetry: onRetry,
        );
      }
      return const SkeletonRows(count: 4);
    }
    if (s.items.isEmpty) {
      return QuietState(title: 'Nothing here', message: empty);
    }
    return Column(
      children: [
        for (final i in s.items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
            child: builder(i),
          ),
        if (s.loadingMore)
          const Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        if (s.loadMoreFailed)
          TextButton(
            onPressed: onMore,
            child: const Text('Could not load more. Tap to retry'),
          ),
      ],
    );
  }
}

class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}

class KvLine extends StatelessWidget {
  const KvLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppType.caption.copyWith(color: t.textSecondary),
            ),
          ),
          Text(value, style: AppType.body.copyWith(color: t.text)),
        ],
      ),
    );
  }
}

class ServiceEarningCard extends StatelessWidget {
  const ServiceEarningCard({super.key, required this.s});

  final ServiceEarning s;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.name, style: AppType.bodyStrong.copyWith(color: t.text)),
          Text(
            '${s.price.format()} · ${s.duration} min',
            style: AppType.caption.copyWith(color: t.textSecondary),
          ),
          Divider(height: AppSpace.lg, color: t.border),
          KvLine('Total Appointment', '${s.appointments}'),
          KvLine('Total Service Commision', s.commission.format()),
          KvLine('Total Service Tip', s.tips.format()),
          KvLine('Total Earn', s.total.format()),
        ],
      ),
    );
  }
}

class DailyEarningCard extends StatelessWidget {
  const DailyEarningCard({super.key, required this.d});

  final DailyEarning d;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InfoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ShopTime.relativeDay(ShopTime.parseDate(d.date)),
                  style: AppType.bodyStrong.copyWith(color: t.text),
                ),
              ),
              Text(
                d.total.format(),
                style: AppType.bodyStrong.copyWith(color: t.accentText),
              ),
            ],
          ),
          Divider(height: AppSpace.lg, color: t.border),
          KvLine('Product Commision', d.productCommission.format()),
          KvLine('Service Tip', d.tips.format()),
          KvLine('Service Commision', d.serviceCommission.format()),
        ],
      ),
    );
  }
}
