<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\ServiceCategory;
use App\Services\Api\CalendarBreaks;
use App\Services\Api\CalendarReader;
use App\Services\Api\Money;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * CAL-1 .. CAL-3 — the calendar (web: AppointmentController calender* / fetch /
 * fetchStaffAvailability / breakFormSubmit). Needs `Calender-View` (route middleware).
 */
class CalendarController extends ApiController
{
    /** Longest range one call may ask for (the web has no limit and returns everything). */
    private const MAX_DAYS = 62;

    public function events(Request $request, CalendarReader $calendar)
    {
        $in = $request->validate([
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
            'staff_id' => ['nullable', 'integer', 'min:1'],
        ]);

        if (Carbon::parse($in['from'])->diffInDays(Carbon::parse($in['to'])) > self::MAX_DAYS) {
            return $this->fail('Please ask for at most ' . self::MAX_DAYS . ' days at a time.', 422, [
                'errors' => ['to' => ['Please ask for at most ' . self::MAX_DAYS . ' days at a time.']],
            ]);
        }

        $user = $request->user();

        return $this->ok([
            'range' => ['from' => $in['from'], 'to' => $in['to']],
            'lanes' => $calendar->lanes($user),
            'events' => $calendar->events($user, $in['from'], $in['to'], isset($in['staff_id']) ? (int) $in['staff_id'] : null),
        ]);
    }

    /**
     * The services a booking can contain (web: the calendar page gets Service::get()).
     * Prices and durations only: commissions are not for the booking form.
     */
    public function bookingOptions()
    {
        $categories = ServiceCategory::with(['services' => fn ($q) => $q->where('status', 1)->orderBy('service_name')])
            ->orderBy('category_name')->get()
            ->map(fn ($c) => [
                'id' => (int) $c->id,
                'name' => $c->category_name,
                'services' => $c->services->map(fn ($s) => [
                    'id' => (int) $s->id,
                    'name' => $s->service_name,
                    'price' => Money::str($s->price),
                    'duration' => (int) $s->duration,
                ])->values()->all(),
            ])->filter(fn ($c) => count($c['services']) > 0)->values()->all();

        return $this->ok(['categories' => $categories]);
    }

    public function availability(Request $request, CalendarReader $calendar)
    {
        $in = $request->validate([
            'date' => ['required', 'date_format:Y-m-d'],
            'staff_id' => ['nullable', 'integer', 'min:1'],
        ]);

        return $this->ok($calendar->availability($request->user(), $in['date'], isset($in['staff_id']) ? (int) $in['staff_id'] : null));
    }

    public function addBreak(Request $request, CalendarBreaks $breaks)
    {
        $in = $request->validate([
            'staff_id' => ['required', 'integer', Rule::exists('users', 'id')->where(fn ($q) => $q->where('role', 'Staff')->whereNull('deleted_at'))],
            'rest_of_day' => ['nullable', 'boolean'],
            'hour' => ['nullable', 'integer', 'between:0,23'],
            'minute' => ['nullable', 'integer', 'between:0,59'],
        ]);

        [$http, $message, $data] = $breaks->create($request->user(), $in);

        return $http < 400 ? $this->ok($data, $message, $http) : $this->fail($message, $http, $data);
    }
}
