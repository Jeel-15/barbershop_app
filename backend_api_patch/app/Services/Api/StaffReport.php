<?php

namespace App\Services\Api;

use App\Models\Appointment;
use App\Models\Setting;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * ME-3 .. ME-6 — a staff member's own earnings report (web:
 * StaffreportController). The web page sends the signed-in user's id in its
 * hidden `staff_id` field; the app always uses the signed-in user.
 */
class StaffReport
{
    /** web: the cards above the appointment table + the service fee note */
    public function summary(User $user, array $f): array
    {
        $staffId = $user->id;

        $serviceSub = DB::table('tbl_appointment_service')
            ->select('appointment_id', DB::raw('SUM(service_tip) as total_service_tip'), DB::raw('SUM(service_commission) as total_service_commission'))
            ->where('staff_id', $staffId)->groupBy('appointment_id');
        $productSub = DB::table('tbl_appointment_product')
            ->select('appointment_id', DB::raw('SUM(product_commision) as total_product_commission'))
            ->where('staff_id', $staffId)->groupBy('appointment_id');

        $s = DB::table('tbl_appointment as a')
            ->leftJoinSub($serviceSub, 's', fn ($j) => $j->on('a.appointment_id', '=', 's.appointment_id'))
            ->leftJoinSub($productSub, 'p', fn ($j) => $j->on('a.appointment_id', '=', 'p.appointment_id'))
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->when(isset($f['status']) && $f['status'] !== '', fn ($q) => $q->where('a.status', $f['status']))
            ->where(fn ($q) => $q->whereNotNull('s.appointment_id')->orWhereNotNull('p.appointment_id'))
            ->selectRaw('
                SUM(a.total_amt) as total_revenue,
                COUNT(DISTINCT a.appointment_id) as total_appointments,
                COUNT(DISTINCT a.customer_id) as total_visits,
                SUM(a.total_tip) as total_tips,
                COALESCE(SUM(s.total_service_tip), 0) as total_service_tip,
                COALESCE(SUM(s.total_service_commission), 0) as total_service_commission,
                COALESCE(SUM(p.total_product_commission), 0) as total_product_commission,
                (COALESCE(SUM(s.total_service_tip), 0) + COALESCE(SUM(s.total_service_commission), 0) + COALESCE(SUM(p.total_product_commission), 0)) as total_earning
            ')
            ->first();

        return [
            'total_revenue' => Money::str($s->total_revenue ?? 0),
            'total_appointments' => (int) ($s->total_appointments ?? 0),
            'total_visits' => (int) ($s->total_visits ?? 0),
            'total_tips' => Money::str($s->total_tips ?? 0),
            'my_tips' => Money::str($s->total_service_tip ?? 0),
            'my_service_commission' => Money::str($s->total_service_commission ?? 0),
            'my_product_commission' => Money::str($s->total_product_commission ?? 0),
            'my_total_earning' => Money::str($s->total_earning ?? 0),
            'service_fee' => Money::str(Setting::where('id', 1)->value('service_fee') ?? 0),
        ];
    }

    /** web: DailyEarningGetTableData — invoiced appointments only, one row per day */
    public function earnings(User $user, int $page, int $perPage): array
    {
        $serviceSub = DB::table('tbl_appointment_service as s')
            ->select('s.appointment_id', DB::raw('SUM(s.service_commission) as total_service_commission'), DB::raw('SUM(s.service_tip) as total_service_tip'))
            ->where('s.staff_id', $user->id)->groupBy('s.appointment_id');
        $productSub = DB::table('tbl_appointment_product as p')
            ->select('p.appointment_id', DB::raw('SUM(p.product_commision) as total_product_commission'))
            ->where('p.staff_id', $user->id)->groupBy('p.appointment_id');

        $rows = DB::table('tbl_appointment as a')
            ->where('a.is_invoiced', 1)
            ->leftJoinSub($serviceSub, 's', fn ($j) => $j->on('a.appointment_id', '=', 's.appointment_id'))
            ->leftJoinSub($productSub, 'p', fn ($j) => $j->on('a.appointment_id', '=', 'p.appointment_id'))
            ->select(
                'a.date',
                DB::raw('SUM(COALESCE(s.total_service_commission,0) + COALESCE(s.total_service_tip,0) + COALESCE(p.total_product_commission,0)) as total_earn'),
                DB::raw('SUM(COALESCE(s.total_service_commission,0)) as service_commission'),
                DB::raw('SUM(COALESCE(s.total_service_tip,0)) as service_tip'),
                DB::raw('SUM(COALESCE(p.total_product_commission,0)) as product_commission')
            )
            ->groupBy('a.date')->orderBy('a.date', 'desc')
            ->get();

        $items = $rows->map(fn ($r) => [
            'date' => $r->date,
            'service_commission' => Money::str($r->service_commission),
            'tips' => Money::str($r->service_tip),
            'product_commission' => Money::str($r->product_commission),
            'total_earning' => Money::str($r->total_earn),
        ])->all();

        return [array_slice($items, ($page - 1) * $perPage, $perPage), count($items)];
    }

    /** web: AssignServicesGetTableData — per service, invoiced appointments only */
    public function services(User $user, int $page, int $perPage): array
    {
        $rows = DB::table('tbl_appointment_service as a')
            ->leftJoin('tbl_appointment as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->leftJoin('tbl_service as c', 'a.service_id', '=', 'c.id')
            ->select(
                'c.service_name', 'c.duration', 'c.price',
                DB::raw('SUM(DISTINCT a.service_commission) as total_service_commission'),
                DB::raw('SUM(DISTINCT a.service_tip) as total_service_tip'),
                DB::raw('COUNT(DISTINCT a.appointment_id) as appointmentCount')
            )
            ->where('a.staff_id', $user->id)
            ->where('b.is_invoiced', 1)
            ->groupBy('a.service_id', 'c.service_name', 'c.duration', 'c.price')
            ->orderByDesc(DB::raw('SUM(DISTINCT b.total_amt)'))->orderBy('c.duration')
            ->get();

        $items = $rows->map(fn ($r) => [
            'service_name' => $r->service_name,
            'duration' => (int) $r->duration,
            'price' => Money::str($r->price),
            'appointment_count' => (int) $r->appointmentCount,
            'commission' => Money::str($r->total_service_commission),
            'tips' => Money::str($r->total_service_tip),
            'total_earning' => Money::str($r->total_service_commission + $r->total_service_tip),   // web: commission + tip
        ])->all();

        return [array_slice($items, ($page - 1) * $perPage, $perPage), count($items)];
    }

    /** web: getAppointmentsTableData (rows only; the cards are in summary()) */
    public function appointments(User $user, array $f, int $page, int $perPage): array
    {
        $base = DB::table('tbl_appointment as a')
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->leftJoin('tbl_appointment_service as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->leftJoin('users as u', 'b.staff_id', '=', 'u.id')
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->when(isset($f['status']) && $f['status'] !== '', fn ($q) => $q->where('a.status', $f['status']))
            ->where('b.staff_id', $user->id);

        if (!empty($f['q'])) {
            $like = '%' . $f['q'] . '%';
            $base->where(fn ($s) => $s->where('c.customer_name', 'like', $like)
                ->orWhere('c.customer_phone', 'like', $like)
                ->orWhere('a.date', 'like', $like));
        }

        $total = (int) (clone $base)->distinct()->count('a.appointment_id');

        $rows = (clone $base)
            ->select(
                'a.appointment_id', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status',
                'c.customer_name', 'c.customer_phone',
                DB::raw('GROUP_CONCAT(DISTINCT u.name SEPARATOR ", ") as staff_names'),
                'a.total_discount', 'a.total_amt', 'a.total_tip'
            )
            ->groupBy('a.appointment_id', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status', 'c.customer_name', 'c.customer_phone', 'a.total_discount', 'a.total_amt', 'a.total_tip')
            ->orderByDesc('a.date')->orderByDesc('a.slot_start')->orderByDesc('a.appointment_id')
            ->forPage($page, $perPage)->get();

        return [$rows->map(fn ($r) => [
            'id' => (int) $r->appointment_id,
            'date' => $r->date,
            'start' => substr($r->slot_start, 0, 5),
            'end' => substr($r->slot_end, 0, 5),
            'start_label' => AppointmentReader::timeLabel($r->slot_start),
            'end_label' => AppointmentReader::timeLabel($r->slot_end),
            'status' => (int) $r->status,
            'status_key' => AppointmentReader::STATUS_KEYS[(int) $r->status] ?? 'unknown',
            'status_label' => Appointment::statusLabel((int) $r->status),
            'customer' => ['name' => $r->customer_name, 'phone' => $r->customer_phone],
            'staff_names' => $r->staff_names ?? '',
            'discount' => Money::str($r->total_discount),
            'tip' => Money::str($r->total_tip),
            'total' => Money::str($r->total_amt),
        ])->all(), $total];
    }
}
