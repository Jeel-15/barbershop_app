<?php

namespace App\Services\Api;

use App\Models\Appointment;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * RPT-1 .. RPT-6 — the admin reports (web: ReportController). The queries are the
 * web's, quirks included (docs/API_PLAN.md Q46..Q49); summaries come back in
 * `meta.summary`.
 */
class ReportAdmin
{
    // ------------------------------------------------------------------ RPT-1 appointments

    /** @return array{0: array, 1: int, 2: array} rows, total, summary */
    public function appointments(array $f, int $page, int $perPage): array
    {
        $base = DB::table('tbl_appointment as a')
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->leftJoin('tbl_appointment_service as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->leftJoin('users as u', 'b.staff_id', '=', 'u.id')
            ->where('a.is_invoiced', 1)->where('a.status', 1)
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->when(!empty($f['staff_id']), fn ($q) => $q->where('b.staff_id', $f['staff_id']))
            ->when(!empty($f['q']), function ($q) use ($f) {
                $like = '%' . $f['q'] . '%';
                $q->where(fn ($s) => $s->where('u.name', 'like', $like)->orWhere('c.customer_name', 'like', $like)
                    ->orWhere('c.customer_phone', 'like', $like)->orWhere('a.date', 'like', $like)->orWhere('a.invoice_number', 'like', $like));
            });

        $total = (int) (clone $base)->distinct()->count('a.appointment_id');

        $rows = (clone $base)->select(
            'a.appointment_id', 'a.invoice_number', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status', 'c.customer_name', 'c.customer_phone',
            DB::raw('GROUP_CONCAT(DISTINCT u.name SEPARATOR ", ") as staff_names'),
            'a.total_discount', 'a.total_tax', 'a.total_amt', 'a.total_tip'
        )->groupBy('a.appointment_id', 'a.invoice_number', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status', 'c.customer_name', 'c.customer_phone', 'a.total_discount', 'a.total_tax', 'a.total_amt', 'a.total_tip')
            ->orderByDesc('a.date')->orderByDesc('a.appointment_id')->forPage($page, $perPage)->get();

        $items = $rows->map(fn ($r) => [
            'id' => (int) $r->appointment_id,
            'invoice_number' => $r->invoice_number,
            'date' => $r->date,
            'start_label' => AppointmentReader::timeLabel($r->slot_start),
            'end_label' => AppointmentReader::timeLabel($r->slot_end),
            'customer' => ['name' => $r->customer_name, 'phone' => $r->customer_phone],
            'staff_names' => $r->staff_names ?? '',
            'discount' => Money::str($r->total_discount),
            'sub_total' => Money::str($r->total_amt - $r->total_tip - $r->total_tax),
            'tax' => Money::str($r->total_tax),
            'tip' => Money::str($r->total_tip),
            'total' => Money::str($r->total_amt),
        ])->all();

        $s = $this->summary($f);

        return [$items, $total, [
            'total_revenue' => Money::str($s->total_revenue ?? 0),
            'total_appointments' => (int) ($s->total_appointments ?? 0),
            'total_visits' => (int) ($s->total_visits ?? 0),
            'total_tips' => Money::str($s->total_tips ?? 0),
            'total_discount' => Money::str($s->total_discount ?? 0),
            'staff_total_service_tip' => Money::str($s->total_service_tip ?? 0),
            'staff_total_service_commission' => Money::str($s->total_service_commission ?? 0),
            'staff_total_product_commission' => Money::str($s->total_product_commission ?? 0),
            'staff_total_earning' => Money::str($s->total_earning ?? 0),
        ]];
    }

    /** web summary used by RPT-1 and RPT-2: completed appointments (status 1) in the dates, staff parts by the staff filter */
    private function summary(array $f)
    {
        $serviceSub = DB::table('tbl_appointment_service as s')
            ->select('s.appointment_id', DB::raw('SUM(s.total_amt) as total_service_amount'), DB::raw('SUM(s.service_commission) as total_service_commission'), DB::raw('SUM(s.service_tip) as total_service_tip'))
            ->when(!empty($f['staff_id']), fn ($q) => $q->where('s.staff_id', $f['staff_id']))->groupBy('s.appointment_id');
        $productSub = DB::table('tbl_appointment_product as p')
            ->select('p.appointment_id', DB::raw('SUM(p.amount) as total_product_amount'), DB::raw('SUM(p.product_commision) as total_product_commission'))
            ->when(!empty($f['staff_id']), fn ($q) => $q->where('p.staff_id', $f['staff_id']))->groupBy('p.appointment_id');

        return DB::table('tbl_appointment as a')
            ->leftJoinSub($serviceSub, 's', fn ($j) => $j->on('a.appointment_id', '=', 's.appointment_id'))
            ->leftJoinSub($productSub, 'p', fn ($j) => $j->on('a.appointment_id', '=', 'p.appointment_id'))
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->where('a.status', 1)
            ->selectRaw('
                SUM(a.total_amt - a.total_tax - a.total_tip) as total_revenue,
                COUNT(DISTINCT a.appointment_id) as total_appointments,
                COUNT(DISTINCT a.customer_id) as total_visits,
                SUM(a.total_tip) as total_tips,
                SUM(a.total_discount) as total_discount,
                COALESCE(SUM(s.total_service_tip),0) as total_service_tip,
                COALESCE(SUM(s.total_service_commission),0) as total_service_commission,
                COALESCE(SUM(p.total_product_commission),0) as total_product_commission,
                (COALESCE(SUM(s.total_service_tip),0) + COALESCE(SUM(s.total_service_commission),0) + COALESCE(SUM(p.total_product_commission),0)) as total_earning
            ')->first();
    }

    // ------------------------------------------------------------------ RPT-2 payments

    public function payments(array $f): array
    {
        // web: left join + "a.status = 1" makes it an inner join; the staff filter is not applied to the rows
        $rows = DB::table('tbl_payment_method as pm')
            ->leftJoin('tbl_appointment as a', 'pm.name', '=', 'a.payment_method')
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->where('a.status', 1)
            ->select('pm.name as method', DB::raw('IFNULL(SUM(a.total_amt - a.total_tax - a.total_tip), 0) as revenue'))
            ->groupBy('pm.id', 'pm.name')->orderByDesc('revenue')->orderBy('pm.name')->get();

        $s = $this->summary($f);

        return [
            $rows->map(fn ($r) => ['method' => $r->method, 'revenue' => Money::str($r->revenue)])->all(),
            ['total_revenue' => Money::str($s->total_revenue ?? 0), 'total_discount' => Money::str($s->total_discount ?? 0)],
        ];
    }

    // ------------------------------------------------------------------ RPT-3 staff earnings

    /** web quirk Q46: the rows ignore the end date (the start date filter is written twice); the summary honours both */
    public function staffEarnings(array $f): array
    {
        $rows = DB::table('tbl_appointment as a')
            ->where('a.is_invoiced', 1)
            ->leftJoin('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
            ->leftJoin('tbl_appointment_product as p', function ($join) {
                $join->on('a.appointment_id', '=', 'p.appointment_id')->on('s.staff_id', '=', 'p.staff_id');
            })
            ->leftJoin('users as st', 's.staff_id', '=', 'st.id')
            ->where('a.status', 1)
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['staff_id']), fn ($q) => $q->where('s.staff_id', $f['staff_id']))
            ->select(
                'st.id as staff_id', 'st.name as staff_name',
                DB::raw('COUNT(DISTINCT a.appointment_id) as appointments'),
                DB::raw('COALESCE(SUM(s.total_amt),0) as revenue'),
                DB::raw('COALESCE(SUM(s.service_tip),0) as tips'),
                DB::raw('COALESCE(SUM(s.service_commission),0) as service_commission'),
                DB::raw('COALESCE(SUM(DISTINCT p.product_commision),0) as product_commission')
            )->groupBy('s.staff_id', 'st.id', 'st.name')->orderByDesc('revenue')->orderBy('st.id')->get();

        $s = DB::table('tbl_appointment as a')
            ->where('a.is_invoiced', 1)
            ->leftJoin('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
            ->leftJoin('tbl_appointment_product as p', 'a.appointment_id', '=', 'p.appointment_id')
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->where('a.status', 1)
            ->when(!empty($f['staff_id']), fn ($q) => $q->where('s.staff_id', $f['staff_id']))
            ->selectRaw('
                COALESCE(SUM(DISTINCT s.service_commission),0) as total_service_commission,
                COALESCE(SUM(DISTINCT s.service_tip),0) as total_service_tip,
                COALESCE(SUM(DISTINCT p.product_commision),0) as total_product_commission,
                COALESCE(SUM(DISTINCT a.total_amt),0) as totalRevenue,
                COUNT(DISTINCT a.appointment_id) as appointmentCount
            ')->first();

        return [
            $rows->map(fn ($r) => [
                'staff_id' => $r->staff_id === null ? null : (int) $r->staff_id,
                'staff_name' => $r->staff_name,
                'appointments' => (int) $r->appointments,
                'revenue' => Money::str($r->revenue),
                'tips' => Money::str($r->tips),
                'service_commission' => Money::str($r->service_commission),
                'product_commission' => Money::str($r->product_commission),
                'total_earning' => Money::str($r->tips + $r->service_commission + $r->product_commission),
            ])->all(),
            [
                'total_service_commission' => Money::str($s->total_service_commission ?? 0),
                'total_service_tip' => Money::str($s->total_service_tip ?? 0),
                'total_product_commission' => Money::str($s->total_product_commission ?? 0),
                'total_revenue' => Money::str($s->totalRevenue ?? 0),
                'appointment_count' => (int) ($s->appointmentCount ?? 0),
            ],
        ];
    }

    // ------------------------------------------------------------------ RPT-4 customer invoices

    /** @return array{0: array, 1: int} */
    public function customerInvoices(array $f, int $page, int $perPage): array
    {
        $q = Appointment::where('is_invoiced', 1)
            ->when(!empty($f['start_date']), fn ($w) => $w->whereDate('date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($w) => $w->whereDate('date', '<=', $f['end_date']))
            ->when(!empty($f['staff_id']), function ($w) use ($f) {
                $w->where(fn ($x) => $x->whereHas('services', fn ($s) => $s->where('staff_id', $f['staff_id']))
                    ->orWhereHas('products', fn ($p) => $p->where('staff_id', $f['staff_id'])));
            })
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($x) => $x->where('invoice_number', 'like', $like)->orWhere('name', 'like', $like)->orWhere('phone', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->with(['customer', 'services.staff:id,name', 'products.staff:id,name'])->orderByDesc('appointment_id')->forPage($page, $perPage)->get();

        return [$rows->map(function ($a) {
            $names = collect($a->services)->pluck('staff.name')->merge(collect($a->products)->pluck('staff.name'))->filter()->unique()->implode(', ');
            // web "Amount" column: what the staff earned on the invoice (commission + tips), not the invoice total (Q47)
            $earned = collect($a->services)->sum(fn ($s) => $s->service_commission + $s->service_tip) + collect($a->products)->sum('product_commision');

            return [
                'id' => (int) $a->appointment_id,
                'invoice_number' => $a->invoice_number,
                'date' => $a->date,
                'customer_name' => optional($a->customer)->customer_name ?? '-',
                'staff_names' => $names ?: '-',
                'amount' => Money::str($earned),
                'total' => Money::str($a->total_amt),
                'status_label' => 'Paid',
            ];
        })->all(), $total];
    }

    // ------------------------------------------------------------------ RPT-5 / RPT-6 products

    /** @return array{0: array, 1: int} */
    public function productSales(array $f, int $page, int $perPage): array
    {
        $q = DB::table('tbl_appointment_product as ap')
            ->join('tbl_product as p', 'ap.product_id', '=', 'p.id')
            ->join('tbl_appointment as a', 'ap.appointment_id', '=', 'a.appointment_id')
            ->join('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->leftJoin('users as u', 'ap.staff_id', '=', 'u.id')
            ->when(!empty($f['start_date']), fn ($w) => $w->whereDate('ap.created_at', '>=', Carbon::parse($f['start_date'])->toDateString()))
            ->when(!empty($f['end_date']), fn ($w) => $w->whereDate('ap.created_at', '<=', Carbon::parse($f['end_date'])->toDateString()))
            ->when(!empty($f['staff_id']), fn ($w) => $w->where('ap.staff_id', $f['staff_id']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($x) => $x->where('p.product_name', 'like', $like)->orWhere('c.customer_name', 'like', $like)->orWhere('u.name', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->select('ap.id', 'p.product_name', 'c.customer_name', 'u.name as staff_name', 'ap.created_at as sell_date', 'ap.amount')
            ->orderByDesc('ap.id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($r) => [
            'id' => (int) $r->id,
            'product_name' => $r->product_name,
            'customer_name' => $r->customer_name,
            'staff_name' => $r->staff_name,
            'sell_date' => Carbon::parse($r->sell_date)->toDateString(),
            'amount' => Money::str($r->amount),
        ])->all(), $total];
    }

    /** web quirk Q48: grouped by product AND the invoice's product discount, so one product can appear on several rows */
    public function topProducts(array $f): array
    {
        $rows = DB::table('tbl_appointment_product as ap')
            ->join('tbl_product as p', 'ap.product_id', '=', 'p.id')
            ->join('tbl_appointment as a', 'ap.appointment_id', '=', 'a.appointment_id')
            ->join('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->leftJoin('users as u', 'ap.staff_id', '=', 'u.id')
            ->select(
                'p.id as product_id', 'p.product_name', 'p.price as product_price',
                DB::raw('SUM(ap.qty) as sell_unit'),
                DB::raw('SUM(ap.product_commision) as total_commission'),
                DB::raw('((SUM(ap.amount) - SUM(ap.product_commision)) - ((SUM(ap.amount) - SUM(ap.product_commision)) * (a.product_discount / 100))) as total_revenue'),
                DB::raw('((SUM(ap.amount) - SUM(ap.product_commision)) * (a.product_discount / 100)) as total_discount')
            )
            ->when(!empty($f['start_date']), fn ($w) => $w->whereDate('ap.created_at', '>=', Carbon::parse($f['start_date'])->toDateString()))
            ->when(!empty($f['end_date']), fn ($w) => $w->whereDate('ap.created_at', '<=', Carbon::parse($f['end_date'])->toDateString()))
            ->when(!empty($f['staff_id']), fn ($w) => $w->where('ap.staff_id', $f['staff_id']))
            ->groupBy('p.id', 'p.product_name', 'p.price', 'a.product_discount')
            ->orderByDesc('total_revenue')->orderBy('p.id')->get();

        $s = DB::table('tbl_appointment_product as ap')
            ->join('tbl_product as p', 'ap.product_id', '=', 'p.id')
            ->join('tbl_appointment as a', 'ap.appointment_id', '=', 'a.appointment_id')
            ->when(!empty($f['staff_id']), fn ($w) => $w->where('ap.staff_id', $f['staff_id']))
            ->when(!empty($f['start_date']), fn ($w) => $w->whereDate('ap.created_at', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($w) => $w->whereDate('ap.created_at', '<=', $f['end_date']))
            ->selectRaw('
                SUM(ap.qty) as total_units_sold,
                SUM(ap.amount) as total_product_amount,
                SUM(ap.product_commision) as total_product_commission,
                SUM((ap.amount - ap.product_commision) - ((ap.amount - ap.product_commision) * (a.product_discount / 100))) as total_revenue,
                SUM(((ap.amount - ap.product_commision) * (a.product_discount / 100))) as total_discount
            ')->first();

        return [
            $rows->map(fn ($r) => [
                'product_id' => (int) $r->product_id,
                'product_name' => $r->product_name,
                'price' => Money::str($r->product_price),
                'units_sold' => (int) $r->sell_unit,
                'commission' => Money::str($r->total_commission),
                'revenue' => Money::str($r->total_revenue),
                'discount' => Money::str($r->total_discount),
            ])->all(),
            [
                'total_revenue' => Money::str($s->total_revenue ?? 0),
                'total_discount' => Money::str($s->total_discount ?? 0),
                'total_commission' => Money::str($s->total_product_commission ?? 0),
                'total_units_sold' => (int) ($s->total_units_sold ?? 0),
                'total_product_amount' => Money::str($s->total_product_amount ?? 0),
            ],
        ];
    }
}
