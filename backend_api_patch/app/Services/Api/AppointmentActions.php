<?php

namespace App\Services\Api;

use App\Models\Appointment;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Confirm / cancel an appointment.
 *
 * web: AppointmentController::confirm_reject_action sets `status` to whatever
 * integer it is sent (3 = confirm, 2 = cancel from the buttons). The API keeps
 * those two outcomes but only allows the transitions the web's buttons offer,
 * refuses anything on a completed appointment, and lets a staff member act only
 * on appointments that have one of their own service lines.
 */
class AppointmentActions
{
    /** action => [target status, statuses it may start from] */
    private const RULES = [
        'confirm' => [3, [0, 4]],        // web shows "Confirm" for Pending and Rescheduled
        'cancel' => [2, [0, 3, 4]],      // web shows "Cancel" for Pending, Confirmed, Rescheduled
    ];

    /**
     * @return array{0:int,1:string,2:array} [http status, message, data]
     */
    public function run(User $user, int $id, string $action): array
    {
        [$target, $from] = self::RULES[$action];

        return DB::transaction(function () use ($user, $id, $target, $from, $action) {
            $row = DB::table('tbl_appointment')->where('appointment_id', $id)->lockForUpdate()->first();

            if (!$row || ($user->isStaffUser() && !$this->staffHasLine($user->id, $id))) {
                return [404, 'Appointment not found.', []];
            }

            $current = (int) $row->status;
            $verb = $action === 'confirm' ? 'confirmed' : 'cancelled';

            if ($current === $target) {
                return [409, 'This appointment is already ' . $verb . '.', ['status' => $current]];
            }

            if (!in_array($current, $from, true)) {
                return [409, 'A ' . strtolower(Appointment::statusLabel($current)) . ' appointment cannot be ' . $verb . '.', ['status' => $current]];
            }

            DB::table('tbl_appointment')->where('appointment_id', $id)->update([
                'status' => $target,
                'updated_at' => now(),
            ]);

            return [200, 'Appointment status updated successfully.', [
                'appointment' => [
                    'id' => $id,
                    'status' => $target,
                    'status_key' => AppointmentReader::STATUS_KEYS[$target],
                    'status_label' => Appointment::statusLabel($target),
                    'actions' => AppointmentReader::actionsFor($target),
                ],
            ]];
        });
    }

    private function staffHasLine(int $staffId, int $appointmentId): bool
    {
        return DB::table('tbl_appointment_service')
            ->where('appointment_id', $appointmentId)
            ->where('staff_id', $staffId)
            ->exists();
    }
}
