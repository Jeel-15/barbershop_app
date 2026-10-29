<?php

namespace App\Services\Api;

use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The numbers on the dashboard cards, with the exact rules of
 * DashboardController::index (including its quirks, see docs/API_PLAN.md
 * Section 8). Where the web's figure is questionable the formula is still the
 * web's so the app shows the same number the owner already sees.
 */
class DashboardReader
{
    public function summary(User $user): array
    {
        $isStaff = $user->isStaffUser();            // web: $user->role === 'Staff'
        $today = Carbon::today()->toDateString();

        // web: join to service lines (inner), staff => own lines, DISTINCT appointments
        $countStatus = function (int $status) use ($isStaff, $user) {
            return (int) DB::table('tbl_appointment as a')
                ->join('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
                ->where('a.status', $status)
                ->when($isStaff, fn ($q) => $q->where('s.staff_id', $user->id))
                ->distinct()
                ->count('a.appointment_id');
        };

        $upcoming = (int) DB::table('tbl_appointment as a')
            ->join('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
            ->when($isStaff, fn ($q) => $q->where('s.staff_id', $user->id))
            ->where('a.date', '>', $today)
            ->where('a.is_invoiced', null)
            ->distinct()
            ->count('a.appointment_id');

        $data = [
            'scope' => $isStaff ? 'staff' : 'admin',
            'appointments' => [
                'upcoming' => $upcoming,
                'completed' => $countStatus(1),
                'cancelled' => $countStatus(2),
                'confirmed' => $countStatus(3),
                'rescheduled' => $countStatus(4),
            ],
            'customers' => (int) DB::table('customers')->count('customer_id'),
        ];

        // web: only users.role == 'Admin' see shop revenue; everyone else sees what they earn.
        if ($user->role == 'Admin') {
            $revenue = DB::table('tbl_appointment')
                ->select(DB::raw('SUM(total_amt - total_tax - total_tip) as total_revenue'))
                ->first();
            // web quirk Q29: the tip total joins service lines, so a tip is counted once per line
            $tips = DB::table('tbl_appointment as a')
                ->join('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
                ->sum('a.total_tip');

            $data['money'] = [
                'kind' => 'revenue',
                'revenue' => Money::str($revenue->total_revenue ?? 0),
                'tips' => Money::str($tips),
            ];
        } else {
            $tips = DB::table('tbl_appointment_service as s')->where('s.staff_id', $user->id)->sum('s.service_tip');
            $serviceCommission = DB::table('tbl_appointment_service as s')->where('s.staff_id', $user->id)->sum('s.service_commission');
            $productCommission = DB::table('tbl_appointment_product as p')->where('p.staff_id', $user->id)->sum('p.product_commision');
            $commission = $serviceCommission + $productCommission;

            $data['money'] = [
                'kind' => 'earnings',
                'revenue' => Money::str($tips + $commission),      // web calls this "revenue" for staff
                'tips' => Money::str($tips),
                'commission' => Money::str($commission),
            ];
        }

        // Which dashboard blocks the web draws for this user (@can in the view).
        $data['widgets'] = [
            'today' => $user->can('Dashboard-Today_Appointments'),
            'upcoming' => $user->can('Dashboard-Upcoming_Appointments'),
            'top_services' => $user->can('Dashboard-Top_Services'),
            'top_products' => $user->can('Dashboard-Top_Selling_Product'),
        ];

        return $data;
    }
}
