<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\StaffService;
use App\Models\User;
use App\Services\Api\Money;
use App\Services\Api\UserPresenter;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

/**
 * ME-1 / ME-2 — mirrors Admin\ProfileController (view and edit own profile).
 * Open to every signed-in user, exactly like the web's profile page.
 */
class ProfileController extends ApiController
{
    public function show(Request $request)
    {
        return $this->ok($this->payload($request->user()));
    }

    /**
     * Multipart form (photo upload). Send as POST; PUT would not carry files in PHP.
     * web: name, email (unique), phone (max 20), profile_image (image, 2 MB).
     */
    public function update(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'phone' => ['nullable', 'string', 'max:20'],
            'profile_image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)],
        ]);

        $user->name = $data['name'];
        $user->email = $data['email'];
        $user->phone = $data['phone'] ?? null;

        if ($request->hasFile('profile_image')) {
            if (!empty($user->profile_img) && Storage::disk('public')->exists($user->profile_img)) {
                Storage::disk('public')->delete($user->profile_img);
            }
            $user->profile_img = $request->file('profile_image')->store('profile_images', 'public');
        }

        $user->save();

        return $this->ok($this->payload($user->fresh()), 'Profile updated successfully.');
    }

    private function payload(User $user): array
    {
        $ids = StaffService::idsForStaff($user->id);

        $services = empty($ids) ? [] : DB::table('tbl_service as s')
            ->whereIn('s.id', $ids)
            ->whereNull('s.deleted_at')
            ->orderBy('s.service_name')
            ->pluck('s.service_name')
            ->all();

        return [
            'user' => UserPresenter::make($user),
            'services' => $services,
            // web: only staff get the statistics block
            'stats' => $user->isStaffUser() ? $this->staffStats($user->id) : null,
        ];
    }

    /**
     * Port of ProfileController::staffStats (completed appointments only).
     */
    private function staffStats(int $id): array
    {
        $totalAppointments = DB::table('tbl_appointment as a')
            ->join('tbl_appointment_service as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->where('b.staff_id', $id)
            ->where('is_invoiced', 1)
            ->count('b.appointment_id');

        $serviceSub = DB::table('tbl_appointment_service as s')
            ->select(
                's.appointment_id',
                DB::raw('SUM(s.service_commission) as total_service_commission'),
                DB::raw('SUM(s.service_tip) as total_service_tip')
            )
            ->where('s.staff_id', $id)
            ->groupBy('s.appointment_id');

        $productSub = DB::table('tbl_appointment_product as p')
            ->select('p.appointment_id', DB::raw('SUM(p.product_commision) as total_product_commission'))
            ->where('p.staff_id', $id)
            ->groupBy('p.appointment_id');

        $earning = DB::table('tbl_appointment as a')
            ->leftJoinSub($serviceSub, 's', fn ($join) => $join->on('a.appointment_id', '=', 's.appointment_id'))
            ->leftJoinSub($productSub, 'p', fn ($join) => $join->on('a.appointment_id', '=', 'p.appointment_id'))
            ->where('a.status', 1)
            ->selectRaw('
                COALESCE(SUM(s.total_service_tip),0) as total_service_tip,
                COALESCE(SUM(s.total_service_commission),0) as total_service_commission,
                COALESCE(SUM(p.total_product_commission),0) as total_product_commission
            ')
            ->first();

        $totalVisit = DB::table('tbl_appointment_service as s')
            ->join('tbl_appointment as a', 's.appointment_id', '=', 'a.appointment_id')
            ->where('s.staff_id', $id)
            ->where('a.is_invoiced', 1)
            ->distinct('a.appointment_id')
            ->count('a.customer_id');

        $tip = (float) ($earning->total_service_tip ?? 0);
        $serviceCommission = (float) ($earning->total_service_commission ?? 0);
        $productCommission = (float) ($earning->total_product_commission ?? 0);

        return [
            'appointments' => (int) $totalAppointments,
            'visits' => (int) $totalVisit,
            'tips' => Money::str($tip),
            'service_commission' => Money::str($serviceCommission),
            'product_commission' => Money::str($productCommission),
            'total_earning' => Money::str($tip + $serviceCommission + $productCommission),
        ];
    }
}
