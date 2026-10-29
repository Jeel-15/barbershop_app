<?php

namespace App\Services\Api;

use App\Models\Appointment;
use App\Models\AppointmentService;
use App\Models\Customer;
use App\Models\Service;
use App\Models\StaffService;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Writes for the calendar and the reschedule dialog.
 *
 * Create / edit mirror AppointmentController::calenderAppointMentStore (same
 * overlap rule, same customer lookup by phone, same service-line rows, same
 * "edit resets the appointment to Pending"). Reschedule mirrors
 * submit_reschedule_appointment. Every method returns [http, message, data] so the
 * controller stays thin.
 *
 * Added protections that change nothing for a normal use of the web: services and
 * staff must exist, an appointment must end the same day, a finished or cancelled
 * appointment cannot be edited, a staff user can only work on their own calendar,
 * a reschedule target must be a slot the booking engine really offers, and the
 * write happens inside a transaction under a per-staff/day lock.
 */
class AppointmentBooking
{
    public function __construct(private AppointmentReader $reader, private SlotEngine $slots)
    {
    }

    // ------------------------------------------------------------ staff by service

    /**
     * web: get_staff_by_service / StaffController::getStaffByService — active
     * barbers (is_barber = 1, not deleted) that offer at least one of the services;
     * the "First available" pseudo user is included whenever it is flagged a barber.
     */
    public function staffByService(array $serviceIds): array
    {
        $rows = [];

        foreach (User::where('role', 'Staff')->where('is_barber', 1)->whereNull('deleted_at')->get() as $barber) {
            $isFirst = (bool) preg_match('/^first\s+available/i', trim((string) $barber->name));
            $offers = [];

            foreach ($serviceIds as $sid) {
                if ($isFirst || StaffService::offersService($barber->id, $sid)) {
                    $offers[] = (int) $sid;
                }
            }

            if ($offers !== []) {
                $rows[] = [
                    'id' => (int) $barber->id,
                    'name' => $barber->name,
                    'is_first_available' => $isFirst,
                    'profile_image_url' => Media::avatar($barber->profile_img),
                    'offers_service_ids' => $offers,
                ];
            }
        }

        return $rows;
    }

    // ------------------------------------------------------------------ create

    public function create(User $user, array $in): array
    {
        $staffId = (int) $in['staff_id'];

        if ($user->isStaffUser() && $staffId !== (int) $user->id) {
            return [403, 'You can only book appointments on your own calendar.', []];
        }

        [$serviceIds, $minutes, $error] = $this->resolveServices($in['services']);
        if ($error) {
            return [422, $error, ['errors' => ['services' => [$error]]]];
        }

        [$start, $end, $error] = $this->window($in['date'], $in['time'], $minutes);
        if ($error) {
            return [422, $error, ['errors' => ['time' => [$error]]]];
        }

        return SlotGuard::run($start->toDateString() . ':' . $staffId, function () use ($user, $in, $staffId, $serviceIds, $start, $end) {
            return DB::transaction(function () use ($user, $in, $staffId, $serviceIds, $start, $end) {
                if ($this->overlaps($staffId, $start, $end, null)) {
                    return [409, 'This staff already has an appointment in this time slot.', []];
                }

                // web: reuse the customer with this phone, otherwise create one
                $customer = Customer::where('customer_phone', $in['phone'])->first()
                    ?: Customer::create([
                        'customer_name' => $in['name'],
                        'customer_phone' => $in['phone'],
                        'customer_email' => $in['email'] ?? null,
                        'customer_status' => 1,
                    ]);

                $appointment = Appointment::create([
                    'date' => $start->toDateString(),
                    'customer_id' => $customer->customer_id,
                    'slot_start' => $start->format('H:i:s'),
                    'slot_end' => $end->format('H:i:s'),
                    'name' => $in['name'],
                    'email' => $in['email'] ?? null,
                    'phone' => $in['phone'],
                    'notes' => $in['notes'] ?? null,
                    'status' => 0,
                    'comment' => $in['name'],
                ]);

                $this->writeLines($appointment->appointment_id, $staffId, $serviceIds);

                return [201, 'Successfully Created Appointment', ['appointment' => $this->reader->detail($user, (int) $appointment->appointment_id)]];
            });
        });
    }

    // -------------------------------------------------------------------- edit

    public function update(User $user, int $id, array $in): array
    {
        $staffId = (int) $in['staff_id'];

        if ($user->isStaffUser() && $staffId !== (int) $user->id) {
            return [403, 'You can only edit appointments on your own calendar.', []];
        }

        [$serviceIds, $minutes, $error] = $this->resolveServices($in['services']);
        if ($error) {
            return [422, $error, ['errors' => ['services' => [$error]]]];
        }

        [$start, $end, $error] = $this->window($in['date'], $in['time'], $minutes);
        if ($error) {
            return [422, $error, ['errors' => ['time' => [$error]]]];
        }

        return SlotGuard::run($start->toDateString() . ':' . $staffId, function () use ($user, $id, $in, $staffId, $serviceIds, $start, $end) {
            return DB::transaction(function () use ($user, $id, $in, $staffId, $serviceIds, $start, $end) {
                $row = DB::table('tbl_appointment')->where('appointment_id', $id)->lockForUpdate()->first();

                if (!$row || ($user->isStaffUser() && !$this->staffHasLine($user->id, $id))) {
                    return [404, 'Appointment not found.', []];
                }

                // the web calendar never shows these, so they cannot be edited there either
                if ((int) $row->status === 1 || (int) $row->status === 2 || (string) $row->is_invoiced === '1') {
                    return [409, 'A completed or cancelled appointment can no longer be edited.', []];
                }

                if ($this->overlaps($staffId, $start, $end, $id)) {
                    return [409, 'This staff already has an appointment in this time slot.', []];
                }

                // web: edit resets the appointment to Pending and rewrites the contact fields
                Appointment::where('appointment_id', $id)->update([
                    'date' => $start->toDateString(),
                    'slot_start' => $start->format('H:i:s'),
                    'slot_end' => $end->format('H:i:s'),
                    'name' => $in['name'],
                    'email' => $in['email'] ?? null,
                    'phone' => $in['phone'],
                    'notes' => $in['notes'] ?? null,
                    'status' => 0,
                    'comment' => $in['name'],
                    'updated_at' => now(),
                ]);

                // web: only THIS staff lane's old lines are replaced; other lanes stay
                $old = AppointmentService::where('appointment_id', $id);
                if ($this->isFirstAvailableStaffId($staffId)) {
                    $old->where(function ($q) use ($staffId) {
                        $q->where('staff_id', $staffId)->orWhere('requested_staff_id', $staffId)->orWhere('is_first_available', 1);
                    });
                } else {
                    $old->where(function ($q) use ($staffId) {
                        $q->where('staff_id', $staffId)->orWhere('requested_staff_id', $staffId);
                    });
                }
                $old->delete();

                $this->writeLines($id, $staffId, $serviceIds);

                return [200, 'Successfully Updated Appointment', ['appointment' => $this->reader->detail($user, $id)]];
            });
        });
    }

    // -------------------------------------------------------------- reschedule

    /**
     * web: submit_reschedule_appointment (date + slot, status becomes 4). The web
     * only shows "Reschedule" for Pending and Cancelled appointments, and its
     * dialog only offers slots the booking engine returns; both are enforced here.
     */
    public function reschedule(User $user, int $id, array $in): array
    {
        return SlotGuard::run('resched:' . $id, function () use ($user, $id, $in) {
            return DB::transaction(function () use ($user, $id, $in) {
                $row = DB::table('tbl_appointment')->where('appointment_id', $id)->lockForUpdate()->first();

                if (!$row || ($user->isStaffUser() && !$this->staffHasLine($user->id, $id))) {
                    return [404, 'Appointment not found.', []];
                }

                $status = (int) $row->status;
                if (!in_array($status, [0, 2], true)) {
                    return [409, 'A ' . strtolower(Appointment::statusLabel($status)) . ' appointment cannot be rescheduled.', []];
                }

                // web: the dialog sends the appointment's distinct staff ids and service ids
                // (staff users only ever see their own lines)
                $lines = DB::table('tbl_appointment_service')
                    ->where('appointment_id', $id)
                    ->when($user->isStaffUser(), fn ($q) => $q->where('staff_id', $user->id))
                    ->get(['staff_id', 'service_id']);

                $staffIds = $lines->pluck('staff_id')->unique()->values()->all();
                $serviceIds = $lines->pluck('service_id')->unique()->values()->all();

                if ($staffIds === [] || $serviceIds === []) {
                    return [409, 'This appointment has no services to reschedule.', []];
                }

                if (!$this->slots->offers($staffIds, $serviceIds, $in['date'], $in['slot_start'], $in['slot_end'])) {
                    return [409, 'That time is not available. Please choose another slot.', []];
                }

                DB::table('tbl_appointment')->where('appointment_id', $id)->update([
                    'date' => $in['date'],
                    'slot_start' => $in['slot_start'] . ':00',
                    'slot_end' => $in['slot_end'] . ':00',
                    'status' => 4,
                    'updated_at' => now(),
                ]);

                return [200, 'Appointment rescheduled successfully.', ['appointment' => $this->reader->detail($user, $id)]];
            });
        });
    }

    // ---------------------------------------------------------------- helpers

    /**
     * Turns [{id, qty}] into one id per unit (the web stores one service line per
     * unit) and the total minutes. total_duration is computed here from the
     * catalog, exactly as the web's JavaScript does (duration × qty).
     *
     * @return array{0:int[],1:int,2:?string}
     */
    private function resolveServices(array $services): array
    {
        $ids = [];
        foreach ($services as $s) {
            for ($i = 0; $i < (int) ($s['qty'] ?? 1); $i++) {
                $ids[] = (int) $s['id'];
            }
        }

        $catalog = Service::whereIn('id', array_unique($ids))->get()->keyBy('id');   // soft-deleted services are excluded
        $minutes = 0;

        foreach ($ids as $sid) {
            if (!$catalog->has($sid)) {
                return [[], 0, 'One of the selected services does not exist.'];
            }
            $minutes += (int) $catalog[$sid]->duration;
        }

        if ($minutes <= 0) {
            return [[], 0, 'The selected services have no duration.'];
        }

        return [$ids, $minutes, null];
    }

    /** @return array{0:?Carbon,1:?Carbon,2:?string} */
    private function window(string $date, string $time, int $minutes): array
    {
        $start = Carbon::createFromFormat('Y-m-d H:i', $date . ' ' . $time);
        $end = $start->copy()->addMinutes($minutes);

        if ($end->toDateString() !== $start->toDateString()) {
            return [null, null, 'An appointment must start and end on the same day.'];
        }

        return [$start, $end, null];
    }

    /**
     * web: another appointment of the same staff on the same day whose start or end
     * lies inside [start, end] (inclusive) or that fully covers it. Status is not
     * considered (a cancelled appointment still blocks the slot, like the web).
     * MySQL compares the TIME columns with the time part only.
     */
    private function overlaps(int $staffId, Carbon $start, Carbon $end, ?int $excludeId): bool
    {
        $s = $start->format('H:i:s');
        $e = $end->format('H:i:s');

        return Appointment::join('tbl_appointment_service as aps', 'aps.appointment_id', '=', 'tbl_appointment.appointment_id')
            ->where('aps.staff_id', $staffId)
            ->whereDate('tbl_appointment.date', $start->toDateString())
            ->where(function ($q) use ($s, $e) {
                $q->whereBetween('tbl_appointment.slot_start', [$s, $e])
                    ->orWhereBetween('tbl_appointment.slot_end', [$s, $e])
                    ->orWhere(function ($inner) use ($s, $e) {
                        $inner->where('tbl_appointment.slot_start', '<=', $s)->where('tbl_appointment.slot_end', '>=', $e);
                    });
            })
            ->when($excludeId, fn ($q) => $q->where('tbl_appointment.appointment_id', '!=', $excludeId))
            ->exists();
    }

    private function writeLines(int $appointmentId, int $staffId, array $serviceIds): void
    {
        $isFirst = $this->isFirstAvailableStaffId($staffId);
        $flexId = $this->firstAvailableId();

        foreach ($serviceIds as $serviceId) {
            AppointmentService::create([
                'appointment_id' => $appointmentId,
                'service_id' => $serviceId,
                'staff_id' => $staffId,
                'product_commission' => 0,
                'service_commission' => 0,
                'service_tip' => 0,
                'total_amt' => 0,
                'status' => 0,
                'comment' => 'Appointment from calendar',
                'requested_staff_id' => ($isFirst && $flexId) ? (int) $flexId : $staffId,
                'is_first_available' => $isFirst ? 1 : 0,
            ]);
        }
    }

    private function staffHasLine(int $staffId, int $appointmentId): bool
    {
        return DB::table('tbl_appointment_service')->where('appointment_id', $appointmentId)->where('staff_id', $staffId)->exists();
    }

    /** web: getFirstAvailableResourceId — the pseudo staff user is found by its name. */
    private function firstAvailableId(): ?int
    {
        static $id = false;

        if ($id === false) {
            $found = User::query()
                ->where('role', 'Staff')
                ->where(function ($q) {
                    $q->whereRaw('LOWER(name) = ?', ['first available'])->orWhereRaw('LOWER(name) LIKE ?', ['first available%']);
                })
                ->value('id');
            $id = $found ? (int) $found : null;
        }

        return $id;
    }

    /** web: isFirstAvailableStaffId */
    private function isFirstAvailableStaffId(int $staffId): bool
    {
        if ($staffId <= 0) {
            return false;
        }
        if ($this->firstAvailableId() === $staffId) {
            return true;
        }

        $name = strtolower(trim((string) User::where('id', $staffId)->value('name')));

        return $name === 'first available' || str_starts_with($name, 'first available');
    }
}
