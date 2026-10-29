import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/auth/domain/auth_user.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Launch data of the signed-in session. Only watch this below the auth guard
/// (inside `/app/**`), where a signed-in state is guaranteed.
final bootstrapProvider = Provider<Bootstrap>((ref) {
  final s = ref.watch(sessionControllerProvider);
  if (s is SignedIn) return s.bootstrap;
  // Sign-out: the pages are still mounted for one frame before the router removes them.
  final last = ref.read(sessionControllerProvider.notifier).lastBootstrap;
  if (last != null) return last;
  throw StateError('bootstrapProvider read while signed out');
});

final currentUserProvider = Provider<AuthUser>(
  (ref) => ref.watch(bootstrapProvider).user,
);

/// True while the saved copy of the launch data is in use (no connection).
final isOfflineProvider = Provider<bool>((ref) {
  final s = ref.watch(sessionControllerProvider);
  return s is SignedIn && s.offline;
});
