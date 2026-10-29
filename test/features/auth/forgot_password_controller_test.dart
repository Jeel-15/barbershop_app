import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/features/auth/application/forgot_password_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';

void main() {
  late AuthHarness h;
  late DateTime now;
  late ProviderSubscription<ForgotPasswordState> keepAlive;

  ForgotPasswordController ctl() =>
      h.container.read(forgotPasswordProvider.notifier);
  ForgotPasswordState st() => h.container.read(forgotPasswordProvider);

  setUp(() async {
    h = await AuthHarness.create();
    now = DateTime(2026, 1, 1, 12);
    ForgotPasswordController.clock = () => now;
    keepAlive = h.container.listen(forgotPasswordProvider, (_, _) {});
  });

  tearDown(() {
    keepAlive.close();
    ForgotPasswordController.clock = DateTime.now;
  });

  test('bad e-mail is caught on the phone, no request', () async {
    await ctl().sendCode('nope');
    expect(st().step, ResetStep.email);
    expect(st().fieldErrors['email'], isNotNull);
    expect(h.repo.calls, isEmpty);
  });

  test('full happy path', () async {
    await ctl().sendCode(' a@b.co ');
    expect(st().step, ResetStep.code);
    expect(st().maskedEmail, 'a***@rosen.test');
    expect(st().resendAvailableAt, now.add(const Duration(seconds: 45)));

    await ctl().verify('123456');
    expect(st().step, ResetStep.password);
    expect(st().resetToken, 'reset-tok');

    await ctl().setPassword('Secret#1', 'Secret#1');
    expect(st().step, ResetStep.done);
    expect(h.repo.calls, ['forgot:a@b.co', 'verify:123456', 'reset:reset-tok']);
  });

  test('a partial code does nothing', () async {
    await ctl().sendCode('a@b.co');
    await ctl().verify('123');
    expect(st().step, ResetStep.code);
    expect(h.repo.calls, ['forgot:a@b.co']);
  });

  test(
    'wrong code shows the server message under the code and stays',
    () async {
      h.repo.verifyFailure = const ValidationFailure(
        'Invalid',
        fieldErrors: {
          'otp': ['The code is incorrect.'],
        },
      );
      await ctl().sendCode('a@b.co');
      await ctl().verify('000000');
      expect(st().step, ResetStep.code);
      expect(st().fieldErrors['otp'], 'The code is incorrect.');
      expect(st().busy, isFalse);
    },
  );

  test('expired reset token sends the user back to the first step', () async {
    h.repo.verifyFailure = const ValidationFailure(
      'Invalid',
      fieldErrors: {
        'reset_token': ['Reset session expired.'],
      },
    );
    await ctl().sendCode('a@b.co');
    await ctl().verify('111111');
    expect(st().step, ResetStep.email);
    expect(st().error, 'Reset session expired.');
  });

  test(
    'resend is locked for 45 s, then allowed and restarts the pause',
    () async {
      await ctl().sendCode('a@b.co');
      await ctl().resend();
      expect(h.repo.calls.where((c) => c.startsWith('resend')), isEmpty);

      now = now.add(const Duration(seconds: 46));
      await ctl().resend();
      expect(h.repo.calls.where((c) => c.startsWith('resend')), hasLength(1));
      expect(st().resendAvailableAt, now.add(const Duration(seconds: 45)));
      expect(st().notice, isNotNull);
    },
  );

  test('passwords that differ are rejected without a request', () async {
    await ctl().sendCode('a@b.co');
    await ctl().verify('123456');
    await ctl().setPassword('one', 'two');
    expect(st().step, ResetStep.password);
    expect(st().fieldErrors['password'], contains('match'));
    expect(h.repo.calls.where((c) => c.startsWith('reset')), isEmpty);
  });

  test('network failure keeps the step and shows the message', () async {
    h.repo.forgotFailure = const NetworkFailure();
    await ctl().sendCode('a@b.co');
    expect(st().step, ResetStep.email);
    expect(st().error, contains('No connection'));
  });

  test('back walks one step at a time', () async {
    await ctl().sendCode('a@b.co');
    await ctl().verify('123456');
    ctl().back();
    expect(st().step, ResetStep.code);
    ctl().back();
    expect(st().step, ResetStep.email);
  });
}
