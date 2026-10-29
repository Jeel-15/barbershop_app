<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\AppointmentActions;
use App\Services\Api\AppointmentBooking;
use App\Services\Api\AppointmentReader;
use App\Services\Api\SlotEngine;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * APPT-1 .. APPT-5 — mirrors AppointmentController (list, counts, detail,
 * confirm, cancel). Whole module needs `Appointment-View` (route middleware).
 */
class AppointmentController extends ApiController
{
    public function index(Request $request, AppointmentReader $appointments)
    {
        $filters = $request->validate([
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
            'status' => ['nullable', 'integer', 'between:0,4'],
            'staff_id' => ['nullable', 'integer', 'min:1'],
            'day_type' => ['nullable', 'in:Morning,Afternoon,Evening'],
            'q' => ['nullable', 'string', 'max:100'],
        ]);

        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $appointments->paginate($request->user(), 'list', $filters, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function counts(Request $request, AppointmentReader $appointments)
    {
        return $this->ok(['counts' => $appointments->counts($request->user())]);
    }

    public function show(Request $request, AppointmentReader $appointments, int $id)
    {
        $detail = $appointments->detail($request->user(), $id);

        if (!$detail) {
            return $this->fail('Appointment not found.', 404);
        }

        return $this->ok(['appointment' => $detail]);
    }

    public function confirm(Request $request, AppointmentActions $actions, int $id)
    {
        return $this->change($request, $actions, $id, 'confirm');
    }

    public function cancel(Request $request, AppointmentActions $actions, int $id)
    {
        return $this->change($request, $actions, $id, 'cancel');
    }

    private function change(Request $request, AppointmentActions $actions, int $id, string $action)
    {
        [$http, $message, $data] = $actions->run($request->user(), $id, $action);

        return $http === 200 ? $this->ok($data, $message) : $this->fail($message, $http);
    }

    // ------------------------------------------------------------ Phase 2

    /**
     * APPT-7 — free slots for the chosen staff and services on a date. This is the
     * web's own booking engine (see SlotEngine), so the app offers exactly what the
     * website and the web reschedule dialog offer.
     */
    public function slots(Request $request, SlotEngine $engine)
    {
        $in = $request->validate([
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:today'],
            'staff_ids' => ['required'],
            'service_ids' => ['required'],
        ]);

        $staffIds = $this->idList($in['staff_ids']);
        $serviceIds = $this->idList($in['service_ids']);

        if ($staffIds === [] || $serviceIds === []) {
            return $this->fail('Please choose at least one barber and one service.', 422, [
                'errors' => ['staff_ids' => ['Please choose at least one barber and one service.']],
            ]);
        }

        return $this->ok($engine->find($staffIds, $serviceIds, $in['date']));
    }

    /** APPT-10 — barbers that can do the chosen services (web: get_staff_by_service). */
    public function staffByService(Request $request, AppointmentBooking $booking)
    {
        $request->validate(['service_ids' => ['required']]);
        $serviceIds = $this->idList($request->query('service_ids'));

        if ($serviceIds === []) {
            return $this->fail('No service IDs provided', 422, ['errors' => ['service_ids' => ['No service IDs provided']]]);
        }

        return $this->ok(['staff' => $booking->staffByService($serviceIds)]);
    }

    /** APPT-6 — move a Pending or Cancelled appointment to another slot; it becomes Rescheduled. */
    public function reschedule(Request $request, AppointmentBooking $booking, int $id)
    {
        $in = $request->validate([
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:today'],
            'slot_start' => ['required', 'date_format:H:i'],
            'slot_end' => ['required', 'date_format:H:i', 'after:slot_start'],
        ]);

        return $this->respond($booking->reschedule($request->user(), $id, $in));
    }

    /** APPT-8 — new booking from the calendar (walk-in / phone). */
    public function store(Request $request, AppointmentBooking $booking)
    {
        return $this->respond($booking->create($request->user(), $this->bookingInput($request)));
    }

    /** APPT-9 — edit a booking from the calendar. */
    public function update(Request $request, AppointmentBooking $booking, int $id)
    {
        return $this->respond($booking->update($request->user(), $id, $this->bookingInput($request)));
    }

    private function bookingInput(Request $request): array
    {
        return $request->validate([
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:today'],
            'time' => ['required', 'date_format:H:i'],
            'staff_id' => ['required', 'integer', Rule::exists('users', 'id')->where(fn ($q) => $q->where('role', 'Staff')->whereNull('deleted_at'))],
            'services' => ['required', 'array', 'min:1', 'max:30'],
            'services.*.id' => ['required', 'integer', Rule::exists('tbl_service', 'id')->whereNull('deleted_at')],
            'services.*.qty' => ['nullable', 'integer', 'between:1,20'],
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['required', 'string', 'max:25'],
            'email' => ['nullable', 'email', 'max:255'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]);
    }

    /** Turns a service's [http, message, data] into the right envelope. */
    private function respond(array $result)
    {
        [$http, $message, $data] = $result;

        return $http < 400 ? $this->ok($data, $message, $http) : $this->fail($message, $http, $data);
    }

    /** "1,2,3" or [1,2,3] or ["1","2"] → [1,2,3] (repeats are kept: they mean quantity). */
    private function idList($value): array
    {
        $parts = is_array($value) ? $value : explode(',', (string) $value);

        return array_values(array_filter(array_map('intval', array_map('trim', $parts)), fn ($n) => $n > 0));
    }
}
