<?php

namespace App\Services\Api;

use App\Http\Controllers\Website\WebsiteController;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Availability = the web's own booking engine, called directly.
 *
 * WebsiteController::get_slot_by_staff is a public method that only reads the
 * database. Calling it (instead of copying its ~1,000 lines) guarantees the app
 * offers exactly the slots the website and the web reschedule dialog offer, and
 * keeps doing so if the web engine is fixed later. The web project is not edited.
 */
class SlotEngine
{
    /**
     * @param  int[]  $staffIds    barbers to check ("First available" pseudo-user allowed)
     * @param  int[]  $serviceIds  services, repeated for quantity
     * @return array{available:bool,message:?string,date:string,duration:int,slots:array,groups:array}
     */
    public function find(array $staffIds, array $serviceIds, string $date): array
    {
        $day = Carbon::createFromFormat('Y-m-d', $date)->startOfDay();

        // The web's JavaScript sends a 0-based month (JS Date), the engine adds 1 back.
        $request = Request::create('/', 'POST', [
            'selectedYear' => $day->year,
            'selectedMonth' => $day->month - 1,
            'selectedDay' => $day->day,
            'staff_id' => implode(',', $staffIds),
            'service_id' => implode(',', $serviceIds),
            'day_name' => $day->format('l'),
        ]);

        $data = app(WebsiteController::class)->get_slot_by_staff($request)->getData(true);

        $ok = (int) ($data['status'] ?? 0) === 1;

        return [
            'available' => $ok && !empty($data['slots'] ?? []),
            'message' => $ok ? ($data['message'] ?? null) : ($data['message'] ?? 'No available slots for this date.'),
            'date' => $date,
            'duration' => (int) ($data['duration'] ?? 0),
            'slots' => array_values(array_map(fn ($s) => $this->slot($s), $data['slots'] ?? [])),
            'groups' => array_values(array_map(function ($g) {
                return [
                    'key' => (string) ($g['key'] ?? ''),
                    'staff_id' => (string) ($g['staff_id'] ?? ''),
                    'staff_name' => $g['staff_name'] ?? '',
                    'is_first_available' => (bool) ($g['flexible'] ?? false),
                    'duration' => (int) ($g['duration'] ?? 0),
                    'services' => $g['services'] ?? [],
                    'slots' => array_values(array_map(fn ($s) => $this->slot($s), $g['slots'] ?? [])),
                ];
            }, $data['groups'] ?? [])),
        ];
    }

    private function slot(array $s): array
    {
        return [
            'start' => $s['start'],
            'end' => $s['end'],
            'start_label' => Carbon::parse($s['start'])->format('h:i A'),
            'end_label' => Carbon::parse($s['end'])->format('h:i A'),
        ];
    }

    /** True when the engine offers exactly this start/end pair on that day. */
    public function offers(array $staffIds, array $serviceIds, string $date, string $start, string $end): bool
    {
        foreach ($this->find($staffIds, $serviceIds, $date)['slots'] as $slot) {
            if ($slot['start'] === $start && $slot['end'] === $end) {
                return true;
            }
        }

        return false;
    }
}
