<?php
/**
 * Invoice emails (POS-3/6 "send after save", POS-7), tested in-process with a FAKE mailer so no
 * real email is ever sent (the local .env points at the live SMTP server).
 *
 *   php phase3b_invoice_mail_test.php [projectRoot] [adminEmail] [adminPw]
 *
 * Creates two invoices for a test customer (phone 5559995001) and removes them at the end;
 * Setting.invoice_send_sts is switched on for part of the run and restored.
 */
$root = $argv[1] ?? 'J:/laragon/www/rosen_barber';
$adminEmail = $argv[2] ?? 'apitest.admin@rosen.test';
$adminPw = $argv[3] ?? 'Rosen@12345';
chdir($root);
require $root . '/vendor/autoload.php';
$app = require $root . '/bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$kernel->bootstrap();

use App\Mail\invoiceMail;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;

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

$pass = 0;
$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $pass, $fail;
    $ok ? $pass++ : $fail++;
    echo ($ok ? '  PASS ' : '  FAIL ') . $name . ($detail !== '' ? '  ' . $detail : '') . "\n";
}

$origSts = DB::table('tbl_setting')->where('id', 1)->value('invoice_send_sts');
$ids = [];
try {
    [, $login] = call('POST', '/auth/login', ['email' => $adminEmail, 'password' => $adminPw, 'device_name' => 'mailtest']);
    $token = $login['data']['token'];
    $svc = DB::table('tbl_service')->where('status', 1)->whereNull('deleted_at')->value('id');
    $staff = DB::table('users')->where('role', 'Staff')->where('active_status', 1)->whereNull('deleted_at')->value('id');
    $cart = ['items' => [['type' => 'service', 'id' => $svc, 'staff_id' => $staff, 'qty' => 1]], 'customer' => ['name' => 'API TEST Mail', 'phone' => '5559995001', 'email' => 'customer@test.test']];

    DB::table('tbl_setting')->where('id', 1)->update(['invoice_send_sts' => 0]);
    [$c, $r] = call('POST', '/invoices', $cart, $token);
    $id = $r['data']['invoice']['id'] ?? 0;
    $ids[] = $id;
    check('invoice_send_sts = 0: saving sends no email', $c === 201 && Mail::sent(invoiceMail::class)->count() === 0);

    [$c, $r] = call('POST', "/invoices/$id/email", [], $token);
    check('POS-7 email: goes to the customer\'s address', $c === 200 && Mail::sent(invoiceMail::class, fn ($m) => $m->hasTo('customer@test.test'))->count() === 1, "http $c");

    [$c] = call('POST', "/invoices/$id/email", ['email' => 'other@test.test'], $token);
    check('POS-7 email: an address in the request overrides it', $c === 200 && Mail::sent(invoiceMail::class, fn ($m) => $m->hasTo('other@test.test'))->count() === 1);

    $appt = App\Models\Appointment::with(['serviceStaff', 'productStaff', 'services.service', 'products.product'])->find($id);
    $html = (new invoiceMail(collect([$appt])))->render();
    check('the invoice mail renders with the invoice number and total', str_contains($html, $appt->invoice_number) && str_contains($html, (string) number_format((float) $appt->total_amt, 2)), strlen($html) . ' bytes');

    DB::table('tbl_setting')->where('id', 1)->update(['invoice_send_sts' => 1]);
    $before = Mail::sent(invoiceMail::class)->count();
    [$c, $r] = call('POST', '/invoices', $cart, $token);
    $ids[] = $r['data']['invoice']['id'] ?? 0;
    check('invoice_send_sts = 1: saving mails the customer once', $c === 201 && Mail::sent(invoiceMail::class)->count() === $before + 1);

    [$c, $r] = call('POST', '/invoices', ['items' => $cart['items']], $token);   // guest placeholder address
    $guestId = $r['data']['invoice']['id'] ?? 0;
    $ids[] = $guestId;
    check('the Guest placeholder address is never mailed', $c === 201 && Mail::sent(invoiceMail::class)->count() === $before + 1);

    [$c, $r] = call('PUT', "/invoices/$id", $cart, $token);
    check('editing with invoice_send_sts = 1 mails the customer again', $c === 200 && Mail::sent(invoiceMail::class)->count() === $before + 2);

    // the mail server is down
    Mail::swap(new class {
        public function to() { throw new RuntimeException('SMTP down'); }
    });
    [$c, $r] = call('POST', "/invoices/$id/email", [], $token);
    check('POS-7 email: mailer failure → 502 with a clean message', $c === 502 && ($r['status'] ?? 1) === 0 && !str_contains(json_encode($r), 'SMTP'), "http $c: " . ($r['message'] ?? ''));

    [$c, $r] = call('POST', '/invoices', $cart, $token);
    $ids[] = $r['data']['invoice']['id'] ?? 0;
    check('mailer failure never rolls back the saved invoice (the web does, Q21)', $c === 201 && DB::table('tbl_appointment')->where('appointment_id', end($ids))->exists());
} finally {
    DB::table('tbl_setting')->where('id', 1)->update(['invoice_send_sts' => $origSts]);
    $ids = array_filter($ids);
    if ($ids) {
        DB::table('tbl_appointment_service')->whereIn('appointment_id', $ids)->delete();
        DB::table('tbl_appointment_product')->whereIn('appointment_id', $ids)->delete();
        DB::table('tbl_appointment')->whereIn('appointment_id', $ids)->delete();
    }
    DB::table('customers')->where('customer_phone', '5559995001')->delete();
    if (isset($guestId) && !DB::table('tbl_appointment')->where('customer_id', DB::table('customers')->where('customer_phone', '(555) 123-4567')->where('customer_email', 'info@bluecrownbarbers.com')->value('customer_id'))->exists()) {
        DB::table('customers')->where('customer_phone', '(555) 123-4567')->where('customer_email', 'info@bluecrownbarbers.com')->whereNotExists(fn ($q) => $q->select(DB::raw(1))->from('tbl_appointment')->whereColumn('tbl_appointment.customer_id', 'customers.customer_id'))->delete();
    }
}

echo "\n$pass/" . ($pass + $fail) . " passed" . ($fail ? ", $fail FAILED" : '') . "\n";
exit($fail ? 1 : 0);
