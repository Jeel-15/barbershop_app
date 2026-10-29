<?php

namespace App\Services\Api;

use App\Models\Breaks;
use App\Models\Slot;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * A staff member's own weekly working hours (web: Admin\WorkinghoursController).
 *
 * Each weekday is a row in tbl_slots (staff_id = me). The hours of that day are
 * "blocks" stored in tbl_breaks with break_type = 1 (09:00–13:00, 14:00–18:00 …).
 * Adding the first block turns the day on, deleting the last block turns it off.
 *
 * The web checks none of the ids it receives; here every day and block must belong
 * to the signed-in staff member.
 */
class WorkingHours
{
    public function week(User $user): array
    {
        $days = DB::table('tbl_slots')->where('staff_id', $user->id)->orderBy('id')->get();

        return $days->map(function ($day) use ($user) {
            $blocks = DB::table('tbl_breaks')
                ->where('slot_id', $day->id)->where('staff_id', $user->id)->where('break_type', 1)
                ->orderBy('break_start')->get(['id', 'break_start', 'break_end']);

            return [
                'slot_id' => (int) $day->id,
                'day_name' => $day->day_name,
                'is_day_off' => (bool) $day->is_day_off,
                'blocks' => $blocks->map(fn ($b) => [
                    'id' => (int) $b->id,
                    'start' => substr($b->break_start, 0, 5),
                    'end' => substr($b->break_end, 0, 5),
                    'start_label' => Carbon::parse($b->break_start)->format('h:i A'),
                    'end_label' => Carbon::parse($b->break_end)->format('h:i A'),
                ])->values()->all(),
            ];
        })->values()->all();
    }

    /** @return array{0:int,1:string,2:array} */
    public function addBlock(User $user, int $slotId, string $start, string $end): array
    {
        $day = Slot::where('id', $slotId)->where('staff_id', $user->id)->first();
        if (!$day) {
            return [404, 'Day not found.', []];
        }

        if ($this->overlaps($user->id, $slotId, $start, $end, null)) {
            return [409, 'This time slot overlaps with an existing working hour. Please choose another time.', []];
        }

        $block = Breaks::create([
            'slot_id' => $slotId,
            'staff_id' => $user->id,
            'break_start' => $start,
            'break_end' => $end,
            'break_type' => 1,
        ]);

        Slot::where('id', $slotId)->update(['is_day_off' => 0]);

        return [201, 'Working Hours Added Successfully.', ['block' => $this->shape($block), 'is_day_off' => false]];
    }

    /** @return array{0:int,1:string,2:array} */
    public function updateBlock(User $user, int $blockId, string $start, string $end): array
    {
        $block = $this->ownBlock($user, $blockId);
        if (!$block) {
            return [404, 'Working hours not found.', []];
        }

        if ($this->overlaps($user->id, (int) $block->slot_id, $start, $end, $blockId)) {
            return [409, 'This time slot overlaps with an existing working hour. Please choose another time.', []];
        }

        $block->update(['break_start' => $start, 'break_end' => $end]);

        return [200, 'Working Hours Updated Successfully.', ['block' => $this->shape($block->fresh())]];
    }

    /** @return array{0:int,1:string,2:array} */
    public function deleteBlock(User $user, int $blockId): array
    {
        $block = $this->ownBlock($user, $blockId);
        if (!$block) {
            return [404, 'Working hours not found.', []];
        }

        $slotId = (int) $block->slot_id;
        $block->delete();

        $left = Breaks::where('slot_id', $slotId)->where('staff_id', $user->id)->where('break_type', 1)->exists();
        if (!$left) {
            Slot::where('id', $slotId)->update(['is_day_off' => 1]);
        }

        return [200, 'Working hours deleted successfully.', ['is_day_off' => !$left]];
    }

    /** @return array{0:int,1:string,2:array} */
    public function setDayOff(User $user, int $slotId, bool $off): array
    {
        $updated = DB::table('tbl_slots')->where('id', $slotId)->where('staff_id', $user->id)
            ->update(['is_day_off' => $off ? 1 : 0, 'updated_at' => now()]);

        if (!$updated && !DB::table('tbl_slots')->where('id', $slotId)->where('staff_id', $user->id)->exists()) {
            return [404, 'Day not found.', []];
        }

        return [200, 'Day off status updated successfully', ['slot_id' => $slotId, 'is_day_off' => $off]];
    }

    // ---------------------------------------------------------------- helpers

    private function ownBlock(User $user, int $blockId): ?Breaks
    {
        return Breaks::where('id', $blockId)->where('staff_id', $user->id)->where('break_type', 1)->first();
    }

    /** web: another type-1 block of the same day overlaps [start, end). */
    private function overlaps(int $staffId, int $slotId, string $start, string $end, ?int $excludeId): bool
    {
        return Breaks::where('slot_id', $slotId)
            ->where('staff_id', $staffId)
            ->where('break_type', 1)
            ->when($excludeId, fn ($q) => $q->where('id', '!=', $excludeId))
            ->where('break_start', '<', $end)
            ->where('break_end', '>', $start)
            ->exists();
    }

    private function shape(Breaks $b): array
    {
        return [
            'id' => (int) $b->id,
            'slot_id' => (int) $b->slot_id,
            'start' => substr($b->break_start, 0, 5),
            'end' => substr($b->break_end, 0, 5),
        ];
    }
}
