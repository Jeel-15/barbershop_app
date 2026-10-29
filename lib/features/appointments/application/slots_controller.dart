import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the slot finder needs: a day, the barbers and the services.
@immutable
class SlotQuery {
  const SlotQuery({
    required this.date,
    required this.staffIds,
    required this.serviceIds,
  });

  final String date;
  final List<int> staffIds;
  final List<int> serviceIds;

  @override
  bool operator ==(Object other) =>
      other is SlotQuery &&
      other.date == date &&
      listEquals(other.staffIds, staffIds) &&
      listEquals(other.serviceIds, serviceIds);

  @override
  int get hashCode =>
      Object.hash(date, Object.hashAll(staffIds), Object.hashAll(serviceIds));
}

/// Free times for one day. Re-asked each time the sheet needs them, so a slot
/// taken by another phone is never offered from an old answer.
final slotsProvider = FutureProvider.autoDispose.family<SlotsResult, SlotQuery>(
  (ref, q) => ref
      .read(appointmentsRepositoryProvider)
      .slots(date: q.date, staffIds: q.staffIds, serviceIds: q.serviceIds),
);
