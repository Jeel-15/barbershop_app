<?php

namespace App\Services\Api;

use App\Mail\invoiceMail;
use App\Models\Appointment;
use App\Models\AppointmentProduct;
use App\Models\AppointmentService;
use App\Models\Customer;
use App\Models\Gst;
use App\Models\PaymentMethod;
use App\Models\Product;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Setting;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Validation\ValidationException;

/**
 * POS-1 .. POS-8 — the point of sale and invoices (web: InvoiceController).
 *
 * The web page computes every total in the browser and the controller stores
 * what it is sent. Here the server computes the numbers itself with the same
 * formulas (docs/API_PLAN.md Section 6), so an honest user gets exactly the
 * web's result and nobody can post a different total.
 */
class PosService
{
    /** the web's stand-in address for a guest invoice: never emailed */
    public const PLACEHOLDER_EMAIL = 'info@bluecrownbarbers.com';

    // ------------------------------------------------------------------ catalog

    /** web: InvoiceController::create (services by category, products, staff, GST, payment methods) */
    public function catalog(User $user): array
    {
        $hideCommission = $user->isStaffUser();   // plan: commission rates are not for staff

        $categories = ServiceCategory::with(['services' => fn ($q) => $q->where('status', 1)->orderBy('service_name')])
            ->orderBy('category_name')->get()
            ->map(fn ($c) => [
                'id' => (int) $c->id,
                'name' => $c->category_name,
                'services' => $c->services->map(fn ($s) => array_filter([
                    'id' => (int) $s->id,
                    'name' => $s->service_name,
                    'price' => Money::str($s->price),
                    'duration' => (int) $s->duration,
                    'tip_eligible' => (int) $s->tip_status === 1,
                    'commission_percent' => $hideCommission ? null : Money::str($s->commission ?? 0),
                ], fn ($v) => $v !== null))->values()->all(),
            ])->filter(fn ($c) => count($c['services']) > 0)->values()->all();

        $products = Product::where('status', 1)->orderBy('product_name')->get()
            ->map(fn ($p) => array_filter([
                'id' => (int) $p->id,
                'name' => $p->product_name,
                'price' => Money::str($p->price),
                'stock' => (int) $p->stock,
                'commission_percent' => $hideCommission ? null : Money::str($p->commission ?? 0),
            ], fn ($v) => $v !== null))->all();

        $gst = Gst::where('default_status', 1)->first();

        return [
            'categories' => $categories,
            'products' => $products,
            'staff' => $this->posStaff()->map(fn ($u) => ['id' => (int) $u->id, 'name' => $u->name])->all(),
            'gst' => $gst ? [
                'id' => (int) $gst->id,
                'name' => $gst->name,
                'rate' => Money::str($gst->rate),
                'tax_type' => strtolower((string) $gst->tax_type) === 'exclude' ? 'exclude' : 'include',
            ] : null,
            'payment_methods' => PaymentMethod::orderBy('id')->get()->map(fn ($m) => ['id' => (int) $m->id, 'name' => $m->name])->all(),
            'default_payment_method' => 'Cash',
        ];
    }

    private function posStaff()
    {
        return User::where('role', 'Staff')->where('active_status', 1)->orderBy('name')->get();
    }

    /** web: InvoiceController::getCustomerDetails (phone lookup on the customer step) */
    public function lookup(User $user, string $phone): array
    {
        $isStaff = $user->isStaffUser();

        $customers = Customer::withCount(['invoicedAppointments as appointments_count'])
            ->withSum(['invoicedAppointments as appointments_sum_total_amt'], 'total_amt')
            ->with(['invoicedAppointments' => fn ($q) => $q->with(['services.service'])->orderByDesc('appointment_id')])
            ->with(['appointments' => fn ($q) => $q->with(['services.service'])->whereHas('services')->orderByDesc('appointment_id')->limit(1)])
            ->where('customer_phone', $phone)
            ->get();

        return $customers->map(function ($c) use ($isStaff) {
            $last = $c->invoicedAppointments->first() ?? $c->appointments->first();
            $names = $last
                ? $last->services->map(fn ($r) => optional($r->service)->service_name)->filter()->unique()->values()->all()
                : [];

            return CustomerService::present($c) + [
                'visits' => (int) $c->appointments_count,
                'total_spend' => $isStaff ? null : Money::str($c->appointments_sum_total_amt ?? 0),   // web hides spend from staff
                'last_services' => $names,
                'last_service' => $names ? implode(', ', $names) : '—',
            ];
        })->all();
    }

    // ------------------------------------------------------------------ the money

    /**
     * Validates a cart and computes every figure the way create-invoice.blade.php does.
     *
     * @param array $in items[{type,id,staff_id,qty}], service_discount, product_discount, tip
     * @return array{units: array, totals: array}
     */
    public function calculate(array $in): array
    {
        $serviceIds = collect($in['items'])->where('type', 'service')->pluck('id')->unique()->all();
        $productIds = collect($in['items'])->where('type', 'product')->pluck('id')->unique()->all();
        $services = Service::whereIn('id', $serviceIds)->where('status', 1)->get()->keyBy('id');
        $products = Product::whereIn('id', $productIds)->where('status', 1)->get()->keyBy('id');
        $staffIds = $this->posStaff()->pluck('id')->all();

        $errors = [];
        $units = [];
        foreach ($in['items'] as $i => $item) {
            $isService = $item['type'] === 'service';
            $model = $isService ? $services->get($item['id']) : $products->get($item['id']);
            if (!$model) {
                $errors["items.$i.id"] = ($isService ? 'Service' : 'Product') . ' not found or not active.';
                continue;
            }
            if (!in_array((int) $item['staff_id'], $staffIds, true)) {
                $errors["items.$i.staff_id"] = 'Staff member not found or not active.';
                continue;
            }
            for ($n = 0; $n < $item['qty']; $n++) {
                $units[] = [
                    'flag' => $isService ? 'S' : 'P',
                    'id' => (int) $item['id'],
                    'staff_id' => (int) $item['staff_id'],
                    'name' => $isService ? $model->service_name : $model->product_name,
                    'price' => (float) $model->price,
                    'model' => $model,
                ];
            }
        }
        if ($errors) {
            throw ValidationException::withMessages($errors);
        }

        $serviceTotal = $productTotal = 0.0;
        foreach ($units as $u) {
            $u['flag'] === 'S' ? $serviceTotal += $u['price'] : $productTotal += $u['price'];
        }

        $sPct = (float) ($in['service_discount'] ?? 0);
        $pPct = (float) ($in['product_discount'] ?? 0);
        $sDisc = $serviceTotal * $sPct / 100;
        $pDisc = $productTotal * $pPct / 100;
        $discounted = ($serviceTotal - $sDisc) + ($productTotal - $pDisc);

        $gst = Gst::where('default_status', 1)->first();
        $rate = $gst ? (float) $gst->rate : 0.0;
        $exclude = $gst && strtolower((string) $gst->tax_type) === 'exclude';
        $tax = 0.0;
        if ($rate && $discounted > 0) {
            $tax = $exclude ? ($discounted * $rate) / 100 : ($discounted * $rate) / (100 + $rate);
        }
        $tip = (float) ($in['tip'] ?? 0);
        $final = $exclude ? $discounted + $tax + $tip : $discounted + $tip;

        return [
            'units' => $units,
            'totals' => [
                'service_total' => round($serviceTotal, 2),
                'product_total' => round($productTotal, 2),
                'service_discount_percent' => $sPct,
                'product_discount_percent' => $pPct,
                'service_discount_amount' => round($sDisc, 2),
                'product_discount_amount' => round($pDisc, 2),
                'total_discount' => round(round($sDisc, 2) + round($pDisc, 2), 2),
                'subtotal' => round($discounted, 2),
                'tax' => round($tax, 2),
                'tax_rate' => $rate,
                'tax_type' => $exclude ? 'exclude' : 'include',
                'tip' => round($tip, 2),
                'final_total' => round($final, 2),
            ],
        ];
    }

    /** the preview the app shows while the cart is being built */
    public function preview(array $in): array
    {
        $calc = $this->calculate($in);
        $t = $calc['totals'];

        return [
            'lines' => array_map(fn ($u) => [
                'type' => $u['flag'] === 'S' ? 'service' : 'product',
                'id' => $u['id'],
                'name' => $u['name'],
                'staff_id' => $u['staff_id'],
                'price' => Money::str($u['price']),
            ], $calc['units']),
            'totals' => [
                'service_total' => Money::str($t['service_total']),
                'service_discount_percent' => Money::str($t['service_discount_percent']),
                'service_discount_amount' => Money::str($t['service_discount_amount']),
                'product_total' => Money::str($t['product_total']),
                'product_discount_percent' => Money::str($t['product_discount_percent']),
                'product_discount_amount' => Money::str($t['product_discount_amount']),
                'total_discount' => Money::str($t['total_discount']),
                'subtotal' => Money::str($t['subtotal']),
                'tax' => Money::str($t['tax']),
                'tax_rate' => Money::str($t['tax_rate']),
                'tax_type' => $t['tax_type'],
                'tip' => Money::str($t['tip']),
                'final_total' => Money::str($t['final_total']),
            ],
        ];
    }

    // ------------------------------------------------------------------ write

    /** web: InvoiceController::store — a brand-new completed invoice dated now */
    public function create(User $user, array $in): Appointment
    {
        $calc = $this->calculate($in);

        return DB::transaction(function () use ($user, $in, $calc) {
            $customer = $this->resolveCustomer($in['customer'] ?? []);
            $now = Carbon::now();

            $appointment = Appointment::create($this->header($in, $calc['totals'], $customer, $now) + [
                'invoice_created_by' => $user->id,
                'invoice_number' => $this->uniqueInvoiceNumber($now),
            ]);

            $this->writeLines($appointment->appointment_id, $calc);

            return $appointment;
        });
    }

    /**
     * web: InvoiceController::update — replaces the lines, keeps the invoice
     * number and the creator, stamps date/time = now.
     *
     * @return Appointment|null null when the user cannot see that invoice
     */
    public function update(User $user, int $id, array $in): ?Appointment
    {
        $calc = $this->calculate($in);

        return DB::transaction(function () use ($user, $id, $in, $calc) {
            $appointment = $this->visible($user)->where('appointment_id', $id)->lockForUpdate()->first();
            if (!$appointment) {
                return null;
            }

            $customer = $this->resolveCustomer($in['customer'] ?? []);
            $now = Carbon::now();

            $appointment->update($this->header($in, $calc['totals'], $customer, $now) + [
                'invoice_number' => $appointment->invoice_number ?? $this->uniqueInvoiceNumber($now),
            ]);

            AppointmentProduct::where('appointment_id', $id)->delete();
            AppointmentService::where('appointment_id', $id)->delete();
            $this->writeLines($id, $calc);

            return $appointment;
        });
    }


    /**
     * APPT-11 (feature flag `complete_from_appointment`, OFF): turns a booked appointment
     * into a paid invoice. The web's Complete button cannot do this today (Q5).
     *
     * @return array{0:int,1:string,2:?int} [http, message, appointment id]
     */
    public function complete(User $user, int $id, array $in): array
    {
        $calc = $this->calculate($in);

        return DB::transaction(function () use ($user, $id, $in, $calc) {
            $a = Appointment::where('appointment_id', $id)->lockForUpdate()->first();
            $ownLine = fn () => AppointmentService::where('appointment_id', $id)->where('staff_id', $user->id)->exists();
            if (!$a || ($user->isStaffUser() && !$ownLine())) {
                return [404, 'Appointment not found.', null];
            }
            if ($a->is_invoiced == 1 || !in_array((int) $a->status, [0, 3, 4], true)) {
                return [409, 'Only a pending, confirmed or rescheduled appointment that is not invoiced yet can be completed.', null];
            }

            $customer = !empty($in['customer']) && array_filter($in['customer'])
                ? $this->resolveCustomer($in['customer'])
                : Customer::find($a->customer_id) ?? $this->resolveCustomer([]);
            $now = Carbon::now();

            $a->update($this->header($in, $calc['totals'], $customer, $now) + [
                'invoice_created_by' => $user->id,
                'invoice_number' => $this->uniqueInvoiceNumber($now),
            ]);
            AppointmentProduct::where('appointment_id', $id)->delete();
            AppointmentService::where('appointment_id', $id)->delete();
            $this->writeLines($id, $calc);

            return [200, 'Appointment completed and invoiced.', $id];
        });
    }

    private function header(array $in, array $t, Customer $customer, Carbon $now): array
    {
        return [
            'date' => $now->toDateString(),
            'customer_id' => $customer->customer_id,
            'slot_start' => $now->format('H:i:s'),
            'slot_end' => $now->format('H:i:s'),
            'name' => $customer->customer_name,
            'email' => $customer->customer_email,
            'phone' => $customer->customer_phone,
            'notes' => $in['notes'] ?? null,
            'status' => 1,
            'is_invoiced' => 1,
            'payment_method' => $in['payment_method'] ?? 'Cash',
            'total_amt' => $t['final_total'],
            'total_discount' => $t['total_discount'],
            'discount_type' => 1,
            'total_tax' => $t['tax'],
            'total_tip' => $t['tip'],
            'service_discount' => $t['service_discount_percent'],
            'product_discount' => $t['product_discount_percent'],
        ];
    }

    /** service rows and product rows, commissions and tips as the web stores them */
    private function writeLines(int $appointmentId, array $calc): void
    {
        $t = $calc['totals'];
        $fee = (float) (Setting::where('id', 1)->value('service_fee') ?? 0);
        $tips = $this->splitTip($calc['units'], $t['tip']);

        foreach ($calc['units'] as $idx => $u) {
            if ($u['flag'] === 'S') {
                $base = $t['service_discount_percent'] > 0
                    ? $u['price'] - ($u['price'] * $t['service_discount_percent']) / 100
                    : $u['price'];
                $commission = (max(0, $base - $fee) * (float) ($u['model']->commission ?? 0)) / 100;

                AppointmentService::create([
                    'appointment_id' => $appointmentId,
                    'service_id' => $u['id'],
                    'staff_id' => $u['staff_id'],
                    'product_commission' => 0,
                    'service_commission' => number_format($commission, 2, '.', ''),
                    'service_tip' => $tips[$idx] ?? 0,
                    'total_amt' => $u['price'],
                    'status' => 1,
                    'comment' => 'Invoicing By POS',
                ]);
            } else {
                $base = $t['product_discount_percent'] > 0
                    ? $u['price'] - ($u['price'] * $t['product_discount_percent']) / 100
                    : $u['price'];

                AppointmentProduct::create([
                    'appointment_id' => $appointmentId,
                    'product_id' => $u['id'],
                    'staff_id' => $u['staff_id'],
                    'qty' => 1,
                    'amount' => $u['price'],
                    'product_commision' => round(($base * (float) ($u['model']->commission ?? 0)) / 100, 2),
                ]);
            }
        }
    }

    /**
     * Tip per service unit: shared by tip-eligible services, or by every service
     * when none is eligible (web rule). Done in cents so the parts add up to the
     * tip exactly (the web stores 1.6666666667 style values).
     *
     * @return array<int,string> unit index => "x.yy"
     */
    private function splitTip(array $units, float $tip): array
    {
        $service = $eligible = [];
        foreach ($units as $idx => $u) {
            if ($u['flag'] !== 'S') {
                continue;
            }
            $service[] = $idx;
            if ((int) $u['model']->tip_status === 1) {
                $eligible[] = $idx;
            }
        }
        $targets = $eligible ?: $service;
        if (!$targets) {
            return [];
        }

        $cents = (int) round($tip * 100);
        $each = intdiv($cents, count($targets));
        $rest = $cents - $each * count($targets);
        $out = [];
        foreach ($targets as $n => $idx) {
            $out[$idx] = number_format(($each + ($n < $rest ? 1 : 0)) / 100, 2, '.', '');
        }

        return $out;
    }

    /** web: customer by phone, else the Guest placeholder, else a new customer */
    private function resolveCustomer(array $c): Customer
    {
        $name = $c['name'] ?? null;
        $phone = $c['phone'] ?? null;
        $email = $c['email'] ?? null;

        $existing = Customer::where('customer_phone', $phone)->first();
        if ($existing) {
            return $existing;
        }

        if (empty($name) && empty($phone) && empty($email)) {
            $guest = [
                'customer_name' => 'Guest Customer',
                'customer_phone' => '(555) 123-4567',
                'customer_email' => self::PLACEHOLDER_EMAIL,
                'customer_status' => 1,
            ];

            return Customer::where('customer_phone', $guest['customer_phone'])
                ->where('customer_email', $guest['customer_email'])->first()
                ?? Customer::create($guest);
        }

        return Customer::create([
            'customer_name' => $name ?? 'Guest Customer',
            'customer_phone' => $phone ?? '(555) 123-4567',
            'customer_email' => $email ?? self::PLACEHOLDER_EMAIL,
            'customer_status' => 1,
        ]);
    }

    private function uniqueInvoiceNumber(Carbon $now): string
    {
        $datePart = $now->format('Ymd');
        for ($i = 0; $i < 50; $i++) {
            $number = 'INV-' . $datePart . '-' . str_pad((string) random_int(0, 9999), 4, '0', STR_PAD_LEFT);
            if (!Appointment::where('invoice_number', $number)->exists()) {
                return $number;
            }
        }

        return 'INV-' . $datePart . '-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 6));
    }

    // ------------------------------------------------------------------ read

    /** web: invoicesVisibleToCurrentUser */
    public function visible(User $user): Builder
    {
        $q = Appointment::where('is_invoiced', 1);
        if ($user->isStaffUser() && !$user->can('Pos_invoice-Show_All')) {
            $q->where('invoice_created_by', $user->getKey());
        }

        return $q;
    }

    /** @return array{0: array, 1: int} */
    public function paginate(User $user, array $f, int $page, int $perPage): array
    {
        $q = $this->visible($user)->with(['customer', 'serviceStaff', 'productStaff'])
            ->when(!empty($f['start_date']), fn ($w) => $w->whereDate('date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($w) => $w->whereDate('date', '<=', $f['end_date']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($s) => $s->where('invoice_number', 'like', $like)
                    ->orWhere('name', 'like', $like)->orWhere('phone', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->orderByDesc('appointment_id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($a) => $this->row($user, $a))->all(), $total];
    }

    private function row(User $user, Appointment $a): array
    {
        return [
            'id' => (int) $a->appointment_id,
            'invoice_number' => $a->invoice_number,
            'customer' => ['id' => $a->customer ? (int) $a->customer->customer_id : null, 'name' => optional($a->customer)->customer_name, 'phone' => $a->phone, 'email' => $a->email],
            'staff_names' => $a->staff_names,
            'date' => $a->date,
            'invoiced_at' => optional($a->updated_at)->format('Y-m-d H:i:s'),
            'payment_method' => $a->payment_method,
            'total' => Money::str($a->total_amt),
            'status_label' => 'Paid',
            'can_edit' => $user->can('Pos_invoice-Edit'),
        ];
    }

    /** POS-5: everything on the invoice plus the cart in the shape POST/PUT accepts */
    public function detail(User $user, int $id): ?array
    {
        $a = $this->visible($user)->with(['customer', 'services.service', 'services.staff', 'products.product', 'products.staff'])
            ->where('appointment_id', $id)->first();
        if (!$a) {
            return null;
        }

        $hideCommission = $user->isStaffUser();
        $lines = [];
        foreach ($a->services as $s) {
            $lines[] = array_filter([
                'type' => 'service',
                'id' => (int) $s->service_id,
                'name' => optional($s->service)->service_name,
                'staff_id' => (int) $s->staff_id,
                'staff_name' => optional($s->staff)->name,
                'price' => Money::str($s->total_amt),
                'tip' => Money::str($s->service_tip),
                'commission' => $hideCommission ? null : Money::str($s->service_commission),
            ], fn ($v) => $v !== null);
        }
        foreach ($a->products as $p) {
            $lines[] = array_filter([
                'type' => 'product',
                'id' => (int) $p->product_id,
                'name' => optional($p->product)->product_name,
                'staff_id' => (int) $p->staff_id,
                'staff_name' => optional($p->staff)->name,
                'price' => Money::str($p->amount),
                'tip' => null,
                'commission' => $hideCommission ? null : Money::str($p->product_commision),
            ], fn ($v) => $v !== null);
        }

        // web edit page: services one unit each, products grouped by product + staff
        $items = [];
        foreach ($a->services as $s) {
            $key = 'service:' . $s->service_id . ':' . $s->staff_id;
            $items[$key]['type'] = 'service';
            $items[$key]['id'] = (int) $s->service_id;
            $items[$key]['staff_id'] = (int) $s->staff_id;
            $items[$key]['qty'] = ($items[$key]['qty'] ?? 0) + 1;
        }
        foreach ($a->products as $p) {
            $key = 'product:' . $p->product_id . ':' . $p->staff_id;
            $items[$key]['type'] = 'product';
            $items[$key]['id'] = (int) $p->product_id;
            $items[$key]['staff_id'] = (int) $p->staff_id;
            $items[$key]['qty'] = ($items[$key]['qty'] ?? 0) + max(1, (int) ($p->qty ?? 1));
        }

        $serviceTotal = $a->services->sum(fn ($s) => (float) $s->total_amt);
        $productTotal = $a->products->sum(fn ($p) => (float) $p->amount);

        return $this->row($user, $a) + [
            'notes' => $a->notes,
            'created_by' => $a->invoice_created_by ? (int) $a->invoice_created_by : null,
            'lines' => $lines,
            'cart' => array_values($items),
            'breakdown' => [
                'service_total' => Money::str($serviceTotal),
                'service_discount_percent' => Money::str($a->service_discount ?? 0),
                'product_total' => Money::str($productTotal),
                'product_discount_percent' => Money::str($a->product_discount ?? 0),
                'total_discount' => Money::str($a->total_discount ?? 0),
                'tax' => Money::str($a->total_tax ?? 0),
                'tip' => Money::str($a->total_tip ?? 0),
                'total' => Money::str($a->total_amt ?? 0),
            ],
        ];
    }

    // ------------------------------------------------------------------ mail

    /**
     * POS-7. Returns an error message, or null when the mail was handed to the mailer.
     * The web silently does nothing for the placeholder address; the API says so.
     */
    public function sendEmail(User $user, int $id, ?string $override): array
    {
        $a = $this->visible($user)->with(['serviceStaff', 'productStaff', 'services.service', 'products.product'])
            ->where('appointment_id', $id)->first();
        if (!$a) {
            return [404, 'Invoice not found.'];
        }

        $to = trim((string) ($override ?: optional($a->customer)->customer_email));
        if ($to === '' || strcasecmp($to, self::PLACEHOLDER_EMAIL) === 0) {
            return [422, 'This invoice has no real customer email address.'];
        }

        try {
            Mail::to($to)->send(new invoiceMail(collect([$a])));
        } catch (\Throwable $e) {
            Log::error('Invoice email failed: ' . $e->getMessage(), ['invoice' => $id]);

            return [502, 'The email could not be sent. Please try again later.'];
        }

        return [200, 'Mail Successfully Send'];
    }

    /** web: store/update send the invoice to the customer when Setting.invoice_send_sts = 1; here after the commit and never fatal */
    public function mailAfterSave(int $id): void
    {
        if ((int) Setting::where('id', 1)->value('invoice_send_sts') !== 1) {
            return;
        }

        $a = Appointment::with(['serviceStaff', 'productStaff', 'services.service', 'products.product'])->where('appointment_id', $id)->first();
        $to = trim((string) optional($a)->email);
        if (!$a || $to === '' || strcasecmp($to, self::PLACEHOLDER_EMAIL) === 0) {
            return;
        }

        try {
            Mail::to($to)->send(new invoiceMail(collect([$a])));
        } catch (\Throwable $e) {
            Log::error('Invoice email after save failed: ' . $e->getMessage(), ['invoice' => $id]);
        }
    }
}
