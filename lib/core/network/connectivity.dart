import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool _hasLink(List<ConnectivityResult> r) =>
    r.any((e) => e != ConnectivityResult.none);

/// Whether the phone has a network link (Wi-Fi, mobile...). It says nothing
/// about whether the shop's server answers; the screens learn that from the
/// failures themselves.
///
/// Starts as online, so a slow first check never flashes "offline".
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  yield _hasLink(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(_hasLink).distinct();
});
