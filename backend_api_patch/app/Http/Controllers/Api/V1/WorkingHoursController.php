<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\WorkingHours;
use Illuminate\Http\Request;

/**
 * ME-7 .. ME-11 — a staff member's own working hours (web: WorkinghoursController).
 * Route middleware: staff only + `Calender-View`, exactly like the web.
 */
class WorkingHoursController extends ApiController
{
    public function index(Request $request, WorkingHours $hours)
    {
        return $this->ok(['days' => $hours->week($request->user())]);
    }

    public function store(Request $request, WorkingHours $hours)
    {
        $in = $request->validate([
            'day_id' => ['required', 'integer'],
            'start_time' => ['required', 'date_format:H:i'],
            'end_time' => ['required', 'date_format:H:i', 'after:start_time'],
        ]);

        return $this->respond($hours->addBlock($request->user(), (int) $in['day_id'], $in['start_time'], $in['end_time']));
    }

    public function update(Request $request, WorkingHours $hours, int $id)
    {
        $in = $request->validate([
            'start_time' => ['required', 'date_format:H:i'],
            'end_time' => ['required', 'date_format:H:i', 'after:start_time'],
        ]);

        return $this->respond($hours->updateBlock($request->user(), $id, $in['start_time'], $in['end_time']));
    }

    public function destroy(Request $request, WorkingHours $hours, int $id)
    {
        return $this->respond($hours->deleteBlock($request->user(), $id));
    }

    public function dayOff(Request $request, WorkingHours $hours, int $slotId)
    {
        $in = $request->validate(['off' => ['required', 'boolean']]);

        return $this->respond($hours->setDayOff($request->user(), $slotId, (bool) $in['off']));
    }

    private function respond(array $result)
    {
        [$http, $message, $data] = $result;

        return $http < 400 ? $this->ok($data, $message, $http) : $this->fail($message, $http, $data);
    }
}
