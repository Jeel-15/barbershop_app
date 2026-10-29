<?php
/**
 * APPT-11 (complete a booked appointment into an invoice), tested in-process. The feature is
 * OFF by default (config api_v1.feature_flags.complete_from_appointment) because the web cannot
 * do it; this checks the switch and the logic that is waiting behind it.
 *
 *   php phase3b_complete_test.php [projectRoot] [adminEmail] [staffEmail] [pw]
 *
 * Needs the marked test data (APITEST-1 pending barber 51, APITEST-4 barber 49 only, APITEST-5 cancelled).
 * Restores the changed appointment at the end.
 */
$root = $argv[1] ?? 'J:/laragon/www/rosen_barber';
$adminEmail = $argv[2] ?? 'apitest.admin@rosen.test';
$staffEmail = $argv[3] ?? 'apitest.staff@rosen.test';
$pw = $argv[4] ?? 'Rosen@12345';
chdir($root);
require $root . '/vendor/autoload.php';
$app = require $root . '/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$kernel->bootstrap();

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;

Mail::fake();

function call(string $method, string $uri, array $data = [], ?string $token = null): array
{
    global $kernel;
    Auth::forgetGuards();
    $server = ['HTTP_ACCEPT' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1', 'CONTENT_TYPE' => 'application/json'];
    if ($token) {
        $server['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;
    }
    $res = $kernel->handle(Request::create('/api/v1' . $uri, $method, [], [], [], $server, $method === 'GET' ? null : json_encode($data)));

    return [$res->getStatusCode(), json_decode($res->getContent(), true) ?? []];
}
$pass = $fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    $ok ? $pass++ : $fail++;
    echo ($ok ? '  PASS ' : '  FAIL ') . $name . ($detail !== '' ? '  ' . $detail : '') . "\n";
}

$id = fn (string $code) => (int) DB::table('tbl_appointment')->where('booking_code', $code)->value('appointment_id');
[$a1, $a4, $a5] = [$id('APITEST-1'), $id('APITEST-4'), $id('APITEST-5')];
$backup = (array) DB::table('tbl_appointment')->where('appointment_id', $a1)->first();
$backupLines = DB::table('tbl_appointment_service')->where('appointment_id', $a1)->get()->map(fn ($r) => (array) $r)->all();

try {
    [, $l] = call('POST', '/auth/login', ['email' => $adminEmail, 'password' => $pw, 'device_name' => 'ct']);
    $admin = $l['data']['token'];
    [, $l] = call('POST', '/auth/login', ['email' => $staffEmail, 'password' => $pw, 'device_name' => 'ct']);
    $staff = $l['data']['token'];
    $svc = DB::table('tbl_service')->where('status', 1)->whereNull('deleted_at')->value('id');
    $barber = (int) DB::table('users')->where('email', $staffEmail)->value('id');
    $cart = ['items' => [['type' => 'service', 'id' => $svc, 'staff_id' => $barber, 'qty' => 1]], 'tip' => 2];

    [$c, $r] = call('POST', "/appointments/$a1/complete", $cart, $admin);
    check('flag OFF (default): 404 "not available yet" and nothing changes', $c === 404 && str_contains($r['message'] ?? '', 'not available') && DB::table('tbl_appointment')->where('appointment_id', $a1)->value('is_invoiced') === null, "http $c");

    config(['api_v1.feature_flags.complete_from_appointment' => true]);

    [$c] = call('POST', "/appointments/$a5/complete", $cart, $admin);
    check('flag ON: a cancelled appointment cannot be completed → 409', $c === 409);
    [$c] = call('POST', '/appointments/99999999/complete', $cart, $admin);
    check('flag ON: unknown appointment → 404', $c === 404);
    [$c] = call('POST', "/appointments/$a4/complete", $cart, $staff);
    check('flag ON: staff cannot complete another barber\'s appointment → 404', $c === 404);

    [$c, $r] = call('POST', "/appointments/$a1/complete", $cart, $staff);
    $inv = $r['data']['invoice'] ?? [];
    $row = DB::table('tbl_appointment')->where('appointment_id', $a1)->first();
    check('flag ON: staff completes their own appointment into a paid invoice', $c === 200 && (int) $row->status === 1 && $row->is_invoiced == 1 && (int) $row->invoice_created_by === $barber && preg_match('/^INV-\d{8}-\d{4}$/', (string) $row->invoice_number) && ($inv['id'] ?? 0) === $a1 && count($inv['lines'] ?? []) === 1, "http $c " . ($row->invoice_number ?? ''));
    [$c] = call('POST', "/appointments/$a1/complete", $cart, $staff);
    check('flag ON: completing it a second time → 409', $c === 409);
} finally {
    DB::table('tbl_appointment')->where('appointment_id', $a1)->update(Arr::except($backup, ['appointment_id']));
    DB::table('tbl_appointment_service')->where('appointment_id', $a1)->delete();
    foreach ($backupLines as $line) {
        DB::table('tbl_appointment_service')->insert($line);
    }
}

echo "\n$pass/" . ($pass + $fail) . ' passed' . ($fail ? ", $fail FAILED" : '') . "\n";
exit($fail ? 1 : 0);
