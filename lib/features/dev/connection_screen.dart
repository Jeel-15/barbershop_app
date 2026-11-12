import 'package:barbershop_app/core/config/env.dart';
import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Debug tool: "can this phone reach the API?". Shows the address the build
/// uses, the answer time of `GET /health`, whether the database schema is OK,
/// and how the phone's clock compares with the shop's.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _Result {
  const _Result({this.ok = false, this.ms, this.data, this.failure});

  final bool ok;
  final int? ms;
  final Map<String, dynamic>? data;
  final Failure? failure;
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  static const _localUsb = 'http://localhost:8081${ApiBaseUrl.defaultPath}';

  final _addressCtl = TextEditingController();
  String? _addressError;
  _Result? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _test();
  }

  @override
  void dispose() {
    _addressCtl.dispose();
    super.dispose();
  }

  /// Points the app at [url] (already a full address), signs out of the old
  /// server and tests the new one.
  Future<void> _switchTo(String? url) async {
    setState(() => _busy = true);
    await ref.read(apiBaseUrlProvider.notifier).use(url);
    if (!mounted) return;
    _addressCtl.clear();
    setState(() => _addressError = null);
    await _test();
  }

  Future<void> _saveTyped() async {
    final url = ApiBaseUrl.normalize(_addressCtl.text);
    if (url == null) {
      setState(() => _addressError = 'That is not a web address.');
      return;
    }
    await _switchTo(url);
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    final sw = Stopwatch()..start();
    try {
      final res = await ref.read(apiClientProvider).get('/health');
      setState(
        () => _result = _Result(
          ok: res.data['schema_ok'] == true,
          ms: sw.elapsedMilliseconds,
          data: res.data,
        ),
      );
    } on Failure catch (f) {
      setState(() => _result = _Result(ms: sw.elapsedMilliseconds, failure: f));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = _result;
    final phone = DateTime.now();
    final shop = ShopTime.now();

    Widget row(String k, String v, {Color? color}) => AppListRow(
      title: k,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          v,
          textAlign: TextAlign.end,
          style: AppType.caption.copyWith(color: color ?? t.textSecondary),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Connection test')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.sm,
              AppSpace.page,
              AppSpace.lg,
            ),
            child: AppCard(
              raised: true,
              child: Row(
                children: [
                  Icon(
                    _busy
                        ? Icons.sync_rounded
                        : (r?.ok ?? false)
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    size: 38,
                    color: _busy
                        ? t.textMuted
                        : ((r?.ok ?? false) ? t.success : t.danger),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _busy
                              ? 'Testing...'
                              : (r?.ok ?? false)
                              ? 'Connected'
                              : 'Cannot reach the API',
                          style: AppType.heading.copyWith(color: t.text),
                        ),
                        Text(
                          r?.failure?.userMessage ??
                              (r?.ms == null ? '' : 'Answered in ${r!.ms} ms'),
                          style: AppType.caption.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
            child: AppButton(
              label: 'Test again',
              icon: Icons.refresh_rounded,
              loading: _busy,
              onPressed: _test,
            ),
          ),
          AppListGroup(
            title: 'This build',
            children: [
              row('API address', ref.watch(apiBaseUrlProvider)),
              row('Build default', Env.apiBaseUrl),
              row('Flavor', Env.flavor.name),
            ],
          ),
          if (!Env.isProd) ...[
            AppListGroup(
              title: 'Switch server (signs you out)',
              children: [
                AppListRow(
                  title: 'Local PC (USB cable)',
                  subtitle: _localUsb,
                  onTap: _busy ? null : () => _switchTo(_localUsb),
                ),
                AppListRow(
                  title: 'Build default',
                  subtitle: Env.apiBaseUrl,
                  onTap: _busy ? null : () => _switchTo(null),
                ),
                for (final url in ref.watch(appPrefsProvider).recentServers)
                  AppListRow(
                    title: 'Recent',
                    subtitle: url,
                    onTap: _busy ? null : () => _switchTo(url),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.page,
                AppSpace.md,
                AppSpace.page,
                AppSpace.sm,
              ),
              child: AppTextField(
                label: 'New address',
                hint: 'abcd-1234.ngrok-free.app',
                helperText:
                    'Paste the tunnel or live address. The path '
                    '${ApiBaseUrl.defaultPath} is added if you give only the host.',
                controller: _addressCtl,
                errorText: _addressError,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveTyped(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
              child: AppButton(
                label: 'Use this address',
                icon: Icons.link_rounded,
                loading: _busy,
                onPressed: _saveTyped,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
          ],
          AppListGroup(
            title: 'Server',
            children: [
              row(
                'Database',
                r?.data?['db'] == true ? 'OK' : (r == null ? '...' : 'Problem'),
              ),
              row(
                'Schema',
                r?.data?['schema_ok'] == true
                    ? 'OK'
                    : (r == null ? '...' : 'Check failed'),
              ),
              row(
                'API version',
                '${r?.data?['version'] ?? '...'}  ·  build ${r?.data?['build'] ?? '...'}',
              ),
              row('Server time', '${r?.data?['time'] ?? '...'}'),
              if (r?.failure?.requestId != null)
                row('Support code', r!.failure!.requestId!),
            ],
          ),
          AppListGroup(
            title: 'Clocks',
            children: [
              row(
                'Shop time (Edmonton)',
                '${ShopTime.dayLabel(shop)}  ${ShopTime.timeLabel(shop.hour * 60 + shop.minute)}',
              ),
              row(
                'This phone',
                '${ShopTime.dayLabel(phone)}  ${ShopTime.timeLabel(phone.hour * 60 + phone.minute)}  (UTC${phone.timeZoneOffset.isNegative ? '-' : '+'}${phone.timeZoneOffset.inHours.abs()})',
              ),
            ],
          ),
          if (r?.failure != null && r!.failure is! ServerFailure)
            Padding(
              padding: const EdgeInsets.all(AppSpace.page),
              child: Text(
                'Cannot connect? On a phone the address "localhost" is the phone itself.\n'
                'Use the PC\'s Wi-Fi address in API_BASE_URL, or for Android with USB run '
                '"adb reverse tcp:80 tcp:80". See docs/RUN_ON_PHONE.md.',
                style: AppType.caption.copyWith(color: t.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
