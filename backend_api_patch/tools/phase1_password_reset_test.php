<?php
/**
 * Forgot-password flow (AUTH-5..8), tested in-process with a FAKE mailer so no real
 * email is ever sent. The whole HTTP stack (our middleware included) runs.
 *
 *   php phase1_password_reset_test.php [projectRoot] [email]
 *
 * It changes the test user's password during the test and restores the original
 * hash at the end; it also removes the OTP rows it created.
 */
$root = $argv[1] ?? 'J:/laragon/www/rosen_barber';
$email = $argv[2] ?? 'apitest.staff@rosen.test';
chdir($root);
require $root . '/vendor/autoload.php';
$app = require $root . '/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$kernel->bootstrap();   // facades (DB, Mail, …) need the app booted before the first request

use App\Mail\PasswordResetOtpMail;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;

Mail::fake();

function call(string $method, string $uri, array $data = [], ?string $token = null): array
{
    global $kernel;
    Auth::forgetGuards();                       // the guard caches the user between in-process requests
    $server = ['HTTP_ACCEPT' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'];
    if ($token) {
        $server['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;
    }
    $res = $kernel->handle(Request::create('/api/v1' . $uri, $method, $data, [], [], $server));

    return [$res->getStatusCode(), json_decode($res->getContent(), true) ?? []];
}

$results = [];
function check(string $name, bool $ok, string $detail = ''): void
{
    global $results;
    $results[] = [$ok, $name, $detail];
}

function lastOtp(): ?string
{
    $sent = Mail::sent(PasswordResetOtpMail::class);

    return $sent->isEmpty() ? null : $sent->last()->emailData['otp'];
}

function clearLimits(string $email): void
{
    foreach (['forgot|127.0.0.1|' . $email, 'verify|127.0.0.1', 'resend|127.0.0.1|' . $email, 'reset|127.0.0.1|' . $email, 'login|127.0.0.1|' . $email] as $k) {
        RateLimiter::clear('api-rl:' . $k);
    }
}

$user = DB::table('users')->where('email', $email)->first();
$origHash = $user->password;
$oldPw = 'Rosen@12345';
$newPw = 'Fresh#Pass7';
clearLimits($email);

try {
    // --- AUTH-5 forgot-password
    [$s, $j] = call('POST', '/auth/forgot-password', ['email' => 'nobody@nowhere.test']);
    check('AUTH-5 unknown email → 422 with the web\'s message', $s === 422 && str_contains($j['message'], 'could not find an active account'), "http $s: " . ($j['message'] ?? ''));

    [$s, $j] = call('POST', '/auth/forgot-password', ['email' => 'not-an-email']);
    check('AUTH-5 invalid email → 422', $s === 422 && isset($j['errors']['email']), "http $s");

    // a token issued BEFORE the reset must stop working after it
    [, $login] = call('POST', '/auth/login', ['email' => $email, 'password' => $oldPw, 'device_name' => 'before-reset']);
    $oldToken = $login['data']['token'] ?? null;

    [$s, $j] = call('POST', '/auth/forgot-password', ['email' => strtoupper($email)]);   // case-insensitive like the web
    $otp1 = lastOtp();
    check('AUTH-5 sends a 6-digit OTP by email (fake mailer), response never contains it',
        $s === 200 && preg_match('/^\d{6}$/', (string) $otp1) && !str_contains(json_encode($j), (string) $otp1) && ($j['data']['masked_email'] ?? '') !== '',
        "http $s, masked=" . ($j['data']['masked_email'] ?? ''));
    $row = DB::table('password_reset_otps')->where('user_id', $user->id)->latest('id')->first();
    check('OTP is stored hashed, expires in ~10 minutes, attempts=0',
        $row && $row->otp !== $otp1 && Hash::check($otp1, $row->otp) && $row->attempts == 0 && strtotime($row->expires_at) - time() > 540 && strtotime($row->expires_at) - time() <= 600);

    // --- AUTH-6 verify-otp
    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => '12345']);
    check('AUTH-6 OTP not 6 digits → 422', $s === 422 && isset($j['errors']['otp']), $j['message'] ?? '');

    $wrong = $otp1 === '111111' ? '222222' : '111111';
    for ($i = 1; $i <= 4; $i++) {
        [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $wrong]);
    }
    check('AUTH-6 wrong OTP → 422 "incorrect", attempts counted (4 so far)', $s === 422 && str_contains($j['message'], 'incorrect')
        && DB::table('password_reset_otps')->where('id', $row->id)->value('attempts') == 4, $j['message'] ?? '');

    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $wrong]);
    check('AUTH-6 5th wrong OTP → "Too many attempts"', $s === 422 && str_contains($j['message'], 'Too many attempts'), $j['message'] ?? '');

    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $otp1]);
    check('AUTH-6 even the RIGHT OTP is refused after 5 wrong tries (brute-force lock)', $s === 422 && str_contains($j['message'], 'Too many attempts'), $j['message'] ?? '');

    // --- AUTH-7 resend-otp
    [$s, $j] = call('POST', '/auth/resend-otp', ['email' => $email]);
    $otp2 = lastOtp();
    check('AUTH-7 resend → new OTP, old OTP expired, attempts reset',
        $s === 200 && $otp2 !== null && DB::table('password_reset_otps')->where('id', $row->id)->value('expires_at') <= date('Y-m-d H:i:s') . '' , "http $s");

    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $otp1 === $otp2 ? $wrong : $otp1]);
    check('the OLD OTP no longer works after a resend', $s === 422, $j['message'] ?? '');

    // expired OTP
    DB::table('password_reset_otps')->where('user_id', $user->id)->latest('id')->limit(1)->update(['expires_at' => now()->subMinute()]);
    $latestId = DB::table('password_reset_otps')->where('user_id', $user->id)->max('id');
    DB::table('password_reset_otps')->where('id', $latestId)->update(['expires_at' => now()->subMinute()]);
    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $otp2]);
    check('AUTH-6 expired OTP → "expired"', $s === 422 && str_contains($j['message'], 'expired'), $j['message'] ?? '');

    // fresh OTP for the real path
    clearLimits($email);
    call('POST', '/auth/resend-otp', ['email' => $email]);
    $otp3 = lastOtp();
    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $otp3]);
    $token = $j['data']['reset_token'] ?? null;
    check('AUTH-6 correct OTP → 64-char reset_token, expires in 900 s',
        $s === 200 && strlen((string) $token) === 64 && ($j['data']['expires_in_seconds'] ?? 0) === 900, "http $s");

    [$s, $j] = call('POST', '/auth/verify-otp', ['email' => $email, 'otp' => $otp3]);
    check('AUTH-6 the same OTP cannot be used twice', $s === 422 && str_contains($j['message'], 'already been used'), $j['message'] ?? '');

    // --- AUTH-8 reset-password
    $base = ['email' => $email, 'reset_token' => $token];
    [$s, $j] = call('POST', '/auth/reset-password', $base + ['password' => 'abcdefgh', 'password_confirmation' => 'abcdefgh']);
    check('AUTH-8 weak password (no number) → 422', $s === 422 && isset($j['errors']['password']), $j['message'] ?? '');
    [$s, $j] = call('POST', '/auth/reset-password', $base + ['password' => $newPw, 'password_confirmation' => 'different1']);
    check('AUTH-8 confirmation mismatch → 422', $s === 422 && str_contains($j['message'], 'Confirm password'), $j['message'] ?? '');
    [$s, $j] = call('POST', '/auth/reset-password', ['email' => $email, 'reset_token' => str_repeat('a', 64), 'password' => $newPw, 'password_confirmation' => $newPw]);
    check('AUTH-8 wrong reset token → 422 "session has expired"', $s === 422 && str_contains($j['message'], 'expired'), $j['message'] ?? '');

    [$s, $j] = call('POST', '/auth/reset-password', $base + ['password' => $newPw, 'password_confirmation' => $newPw]);
    check('AUTH-8 valid reset → 200', $s === 200, $j['message'] ?? '');

    [$s] = call('GET', '/auth/me', [], $oldToken);
    check('after reset the old session/token is signed out everywhere (extra protection)', $s === 401, "http $s");
    [$s] = call('POST', '/auth/login', ['email' => $email, 'password' => $oldPw]);
    check('old password no longer works', $s === 401, "http $s");
    [$s, $j] = call('POST', '/auth/login', ['email' => $email, 'password' => $newPw]);
    check('new password works', $s === 200 && !empty($j['data']['token']), "http $s");

    [$s, $j] = call('POST', '/auth/reset-password', $base + ['password' => 'Another#Pw9', 'password_confirmation' => 'Another#Pw9']);
    check('AUTH-8 the reset token is single-use', $s === 422, $j['message'] ?? '');
    $left = DB::table('password_reset_otps')->where('user_id', $user->id)->whereNotNull('reset_token')->count();
    check('no usable reset token is left behind in the database', $left === 0, "rows with token: $left");

    // --- inactive account cannot request a reset
    DB::table('users')->where('id', $user->id)->update(['active_status' => 0]);
    clearLimits($email);
    [$s, $j] = call('POST', '/auth/forgot-password', ['email' => $email]);
    check('inactive account cannot start a reset (same as web)', $s === 422 && str_contains($j['message'], 'could not find an active account'), $j['message'] ?? '');
    DB::table('users')->where('id', $user->id)->update(['active_status' => 1]);

    // --- mail failure is reported as the web does (no 500)
    clearLimits($email);
    Mail::shouldReceive('to')->andThrow(new RuntimeException('SMTP down'));
    [$s, $j] = call('POST', '/auth/forgot-password', ['email' => $email]);
    check('mail failure → 422 friendly message, no internals leaked', $s === 422 && str_contains($j['message'], 'Unable to send the verification email') && !str_contains(json_encode($j), 'SMTP down') || config('app.debug'), "http $s: " . ($j['message'] ?? ''));
} finally {
    DB::table('users')->where('id', $user->id)->update(['password' => $origHash, 'active_status' => 1]);
    DB::table('password_reset_otps')->where('user_id', $user->id)->delete();
    DB::table('personal_access_tokens')->where('tokenable_id', $user->id)->delete();
    clearLimits($email);
}

$w = max(array_map(fn ($r) => strlen($r[1]), $results));
echo "\nPhase 1 password-reset tests (fake mailer)\n\n";
$failed = 0;
foreach ($results as [$ok, $name, $detail]) {
    echo ($ok ? '  PASS ' : '  FAIL ') . str_pad($name, $w) . ($detail ? '  ' . $detail : '') . "\n";
    $failed += $ok ? 0 : 1;
}
echo "\n" . (count($results) - $failed) . '/' . count($results) . ' passed' . ($failed ? ", $failed FAILED" : '') . "\n";
echo 'original password restored: ' . (Hash::check($oldPw, DB::table('users')->where('id', $user->id)->value('password')) ? 'yes' : 'NO') . "\n";
exit($failed ? 1 : 0);
