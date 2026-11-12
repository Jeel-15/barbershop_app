import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/presentation/widgets/appointment_tile.dart';
import 'package:flutter/material.dart';

/// How many bookings the sheet lists; "View all" opens the rest in Bookings.
const homeSheetLimit = 10;

/// "Show more" on Home: the first [homeSheetLimit] bookings of Today or
/// Upcoming in a sheet that rises from the bottom, so the dashboard itself
/// keeps its height. A row opens its booking, "View all" opens Bookings.
Future<void> showHomeAppointmentsSheet(
  BuildContext context, {
  required String title,
  required List<AppointmentRow> rows,
  required int total,
  required bool showDate,
  required void Function(AppointmentRow row) onOpen,
  required VoidCallback onViewAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      reverseDuration: Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) => HomeAppointmentsSheet(
      title: title,
      rows: rows.take(homeSheetLimit).toList(),
      total: total < rows.length ? rows.length : total,
      showDate: showDate,
      onOpen: onOpen,
      onViewAll: onViewAll,
    ),
  );
}

class HomeAppointmentsSheet extends StatelessWidget {
  const HomeAppointmentsSheet({
    super.key,
    required this.title,
    required this.rows,
    required this.total,
    required this.showDate,
    required this.onOpen,
    required this.onViewAll,
  });

  final String title;
  final List<AppointmentRow> rows;
  final int total;
  final bool showDate;
  final void Function(AppointmentRow row) onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.78, 0.95],
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: t.sheet,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 30,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // The grabber and the title stay put; only the bookings scroll.
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.sm,
                  AppSpace.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppType.heading.copyWith(color: t.text),
                          ),
                          Text(
                            'Showing ${rows.length} of $total',
                            style: AppType.caption.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(Icons.close_rounded, color: t.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.xs,
                    AppSpace.page,
                    AppSpace.lg,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpace.sm + 2),
                  itemBuilder: (context, i) => AppointmentTile(
                    row: rows[i],
                    showDate: showDate,
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpen(rows[i]);
                    },
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.page,
                  AppSpace.md + bottom,
                ),
                decoration: BoxDecoration(
                  color: t.sheet,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: AppButton(
                  label: 'View all $total',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    Navigator.of(context).pop();
                    onViewAll();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
