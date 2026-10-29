<?php

namespace App\Services\Api;

use App\Models\Breaks;
use App\Models\User;
use Carbon\Carbon;

/**
 * "Add break" on the calendar (web: AppointmentController::breakFormSubmit).
 *
 * Creates an ad-hoc break (break_type 2, slot_id 0) that starts NOW and lasts
 * hour:minute, or covers the rest of the day. The break belongs to the day it was
 * created (the web keys ad-hoc breaks on created_at). Times are stored in the
 * `time` columns, so only the time part is kept, exactly as the web does.
 */
class CalendarBreaks
{
    /** @return array{0:int,1:string,2:array} */
    public function create(User $user, array $in): array
    {
        $staffId = (int) $in['staff_id'];

        if ($user->isStaffUser() && $staffId !== (int) $user->id) {
            return [403, 'You can only add breaks to your own calendar.', []];
        }

        $rest = !empty($in['rest_of_day']);
        $now = Carbon::now();

        if ($rest) {
            $start = $now->format('Y-m-d') . ' 00:00:00';
            $end = $now->format('Y-m-d') . ' 23:59:59';
        } else {
            $hours = (int) ($in['hour'] ?? 0);
            $minutes = (int) ($in['minute'] ?? 0);

            if ($hours + $minutes <= 0) {
                return [422, 'Please choose how long the break lasts.', ['errors' => ['hour' => ['Please choose how long the break lasts.']]]];
            }

            $start = $now->copy();
            $end = $now->copy()->addHours($hours)->addMinutes($minutes);
        }

        $break = Breaks::create([
            'slot_id' => 0,
            'break_start' => $start,
            'break_end' => $end,
            'staff_id' => $staffId,
            'break_type' => 2,
        ]);

        return [201, 'SuccessFully Created Break', ['break' => [
            'id' => (int) $break->id,
            'staff_id' => $staffId,
            'date' => $now->format('Y-m-d'),
            'start' => Carbon::parse($start)->format('H:i'),
            'end' => Carbon::parse($end)->format('H:i'),
            'rest_of_day' => $rest,
        ]]];
    }
}
