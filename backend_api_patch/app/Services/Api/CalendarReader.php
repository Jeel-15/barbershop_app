<?php

namespace App\Services\Api;

use App\Helpers\Helper;
use App\Models\Appointment;
use App\Models\Breaks;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Read side of the calendar (web: AppointmentController::calenderIndex, fetch,
 * fetchStaffAvailability). The grouping of service lines into "lanes" is ported
 * line for line, so an event appears in the same column, with the same title,
 * service text and duration as on the web calendar.
 *
 * Differences that cannot change what a user sees: a date range is required (the
 * web returns every appointment ever), and staff users are always limited to their
 * own lane (the web only does that when the filter is empty).
 */
class CalendarReader
{
    // ------------------------------------------------------------------ lanes

    /**
     * web: calenderIndex — admins see every barber, staff see themselves, anyone
     * else sees no lane.
     */
    public function lanes(User $user): array
    {
        if ($user->role == 'Admin' || $user->hasRole('Super-admin')) {
            $rows = User::barbers()->get(['id', 'name', 'profile_img', 'role']);
        } elseif ($user->role === 'Staff' || $user->hasRole('Staff')) {
            $rows = User::barbers()->where('id', $user->id)->get(['id', 'name', 'profile_img', 'role']);
        } else {
            $rows = collect();
        }

        return $rows->map(fn ($s) => [
            'id' => (int) $s->id,
            'name' => trim((string) $s->name) ?: 'Staff',
            'profile_image_url' => Media::avatar($s->profile_img),
        ])->values()->all();
    }

    // ----------------------------------------------------------------- events

    public function events(User $user, string $from, string $to, ?int $requestedStaffId): array
    {
        $staffId = $user->isStaffUser() ? (int) $user->id : $requestedStaffId;
        $singleStaffView = !empty($staffId);

        $events = [];

        foreach ($this->appointmentRows($staffId, $from, $to) as $appt) {
            $apptDate = Carbon::parse($appt->date)->format('Y-m-d');
            $dateStart = $apptDate . ' ' . $appt->slot_start;
            $apptStart = Carbon::parse($dateStart);
            $apptEnd = Carbon::parse($apptDate . ' ' . $appt->slot_end);
            $fullDuration = (int) $apptEnd->diffInMinutes($apptStart);
            $customerName = $appt->name ?: 'Walk-In';
            $grouped = $this->groupByLane($appt->services, $singleStaffView ? (string) $staffId : null);

            foreach ($grouped['assigned'] as $g) {
                $duration = (int) ($g['total_duration'] ?: 0) ?: $fullDuration;
                $events[] = $this->appointmentEvent(
                    'appt_' . $appt->appointment_id . '_staff_' . $g['staff_id'],
                    (string) $g['staff_id'], $g['staff_name'], $appt, $customerName,
                    $dateStart, $apptStart->copy()->addMinutes($duration)->format('Y-m-d H:i:s'),
                    $duration, $g['service_ids'], $g['service_names'], (string) $g['staff_id'], null, false
                );
            }

            foreach ($grouped['first_available'] as $g) {
                $duration = (int) ($g['total_duration'] ?: 0) ?: $fullDuration;
                $events[] = $this->appointmentEvent(
                    'appt_' . $appt->appointment_id . '_first_' . $g['resource_id'],
                    (string) $g['resource_id'], 'First available', $appt, $customerName,
                    $dateStart, $apptStart->copy()->addMinutes($duration)->format('Y-m-d H:i:s'),
                    $duration, $g['service_ids'], $g['service_names'], (string) ($g['modal_staff_id'] ?? $g['resource_id']),
                    $g['assigned_staff_name'] ?? null, true
                );
            }
        }

        // web: ad-hoc breaks (type 2) sit on the day they were created
        $breaks = Breaks::where('break_type', 2)
            ->when($staffId, fn ($q, $id) => $q->where('staff_id', $id))
            ->whereBetween(DB::raw('DATE(created_at)'), [$from, $to])
            ->get();

        foreach ($breaks as $break) {
            $day = Carbon::parse($break->created_at)->format('Y-m-d');
            $events[] = [
                'id' => 'break_' . $break->id,
                'type' => 'break',
                'resource_id' => (string) $break->staff_id,
                'title' => 'Break',
                'start' => $day . ' ' . Carbon::parse($break->break_start)->format('H:i:s'),
                'end' => $day . ' ' . Carbon::parse($break->break_end)->format('H:i:s'),
                'staff_id' => (int) $break->staff_id,
                'staff_name' => Helper::getStaffName($break->staff_id),
                'break_id' => (int) $break->id,
            ];
        }

        return $events;
    }

    /** web: fetchCalendarAppointmentRows (not invoiced, not cancelled, has lines). */
    private function appointmentRows($staffId, string $from, string $to)
    {
        return Appointment::query()
            ->select(
                'tbl_appointment.appointment_id', 'tbl_appointment.date', 'tbl_appointment.is_invoiced',
                'tbl_appointment.email', 'tbl_appointment.slot_start', 'tbl_appointment.slot_end',
                'tbl_appointment.name', 'tbl_appointment.phone', 'tbl_appointment.notes',
                'tbl_appointment.comment', 'tbl_appointment.status'
            )
            ->when($staffId, fn ($q) => $q->whereHas('services', fn ($sq) => $sq->where('staff_id', $staffId)))
            ->where(function ($q) {
                $q->orWhereNull('tbl_appointment.is_invoiced');
            })
            ->where('tbl_appointment.status', '!=', 2)
            ->whereBetween('tbl_appointment.date', [$from, $to])
            ->with(['services' => function ($q) use ($staffId) {
                $q->with(['service', 'staff', 'requestedStaff'])
                    ->when($staffId, fn ($sq) => $sq->where('staff_id', $staffId))
                    ->orderBy('id');
            }])
            ->orderBy('tbl_appointment.date')
            ->orderBy('tbl_appointment.slot_start')
            ->get()
            ->filter(fn ($a) => $a->services->isNotEmpty())
            ->values();
    }

    /** web: groupCalendarServicesByLane */
    private function groupByLane($serviceRows, ?string $viewStaffId): array
    {
        $assigned = [];
        $firstAvailable = [];
        $single = !empty($viewStaffId);
        $faResource = $this->firstAvailableId() ?: 'first-available';

        foreach ($serviceRows as $row) {
            $serviceName = optional($row->service)->service_name;
            if (!$serviceName) {
                continue;
            }

            $serviceId = (string) $row->service_id;
            $staffId = (string) $row->staff_id;
            $staffName = optional($row->staff)->name ?: Helper::getStaffName($row->staff_id);
            $duration = (int) (optional($row->service)->duration ?? 0);

            if ($single && $staffId !== (string) $viewStaffId) {
                continue;
            }

            $isFirst = $this->rowIsFirstAvailable($row);

            if ($single || !$isFirst) {
                if ($staffId === '') {
                    continue;
                }
                $assigned[$staffId] ??= ['staff_id' => $row->staff_id, 'staff_name' => $staffName ?: 'Staff', 'service_ids' => [], 'service_names' => [], 'total_duration' => 0];
                $assigned[$staffId]['service_ids'][] = $serviceId;
                $assigned[$staffId]['service_names'][] = $serviceName;
                $assigned[$staffId]['total_duration'] += $duration;
            }

            if (!$single && $isFirst) {
                $resource = (string) $faResource;
                $firstAvailable[$resource] ??= ['resource_id' => $resource, 'service_ids' => [], 'service_names' => [], 'modal_staff_id' => $resource, 'assigned_staff_name' => null, 'total_duration' => 0];
                $firstAvailable[$resource]['service_ids'][] = $serviceId;
                $firstAvailable[$resource]['service_names'][] = $serviceName;
                $firstAvailable[$resource]['total_duration'] += $duration;
            }
        }

        $finish = function ($g) {
            $g['service_names'] = $this->formatServiceNames($g['service_names']);

            return $g;
        };

        return [
            'assigned' => array_values(array_map($finish, $assigned)),
            'first_available' => array_values(array_map($finish, $firstAvailable)),
        ];
    }

    /** web: formatCalendarServiceNames — "Men's cut ×2, Beard ×1" */
    private function formatServiceNames(array $names): string
    {
        $parts = [];
        foreach (array_count_values(array_values(array_filter($names))) as $name => $count) {
            $parts[] = $name . ' ×' . max(1, (int) $count);
        }

        return implode(', ', $parts);
    }

    private function appointmentEvent(
        string $id, string $resourceId, string $staffName, $appt, string $customerName,
        string $start, string $end, int $duration, array $serviceIds, string $serviceNames,
        string $modalStaffId, ?string $assignedStaffName, bool $firstAvailableLane
    ): array {
        $status = (int) $appt->status;

        return [
            'id' => $id,
            'type' => 'appointment',
            'resource_id' => $resourceId,
            'title' => $customerName,
            'start' => $start,
            'end' => $end,
            'appointment_id' => (int) $appt->appointment_id,
            'status' => $status,
            'status_key' => AppointmentReader::STATUS_KEYS[$status] ?? 'unknown',
            'status_label' => Appointment::statusLabel($status),
            'staff_id' => (int) $modalStaffId,
            'staff_name' => $staffName,
            'assigned_staff_name' => $assignedStaffName,
            'is_first_available_lane' => $firstAvailableLane,
            'phone' => $appt->phone,
            'email' => $appt->email,
            'notes' => $appt->notes,
            'location' => $appt->comment,
            'service_ids' => array_map('intval', $serviceIds),
            'service_names' => $serviceNames,
            'duration' => $duration,
        ];
    }

    /** web: calendarRowIsFirstAvailable */
    private function rowIsFirstAvailable($row): bool
    {
        $flexId = $this->firstAvailableId();

        if (!empty($row->is_first_available)) {
            return true;
        }
        if ($flexId && !empty($row->requested_staff_id) && (string) $row->requested_staff_id === (string) $flexId) {
            return true;
        }
        if ($this->isFirstAvailableName(optional($row->requestedStaff)->name)) {
            return true;
        }

        return $flexId && (string) ($row->staff_id ?? '') === (string) $flexId;
    }

    private function isFirstAvailableName($name): bool
    {
        $value = strtolower(trim((string) $name));

        return $value === 'first available' || strpos($value, 'first available') === 0;
    }

    private function firstAvailableId(): ?string
    {
        static $id = false;

        if ($id === false) {
            $found = User::query()
                ->where('role', 'Staff')
                ->where(function ($q) {
                    $q->whereRaw('LOWER(name) = ?', ['first available'])->orWhereRaw('LOWER(name) LIKE ?', ['first available%']);
                })
                ->value('id');
            $id = $found ? (string) $found : null;
        }

        return $id;
    }

    // ----------------------------------------------------------- availability

    /**
     * web: fetchStaffAvailability — what the calendar greys out. Shop open/close
     * (09:00–21:00 when the shop has no hours for that weekday), then for each
     * barber: day-off flag, working-hour blocks (type 1, falling back to the day's
     * open/close) and that day's ad-hoc breaks.
     */
    public function availability(User $user, string $date, ?int $requestedStaffId): array
    {
        $staffId = $user->isStaffUser() ? (int) $user->id : $requestedStaffId;
        $dayName = Carbon::parse($date)->format('l');

        $shopSlot = DB::table('tbl_slots')->where('staff_id', 0)->where('day_name', $dayName)->first();

        $open = $close = null;
        $shopOff = false;

        if ($shopSlot) {
            $shopOff = (bool) $shopSlot->is_day_off;
            if (!$shopOff && !empty($shopSlot->open_time) && !empty($shopSlot->close_time)) {
                $open = Carbon::parse($shopSlot->open_time)->format('H:i');
                $close = Carbon::parse($shopSlot->close_time)->format('H:i');
            }
        }
        if (!$open || !$close) {
            $open = '09:00';
            $close = '21:00';
        }

        $staff = [];

        foreach (User::barbers()->when($staffId, fn ($q) => $q->where('id', $staffId))->get() as $barber) {
            $slot = DB::table('tbl_slots')->where('staff_id', $barber->id)->where('day_name', $dayName)->first();
            $isOff = $slot ? (bool) $slot->is_day_off : false;
            $hours = [];

            if (!$isOff && $slot) {
                $hours = DB::table('tbl_breaks')
                    ->where('slot_id', $slot->id)->where('staff_id', $barber->id)->where('break_type', 1)
                    ->orderBy('break_start')->get()
                    ->map(fn ($b) => ['start' => Carbon::parse($b->break_start)->format('H:i'), 'end' => Carbon::parse($b->break_end)->format('H:i')])
                    ->all();

                if (empty($hours) && !empty($slot->open_time) && !empty($slot->close_time)) {
                    $hours = [['start' => Carbon::parse($slot->open_time)->format('H:i'), 'end' => Carbon::parse($slot->close_time)->format('H:i')]];
                }
            }

            $breaks = DB::table('tbl_breaks')
                ->where('staff_id', $barber->id)->where('break_type', 2)->whereDate('created_at', $date)->get()
                ->map(fn ($b) => ['start' => Carbon::parse($b->break_start)->format('H:i'), 'end' => Carbon::parse($b->break_end)->format('H:i')])
                ->all();

            $staff[(string) $barber->id] = ['name' => $barber->name, 'is_day_off' => $isOff, 'working_hours' => $hours, 'breaks' => $breaks];
        }

        return [
            'date' => $date,
            'day_name' => $dayName,
            'shop_open' => $open,
            'shop_close' => $close,
            'shop_day_off' => $shopOff,
            'staff' => (object) $staff,
        ];
    }
}
