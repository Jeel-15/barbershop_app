<?php

namespace App\Services\Api;

use App\Models\Appointment;
use App\Models\Customer;
use Illuminate\Support\Facades\DB;

/**
 * CUST-1 .. CUST-6 — mirrors CustomerController (list, profile, the profile's
 * appointment table, create, update, delete). The profile numbers are the
 * web's own queries, quirks included (docs/API_PLAN.md Q35).
 */
class CustomerService
{
    public static function present(Customer $c): array
    {
        $status = $c->customer_status;

        return [
            'id' => (int) $c->customer_id,
            'name' => $c->customer_name,
            'phone' => $c->customer_phone,
            'email' => $c->customer_email,
            'status' => $status === null ? null : (int) $status,
            'status_label' => (string) $status === '1' ? 'Active' : 'Inactive',   // web badge: 1 = Active, anything else = Inactive
            'created_at' => optional($c->created_at)->toDateString(),
        ];
    }

    /** @return array{0: array, 1: int} */
    public function paginate(array $f, int $page, int $perPage): array
    {
        $q = Customer::query()
            ->when(isset($f['status']) && $f['status'] !== '', fn ($w) => $w->where('customer_status', (string) $f['status']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($s) => $s->where('customer_name', 'like', $like)
                    ->orWhere('customer_phone', 'like', $like)
                    ->orWhere('customer_email', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->orderByDesc('customer_id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($c) => self::present($c))->all(), $total];
    }

    /** web: CustomerController::customer_profile */
    public function profile(int $id): ?array
    {
        $customer = Customer::where('customer_id', $id)->first();
        if (!$customer) {
            return null;
        }

        $totalVisit = DB::table('tbl_appointment_service as s')
            ->join('tbl_appointment as a', 's.appointment_id', '=', 'a.appointment_id')
            ->where('a.customer_id', $id)
            ->where('a.is_invoiced', 1)
            ->distinct('a.appointment_id')
            ->count('a.customer_id');

        // web quirk Q35: joins service lines, so an invoice is added once per service line
        $totalServiceEarnings = DB::table('tbl_appointment_service as s')
            ->join('tbl_appointment as a', 's.appointment_id', '=', 'a.appointment_id')
            ->where('a.customer_id', $id)
            ->where('a.is_invoiced', 1)
            ->sum('a.total_amt');

        $totalProductCommission = DB::table('tbl_appointment_product as p')
            ->join('tbl_appointment as a', 'p.appointment_id', '=', 'a.appointment_id')
            ->where('a.customer_id', $id)
            ->sum('product_commision');

        return self::present($customer) + [
            'total_visits' => (int) $totalVisit,
            'total_spend' => Money::str($totalProductCommission + $totalServiceEarnings),
            'appointments_total' => (int) DB::table('tbl_appointment')->where('customer_id', $id)->count(),
        ];
    }

    /**
     * web: CustomerController::PendingAppointmentgetTableData — the profile's
     * appointment table. The web's status filter is broken (it never receives a
     * value), here it works.
     *
     * @return array{0: array, 1: int}
     */
    public function appointments(int $customerId, array $f, int $page, int $perPage): array
    {
        $base = DB::table('tbl_appointment as a')
            ->leftJoin('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
            ->leftJoin('users as u', function ($join) {
                $join->on('s.staff_id', '=', 'u.id')->where('u.role', '=', 'Staff');
            })
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->where('a.customer_id', $customerId);

        if (!empty($f['start_date']) && !empty($f['end_date'])) {
            $base->whereBetween('a.date', [$f['start_date'], $f['end_date']]);
        }
        if (isset($f['status']) && $f['status'] !== '') {
            $base->where('a.status', (int) $f['status']);
        }
        if (!empty($f['staff_id'])) {
            $base->where('s.staff_id', $f['staff_id']);
        }
        if (!empty($f['day_type'])) {
            [$from, $to] = [
                'Morning' => ['06:00:00', '11:59:59'],
                'Afternoon' => ['12:00:00', '16:59:59'],
                'Evening' => ['17:00:00', '22:00:00'],
            ][$f['day_type']];
            $base->whereBetween('a.slot_start', [$from, $to]);
        }
        if (!empty($f['q'])) {
            $like = '%' . $f['q'] . '%';
            $base->where(fn ($s) => $s->where('a.appointment_id', 'like', $like)
                ->orWhere('a.name', 'like', $like)
                ->orWhere('a.phone', 'like', $like)
                ->orWhere('u.name', 'like', $like));
        }

        $total = (int) (clone $base)->distinct()->count('a.appointment_id');

        $rows = (clone $base)
            ->select(
                'a.appointment_id', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status',
                DB::raw('GROUP_CONCAT(DISTINCT u.name SEPARATOR ", ") as staff_names'),
                DB::raw('GROUP_CONCAT(DISTINCT s.staff_id) as staff_ids'),
                DB::raw('GROUP_CONCAT(DISTINCT s.service_id) as service_ids')
            )
            ->groupBy('a.appointment_id', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status')
            ->orderByDesc('a.date')->orderByDesc('a.slot_start')->orderByDesc('a.appointment_id')
            ->forPage($page, $perPage)
            ->get();

        $ids = fn ($csv) => $csv === null || $csv === '' ? [] : array_map('intval', explode(',', $csv));

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
            'staff_names' => $r->staff_names ?? '',
            'staff_ids' => $ids($r->staff_ids),
            'service_ids' => $ids($r->service_ids),
        ])->all(), $total];
    }

    public function create(array $in): Customer
    {
        $customer = new Customer();
        $customer->customer_name = $in['full_name'];
        $customer->customer_phone = $in['phone_number'];
        $customer->customer_email = $in['email'] ?? null;
        $customer->customer_status = $in['status'] ?? null;
        $customer->save();

        return $customer;
    }

    public function update(Customer $customer, array $in): Customer
    {
        $customer->customer_name = $in['full_name'];
        $customer->customer_phone = $in['phone_number'];
        $customer->customer_email = $in['email'] ?? null;
        $customer->customer_status = $in['status'] ?? null;
        $customer->update();

        return $customer;
    }

    /** The web deletes for good; the API refuses while the customer still has appointments (D17). */
    public function delete(Customer $customer): ?string
    {
        if (DB::table('tbl_appointment')->where('customer_id', $customer->customer_id)->exists()) {
            return 'This customer has appointments and cannot be deleted.';
        }
        $customer->delete();

        return null;
    }
}
