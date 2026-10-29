<?php

namespace App\Services\Api;

use App\Models\Appointment;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Read side of appointments for the app: the lists on the dashboard and the
 * Appointments page, the per-status counts and the detail view.
 *
 * Every rule here is copied from the web (AppointmentController /
 * DashboardController) and marked with "web:" comments. The web returns one
 * fat GROUP_CONCAT row per appointment as HTML for DataTables; this class
 * returns typed rows instead, using two small queries (a page of appointment
 * ids, then their service lines) which is faster and paginates properly.
 */
class AppointmentReader
{
    /** Same labels as Appointment::statusLabel(). */
    public const STATUS_KEYS = [0 => 'pending', 1 => 'completed', 2 => 'cancelled', 3 => 'confirmed', 4 => 'rescheduled'];

    /**
     * What the web offers per status (the buttons it draws). The app renders
     * buttons from this list, so rules live only on the server.
     */
    public static function actionMatrix(): array
    {
        $matrix = [
            0 => ['confirm', 'complete', 'cancel', 'reschedule', 'view'],
            1 => ['view'],
            2 => ['reschedule', 'view'],
            3 => ['cancel', 'complete', 'view'],
            4 => ['confirm', 'complete', 'cancel', 'view'],
        ];

        // The web's "Complete" button opens invoice/edit/{id}, which returns 404 for
        // an appointment that has no invoice yet (web quirk Q5). Until the web is fixed
        // the app must not offer it.
        if (!config('api_v1.feature_flags.complete_from_appointment')) {
            $matrix = array_map(fn ($a) => array_values(array_diff($a, ['complete'])), $matrix);
        }

        return $matrix;
    }

    public static function actionsFor(int $status): array
    {
        return self::actionMatrix()[$status] ?? ['view'];
    }

    // ------------------------------------------------------------------ lists

    /**
     * @param string $mode  'list' (Appointments page) | 'today' | 'upcoming' (dashboard)
     * @param array  $f     filters: start_date,end_date,status,staff_id,day_type,q
     * @return array{0: array, 1: int} [rows, total]
     */
    public function paginate(User $user, string $mode, array $f, int $page, int $perPage): array
    {
        $q = $this->baseQuery($user, $mode, $f);

        $total = (int) (clone $q)->distinct()->count('a.appointment_id');

        $order = (clone $q)->select('a.appointment_id', 'a.date', 'a.slot_start')
            ->groupBy('a.appointment_id', 'a.date', 'a.slot_start');

        if ($mode === 'list') {
            // web: orderBy date desc, slot_start desc
            $order->orderBy('a.date', 'desc')->orderBy('a.slot_start', 'desc');
        } elseif ($mode === 'today') {
            $order->orderBy('a.slot_start')->orderBy('a.appointment_id');
        } else {
            $order->orderBy('a.date')->orderBy('a.slot_start')->orderBy('a.appointment_id');
        }

        $ids = $order->forPage($page, $perPage)->pluck('a.appointment_id')->all();

        return [$this->hydrate($user, $mode, $f, $ids), $total];
    }

    /**
     * Joined, filtered query shared by the page of ids and the total count.
     */
    private function baseQuery(User $user, string $mode, array $f): Builder
    {
        $q = DB::table('tbl_appointment as a')
            ->leftJoin('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
            ->leftJoin('users as u', function ($join) {
                $join->on('s.staff_id', '=', 'u.id')->where('u.role', '=', 'Staff');
            })
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id');

        $this->applyLineScope($q, $user, $mode, $f);

        if ($mode === 'today') {
            $q->where('a.date', Carbon::today()->toDateString());
            $this->notInvoiced($q);
        } elseif ($mode === 'upcoming') {
            $q->where('a.date', '>', Carbon::today()->toDateString());
            $this->notInvoiced($q);
        } else {
            // web: both dates must be present to filter by date
            if (!empty($f['start_date']) && !empty($f['end_date'])) {
                $q->whereBetween('a.date', [$f['start_date'], $f['end_date']]);
            }
            if (isset($f['status']) && $f['status'] !== '') {
                $q->where('a.status', (int) $f['status']);
            }
            if (!empty($f['day_type'])) {
                $windows = [
                    'Morning' => ['06:00:00', '11:59:59'],
                    'Afternoon' => ['12:00:00', '16:59:59'],
                    'Evening' => ['17:00:00', '22:00:00'],
                ];
                if (isset($windows[$f['day_type']])) {
                    $q->whereBetween('a.slot_start', $windows[$f['day_type']]);
                }
            }
        }

        if (isset($f['q']) && trim($f['q']) !== '') {
            $like = '%' . trim($f['q']) . '%';
            if ($mode === 'list') {
                // web: id, booking name, booking phone, any staff name
                $q->where(function ($sub) use ($like) {
                    $sub->where('a.appointment_id', 'like', $like)
                        ->orWhere('a.name', 'like', $like)
                        ->orWhere('a.phone', 'like', $like)
                        ->orWhere('u.name', 'like', $like);
                });
            } else {
                // web (dashboard): id, customer name, customer phone
                $q->where(function ($sub) use ($like) {
                    $sub->where('a.appointment_id', 'like', $like)
                        ->orWhere('c.customer_name', 'like', $like)
                        ->orWhere('c.customer_phone', 'like', $like);
                });
            }
        }

        return $q;
    }

    /**
     * web: dashboard lists only show appointments that have no invoice yet.
     * (`is_invoiced` is a varchar, so 0 / NULL is compared exactly like the web does.)
     */
    private function notInvoiced($q): void
    {
        $q->where(function ($w) {
            $w->where('a.is_invoiced', 0)->orWhereNull('a.is_invoiced');
        });
    }

    /**
     * Restricts the *service lines* a user may see. Staff only ever see lines that
     * are theirs. The Appointments page additionally hides "First available" lines
     * from staff (web: getTableData); the dashboard does not (web: GetToday/Upcoming).
     */
    private function applyLineScope($q, User $user, string $mode, array $f): void
    {
        if ($user->isStaffUser()) {
            $q->where('s.staff_id', $user->id);
            if ($mode === 'list') {
                $q->where(function ($sub) {
                    $sub->whereNull('s.is_first_available')->orWhere('s.is_first_available', 0);
                });
            }
        }

        if ($mode === 'list' && !empty($f['staff_id'])) {
            $q->where('s.staff_id', (int) $f['staff_id']);
        }
    }

    /**
     * Second query: headers and service lines for the page of ids, shaped for the app.
     */
    private function hydrate(User $user, string $mode, array $f, array $ids): array
    {
        if ($ids === []) {
            return [];
        }

        $headers = DB::table('tbl_appointment as a')
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->whereIn('a.appointment_id', $ids)
            ->get([
                'a.appointment_id', 'a.booking_code', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status',
                'a.name as booking_name', 'a.phone as booking_phone', 'a.total_amt',
                'c.customer_id', 'c.customer_name', 'c.customer_phone',
            ])->keyBy('appointment_id');

        $linesQ = DB::table('tbl_appointment_service as s')
            ->leftJoin('users as u', function ($join) {
                $join->on('s.staff_id', '=', 'u.id')->where('u.role', '=', 'Staff');
            })
            ->leftJoin('tbl_service as t', 's.service_id', '=', 't.id')
            ->whereIn('s.appointment_id', $ids);

        // same line restrictions as the id query so staff names/services match the web
        $this->applyLineScope($linesQ, $user, $mode, $f);

        // web: on the Appointments page the search term is a WHERE on the joined rows, so
        // when an appointment is found only through a *staff name*, only that staff's
        // lines survive in the row. Reproduce that: lines are kept when the appointment
        // itself matches (id / name / phone) or when the line's staff name matches.
        if ($mode === 'list' && isset($f['q']) && trim($f['q']) !== '') {
            $like = '%' . trim($f['q']) . '%';
            $linesQ->join('tbl_appointment as a', 'a.appointment_id', '=', 's.appointment_id')
                ->where(function ($sub) use ($like) {
                    $sub->where('a.appointment_id', 'like', $like)
                        ->orWhere('a.name', 'like', $like)
                        ->orWhere('a.phone', 'like', $like)
                        ->orWhere('u.name', 'like', $like);
                });
        }

        $byAppt = $linesQ->orderBy('s.id')->get([
            's.id', 's.appointment_id', 's.service_id', 's.staff_id', 's.is_first_available',
            'u.name as staff_name', 't.service_name',
        ])->groupBy('appointment_id');

        $rows = [];
        foreach ($ids as $id) {
            $h = $headers->get($id);
            if (!$h) {
                continue;
            }
            $rows[] = $this->shape($h, $byAppt->get($id, collect()));
        }

        return $rows;
    }

    private function shape($h, $lines): array
    {
        $staffNames = [];
        $staffIds = [];
        $serviceIds = [];
        $labels = [];

        foreach ($lines as $l) {
            if ($l->staff_name !== null && !in_array($l->staff_name, $staffNames, true)) {
                $staffNames[] = $l->staff_name;          // web: GROUP_CONCAT(DISTINCT u.name)
            }
            if ($l->staff_id !== null && !in_array((int) $l->staff_id, $staffIds, true)) {
                $staffIds[] = (int) $l->staff_id;        // web: GROUP_CONCAT(DISTINCT s.staff_id)
            }
            if ($l->service_id !== null && !in_array((int) $l->service_id, $serviceIds, true)) {
                $serviceIds[] = (int) $l->service_id;    // web: GROUP_CONCAT(DISTINCT s.service_id)
            }
            // web: "First available: Men's cut | Allen: Beard"
            $who = ((int) $l->is_first_available === 1) ? 'First available' : $l->staff_name;
            if ($who !== null && $l->service_name !== null) {
                $label = $who . ': ' . $l->service_name;
                if (!in_array($label, $labels, true)) {
                    $labels[] = $label;
                }
            }
        }

        $status = (int) $h->status;

        return [
            'id' => (int) $h->appointment_id,
            'booking_code' => $h->booking_code,
            'date' => $h->date,
            'start' => substr((string) $h->slot_start, 0, 5),
            'end' => substr((string) $h->slot_end, 0, 5),
            'start_label' => self::timeLabel($h->slot_start),
            'end_label' => self::timeLabel($h->slot_end),
            'slot_label' => self::timeLabel($h->slot_start) . ' - ' . self::timeLabel($h->slot_end),
            'status' => $status,
            'status_key' => self::STATUS_KEYS[$status] ?? 'unknown',
            'status_label' => Appointment::statusLabel($status),
            'customer' => [
                'id' => $h->customer_id !== null ? (int) $h->customer_id : null,
                'name' => $h->customer_name ?? $h->booking_name,
                'phone' => $h->customer_phone ?? $h->booking_phone,
            ],
            'staff_names' => $staffNames,
            'staff_ids' => $staffIds,
            'service_ids' => $serviceIds,
            'lines' => $labels,
            'actions' => self::actionsFor($status),
        ];
    }

    public static function timeLabel($time): string
    {
        if (!$time) {
            return '';
        }

        return Carbon::parse($time)->format('h:i A');
    }

    // ----------------------------------------------------------------- counts

    /**
     * web: AppointmentController::countAppointmentsByStatus (left join, distinct,
     * staff ⇒ own lines). The web shows five numbers; "pending" is added here.
     */
    public function counts(User $user): array
    {
        $count = function (?int $status) use ($user) {
            return (int) DB::table('tbl_appointment as a')
                ->leftJoin('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
                ->when($status !== null, fn ($q) => $q->where('a.status', $status))
                ->when($user->isStaffUser(), fn ($q) => $q->where('s.staff_id', $user->id))
                ->distinct()
                ->count('a.appointment_id');
        };

        return [
            'all' => $count(null),
            'pending' => $count(0),
            'confirmed' => $count(3),
            'completed' => $count(1),
            'cancelled' => $count(2),
            'rescheduled' => $count(4),
        ];
    }

    // ----------------------------------------------------------------- detail

    /**
     * web: get_appointment_details + fetchAppointmentServiceRows +
     * groupAppointmentDetailRows. Staff only see their own service lines, and an
     * appointment they have no line on does not exist for them.
     */
    public function detail(User $user, int $id): ?array
    {
        $a = DB::table('tbl_appointment as a')
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->where('a.appointment_id', $id)
            ->first([
                'a.appointment_id', 'a.booking_code', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status',
                'a.total_amt', 'a.notes', 'a.comment', 'a.created_at', 'a.is_invoiced', 'a.invoice_number',
                'a.name as booking_name', 'a.phone as booking_phone', 'a.email as booking_email',
                'c.customer_id', 'c.customer_name', 'c.customer_phone', 'c.customer_email',
            ]);

        if (!$a) {
            return null;
        }

        $rows = DB::table('tbl_appointment_service as s')
            ->leftJoin('users as u', function ($join) {
                $join->on('s.staff_id', '=', 'u.id')->where('u.role', '=', 'Staff');
            })
            ->leftJoin('tbl_service as t', 's.service_id', '=', 't.id')
            ->leftJoin('users as ru', 's.requested_staff_id', '=', 'ru.id')
            ->when($user->isStaffUser(), fn ($q) => $q->where('s.staff_id', $user->id))
            ->where('s.appointment_id', $id)
            ->orderBy('s.id')
            ->get([
                's.service_id', 't.service_name', 't.price', 't.duration',
                's.staff_id', 'u.name as staff_name',
                's.requested_staff_id', 'ru.name as requested_staff_name', 's.is_first_available',
            ]);

        if ($user->isStaffUser() && $rows->isEmpty()) {
            return null;
        }

        $grouped = $this->groupDetailRows($rows);

        $subtotal = collect($grouped['services_grouped'])->sum('line_total');
        $total = (float) ($a->total_amt ?? 0);
        if ($total <= 0) {
            $total = $subtotal;   // web: falls back to the services subtotal
        }

        $status = (int) $a->status;

        return [
            'id' => (int) $a->appointment_id,
            'booking_code' => $a->booking_code,
            'date' => $a->date,
            'start' => substr((string) $a->slot_start, 0, 5),
            'end' => substr((string) $a->slot_end, 0, 5),
            'start_label' => self::timeLabel($a->slot_start),
            'end_label' => self::timeLabel($a->slot_end),
            'slot_label' => self::timeLabel($a->slot_start) . ' - ' . self::timeLabel($a->slot_end),
            'status' => $status,
            'status_key' => self::STATUS_KEYS[$status] ?? 'unknown',
            'status_label' => Appointment::statusLabel($status),
            'is_invoiced' => (string) $a->is_invoiced === '1',
            'invoice_number' => $a->invoice_number,
            'notes' => $a->notes,
            'created_at' => $a->created_at ? Carbon::parse($a->created_at)->toIso8601String() : null,
            'customer' => [
                'id' => $a->customer_id !== null ? (int) $a->customer_id : null,
                'name' => $a->customer_name ?? $a->booking_name,
                'phone' => $a->customer_phone ?? $a->booking_phone,
                'email' => $a->customer_email ?? $a->booking_email,
            ],
            'services_grouped' => array_map(function ($g) {
                $g['price'] = Money::str($g['price']);
                $g['line_total'] = Money::str($g['line_total']);

                return $g;
            }, $grouped['services_grouped']),
            'staff_grouped' => $grouped['staff_grouped'],
            'subtotal' => Money::str($subtotal),
            'total' => Money::str($total),
            'actions' => self::actionsFor($status),
        ];
    }

    /**
     * Port of AppointmentController::groupAppointmentDetailRows (qty-aware: one
     * service line per unit, so two units of the same service become qty 2).
     */
    private function groupDetailRows($rows): array
    {
        $serviceGroups = [];
        $staffGroups = [];

        foreach ($rows as $row) {
            $serviceId = (string) ($row->service_id ?? '');
            $staffId = (string) ($row->staff_id ?? '');
            $price = (float) ($row->price ?? 0);
            $duration = (int) ($row->duration ?? 0);
            $serviceName = $row->service_name ?? 'Service';
            $assignedName = $row->staff_name ?? 'Staff';
            $isFirst = $this->rowIsFirstAvailable($row);
            $displayName = $isFirst ? 'First available' : $assignedName;
            $groupKey = $isFirst
                ? ('flex-' . ($staffId !== '' ? $staffId : $displayName))
                : ($staffId !== '' ? $staffId : $displayName);

            if ($serviceId !== '') {
                if (!isset($serviceGroups[$serviceId])) {
                    $serviceGroups[$serviceId] = [
                        'service_id' => (int) $row->service_id,
                        'service_name' => $serviceName,
                        'price' => $price,
                        'duration' => $duration,
                        'qty' => 0,
                        'line_total' => 0,
                        'duration_total' => 0,
                        'staff_names' => [],
                        'staff_ids' => [],
                    ];
                }
                $serviceGroups[$serviceId]['qty']++;
                $serviceGroups[$serviceId]['line_total'] += $price;
                $serviceGroups[$serviceId]['duration_total'] += $duration;
                $label = $isFirst
                    ? 'First available' . ($this->isFirstAvailableName($assignedName) ? '' : ' (' . $assignedName . ')')
                    : $assignedName;
                if ($staffId !== '' && !in_array((int) $staffId, $serviceGroups[$serviceId]['staff_ids'], true)) {
                    $serviceGroups[$serviceId]['staff_ids'][] = (int) $staffId;
                }
                if ($label && !in_array($label, $serviceGroups[$serviceId]['staff_names'], true)) {
                    $serviceGroups[$serviceId]['staff_names'][] = $label;
                }
            }

            if ($groupKey !== '') {
                if (!isset($staffGroups[$groupKey])) {
                    $staffGroups[$groupKey] = [
                        'staff_id' => $row->staff_id !== null ? (int) $row->staff_id : null,
                        'staff_name' => $displayName,
                        'is_first_available' => $isFirst,
                        'assigned_staff_name' => ($isFirst && !$this->isFirstAvailableName($assignedName)) ? $assignedName : null,
                        'services' => [],
                    ];
                }
                $svcKey = $serviceId !== '' ? $serviceId : $serviceName;
                if (!isset($staffGroups[$groupKey]['services'][$svcKey])) {
                    $staffGroups[$groupKey]['services'][$svcKey] = ['service_name' => $serviceName, 'qty' => 0];
                }
                $staffGroups[$groupKey]['services'][$svcKey]['qty']++;
            }
        }

        return [
            'services_grouped' => array_values(array_map(function ($g) {
                $g['staff_names'] = array_values($g['staff_names']);

                return $g;
            }, $serviceGroups)),
            'staff_grouped' => array_values(array_map(function ($g) {
                $g['services'] = array_values($g['services']);

                return $g;
            }, $staffGroups)),
        ];
    }

    private function rowIsFirstAvailable($row): bool
    {
        if (!empty($row->is_first_available)) {
            return true;
        }

        return $this->isFirstAvailableName($row->requested_staff_name ?? null)
            || $this->isFirstAvailableName($row->staff_name ?? null);
    }

    private function isFirstAvailableName($name): bool
    {
        $value = strtolower(trim((string) $name));

        return $value === 'first available' || strpos($value, 'first available') === 0;
    }
}
