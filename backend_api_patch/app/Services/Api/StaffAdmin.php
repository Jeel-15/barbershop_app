<?php

namespace App\Services\Api;

use App\Models\Appointment;
use App\Models\Role;
use App\Models\Service;
use App\Models\StaffService;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;

/**
 * STAFF-1 .. STAFF-12 — staff administration (web: StaffController,
 * StaffServiceController). Only users whose panel role is Staff or Accountant
 * are manageable here, like the web's staff table.
 */
class StaffAdmin
{
    /** roles the form offers: everything except Super-admin (1) and POS Manager (4), web rule */
    public static function assignableRoleIds(): array
    {
        return Role::whereNotIn('id', [1, 4])->pluck('id')->map(fn ($i) => (int) $i)->all();
    }

    public function formOptions(): array
    {
        return [
            'roles' => Role::whereNotIn('id', [1, 4])->orderBy('id')->get()->map(fn ($r) => ['id' => (int) $r->id, 'name' => $r->name])->all(),
            'services' => Service::orderBy('service_name')->get()->map(fn ($s) => ['id' => (int) $s->id, 'name' => $s->service_name, 'active' => (int) $s->status === 1])->all(),
        ];
    }

    // ------------------------------------------------------------------ list / one

    /** @return array{0: array, 1: int} */
    public function paginate(array $f, int $page, int $perPage): array
    {
        $q = User::query()
            ->leftJoin('tbl_staff_service', 'tbl_staff_service.staff_id', '=', 'users.id')
            ->leftJoin('tbl_service', function ($join) {
                $join->on('tbl_service.id', '=', 'tbl_staff_service.service_id')->whereNull('tbl_service.deleted_at');
            })
            ->leftJoin('model_has_roles', 'model_has_roles.model_id', '=', 'users.id')
            ->whereIn('users.role', ['Staff', 'Accountant'])
            ->when(isset($f['barber']) && $f['barber'] !== '', fn ($w) => $w->where('users.is_barber', (int) $f['barber']))
            ->when(isset($f['active']) && $f['active'] !== '', fn ($w) => $w->where('users.active_status', (int) $f['active']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($s) => $s->where('users.name', 'like', $like)->orWhere('users.email', 'like', $like)
                    ->orWhere('users.phone', 'like', $like)->orWhere('tbl_service.service_name', 'like', $like));
            });

        $total = (int) (clone $q)->distinct()->count('users.id');

        $rows = (clone $q)->select(
            'users.id', 'users.name', 'users.email', 'users.phone', 'users.role', 'users.service_id', 'users.commission',
            'users.is_barber', 'users.profile_img', 'users.active_status', 'users.created_at',
            DB::raw('GROUP_CONCAT(DISTINCT tbl_service.service_name SEPARATOR ", ") as service_names'),
            DB::raw('GROUP_CONCAT(DISTINCT model_has_roles.role_id SEPARATOR ",") as role_ids')
        )->groupBy('users.id', 'users.name', 'users.email', 'users.phone', 'users.role', 'users.service_id', 'users.commission', 'users.is_barber', 'users.profile_img', 'users.active_status', 'users.created_at')
            ->orderBy('users.name')->orderBy('users.id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($r) => $this->row($r))->all(), $total];
    }

    private function row($r): array
    {
        $roleIds = array_values(array_filter(array_map('intval', explode(',', (string) ($r->role_ids ?? '')))));

        return [
            'id' => (int) $r->id,
            'name' => $r->name,
            'email' => $r->email,
            'phone' => $r->phone,
            'panel_role' => $r->role,
            'role_ids' => $roleIds,
            'role_names' => $roleIds ? Role::whereIn('id', $roleIds)->pluck('name')->all() : [],
            'commission' => Money::str($r->commission ?? 0),
            'is_barber' => (int) $r->is_barber === 1,
            'active' => (int) $r->active_status === 1,
            'service_names' => $r->service_names ?? '',
            'photo_url' => Media::avatar($r->profile_img),
            'created_at' => optional($r->created_at)->toDateString(),
        ];
    }

    /** a manageable user (Staff or Accountant) */
    public function find(int $id): ?User
    {
        return User::where('id', $id)->whereIn('role', ['Staff', 'Accountant'])->first();
    }

    public function one(int $id): ?array
    {
        $u = $this->find($id);
        if (!$u) {
            return null;
        }
        $r = User::query()
            ->leftJoin('tbl_staff_service', 'tbl_staff_service.staff_id', '=', 'users.id')
            ->leftJoin('tbl_service', function ($join) {
                $join->on('tbl_service.id', '=', 'tbl_staff_service.service_id')->whereNull('tbl_service.deleted_at');
            })
            ->leftJoin('model_has_roles', 'model_has_roles.model_id', '=', 'users.id')
            ->where('users.id', $id)
            ->select(
                'users.id', 'users.name', 'users.email', 'users.phone', 'users.role', 'users.service_id', 'users.commission',
                'users.is_barber', 'users.profile_img', 'users.active_status', 'users.created_at',
                DB::raw('GROUP_CONCAT(DISTINCT tbl_service.service_name SEPARATOR ", ") as service_names'),
                DB::raw('GROUP_CONCAT(DISTINCT model_has_roles.role_id SEPARATOR ",") as role_ids')
            )->groupBy('users.id', 'users.name', 'users.email', 'users.phone', 'users.role', 'users.service_id', 'users.commission', 'users.is_barber', 'users.profile_img', 'users.active_status', 'users.created_at')
            ->first();

        return $r ? $this->row($r) + ['service_ids' => StaffService::idsForStaff($id)] : null;
    }

    // ------------------------------------------------------------------ write

    /** web: StaffController::store */
    public function create(User $by, array $in, ?UploadedFile $photo): int
    {
        return DB::transaction(function () use ($by, $in, $photo) {
            $role = Role::findOrFail($in['role_id']);
            $panelRole = $role->name === 'Accountant' ? 'Accountant' : 'Staff';
            $isBarber = $panelRole === 'Staff' && $in['is_barber'];

            $u = new User();
            $u->created_by = $by->id;
            $this->fill($u, $in, $panelRole, $isBarber);
            $u->password = Hash::make($in['password']);
            if ($photo) {
                $u->profile_img = $photo->store('profile_images', 'public');
            }
            $u->save();
            $u->assignRole($role->name);

            StaffService::syncForStaff($u->id, $isBarber ? $in['service_ids'] : []);

            // web: every panel Staff gets a week of slot rows and two default blocks per day, stored
            // as break_type 2 (docs/API_PLAN.md Q40)
            if ($panelRole === 'Staff') {
                foreach (ShopAdmin::DAYS as $day) {
                    $slotId = DB::table('tbl_slots')->insertGetId([
                        'day_name' => $day, 'staff_id' => $u->id, 'is_day_off' => 0, 'open_time' => null, 'close_time' => null,
                        'created_at' => now(), 'updated_at' => now(),
                    ]);
                    foreach ([['09:00:00', '13:00:00'], ['14:00:00', '18:00:00']] as [$s, $e]) {
                        DB::table('tbl_breaks')->insert([
                            'slot_id' => $slotId, 'break_start' => $s, 'break_end' => $e, 'created_at' => now(), 'updated_at' => now(),
                            'staff_id' => $u->id, 'break_type' => 2,
                        ]);
                    }
                }
            }

            return (int) $u->id;
        });
    }

    /** web: StaffController::update */
    public function update(User $u, array $in, ?UploadedFile $photo): void
    {
        DB::transaction(function () use ($u, $in, $photo) {
            $role = Role::findOrFail($in['role_id']);
            $panelRole = $role->name === 'Accountant' ? 'Accountant' : 'Staff';
            $isBarber = $panelRole === 'Staff' && $in['is_barber'];

            $this->fill($u, $in, $panelRole, $isBarber);
            if (!empty($in['password'])) {
                $u->password = Hash::make($in['password']);
            }
            if ($photo) {
                $this->deleteFile($u->profile_img);
                $u->profile_img = $photo->store('profile_images', 'public');
            }
            $u->syncRoles([$role->name]);
            $u->save();

            StaffService::syncForStaff($u->id, $isBarber ? $in['service_ids'] : []);
        });

        // a changed password, a deactivated account or a new role must not keep old app sessions
        if (!empty($in['password']) || !$in['active_status']) {
            $u->tokens()->delete();
        }
    }

    private function fill(User $u, array $in, string $panelRole, bool $isBarber): void
    {
        $u->name = $in['name'];
        $u->email = $in['email'];
        $u->phone = $in['phone'] ?? null;
        $u->commission = $isBarber ? ($in['commission'] ?? 0) : 0;
        $u->active_status = $in['active_status'] ? 1 : 0;
        $u->role = $panelRole;
        $u->is_barber = $isBarber ? 1 : 0;
        $u->service_id = $isBarber ? implode(',', $in['service_ids']) : null;
    }

    public function delete(User $u): void
    {
        $this->deleteFile($u->profile_img);
        $u->tokens()->delete();
        $u->delete();
    }

    public function changePassword(User $u, string $password): void
    {
        $u->password = Hash::make($password);
        $u->save();
        $u->tokens()->delete();   // the old password's app sessions end
    }

    public function syncServices(User $staff, array $serviceIds): void
    {
        StaffService::syncForStaff($staff->id, $serviceIds);
    }

    private function deleteFile(?string $path): void
    {
        if ($path && Storage::disk('public')->exists($path)) {
            Storage::disk('public')->delete($path);
        }
    }

    // ------------------------------------------------------------------ profile numbers (web: staff_profile + its three tables)

    /** web: StaffController::staff_profile (the cards). Note Q40: revenue/appointments/visits are shop-wide for completed appointments. */
    public function profile(int $id, array $f): array
    {
        $totalAppointments = DB::table('tbl_appointment as a')
            ->join('tbl_appointment_service as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->where('b.staff_id', $id)->where('is_invoiced', 1)->count('b.appointment_id');

        $serviceSub = DB::table('tbl_appointment_service as s')
            ->select('s.appointment_id', DB::raw('SUM(s.total_amt) as total_service_amount'), DB::raw('SUM(s.service_commission) as total_service_commission'), DB::raw('SUM(s.service_tip) as total_service_tip'))
            ->where('s.staff_id', $id)->groupBy('s.appointment_id');
        $productSub = DB::table('tbl_appointment_product as p')
            ->select('p.appointment_id', DB::raw('SUM(p.amount) as total_product_amount'), DB::raw('SUM(p.product_commision) as total_product_commission'))
            ->where('p.staff_id', $id)->groupBy('p.appointment_id');

        $e = DB::table('tbl_appointment as a')
            ->leftJoinSub($serviceSub, 's', fn ($j) => $j->on('a.appointment_id', '=', 's.appointment_id'))
            ->leftJoinSub($productSub, 'p', fn ($j) => $j->on('a.appointment_id', '=', 'p.appointment_id'))
            ->when(!empty($f['start_date']), fn ($q) => $q->whereDate('a.date', '>=', $f['start_date']))
            ->when(!empty($f['end_date']), fn ($q) => $q->whereDate('a.date', '<=', $f['end_date']))
            ->where('a.status', 1)
            ->selectRaw('
                SUM(a.total_amt - a.total_tax - a.total_tip) as total_revenue,
                COUNT(DISTINCT a.appointment_id) as total_appointments,
                COUNT(DISTINCT a.customer_id) as total_visits,
                SUM(a.total_tip) as total_tips,
                COALESCE(SUM(s.total_service_tip),0) as total_service_tip,
                COALESCE(SUM(s.total_service_commission),0) as total_service_commission,
                COALESCE(SUM(p.total_product_commission),0) as total_product_commission,
                (COALESCE(SUM(s.total_service_tip),0) + COALESCE(SUM(s.total_service_commission),0) + COALESCE(SUM(p.total_product_commission),0)) as total_earning
            ')->first();

        $totalVisit = DB::table('tbl_appointment_service as s')
            ->join('tbl_appointment as a', 's.appointment_id', '=', 'a.appointment_id')
            ->where('s.staff_id', $id)->where('a.is_invoiced', 1)
            ->distinct('a.appointment_id')->count('a.customer_id');

        return [
            'total_visits' => (int) $totalVisit,
            'total_appointments' => (int) $totalAppointments,
            'tips' => Money::str($e->total_service_tip ?? 0),
            'product_commission' => Money::str($e->total_product_commission ?? 0),
            'service_commission' => Money::str($e->total_service_commission ?? 0),
            'total_earning' => Money::str($e->total_earning ?? 0),
            'shop_revenue' => Money::str($e->total_revenue ?? 0),
            'shop_completed_appointments' => (int) ($e->total_appointments ?? 0),
            'shop_customers' => (int) ($e->total_visits ?? 0),
            'shop_tips' => Money::str($e->total_tips ?? 0),
        ];
    }

    /** web: DailyEarningGetTableData (the product commission repeats on each day row, Q40) */
    public function earnings(int $id, int $page, int $perPage): array
    {
        $serviceSub = DB::table('tbl_appointment_service as s')
            ->select('s.appointment_id', 's.staff_id', DB::raw('SUM(s.service_commission) as service_commission'), DB::raw('SUM(s.service_tip) as service_tip'))
            ->groupBy('s.appointment_id', 's.staff_id');
        $productSub = DB::table('tbl_appointment_product as p')
            ->select('p.staff_id', DB::raw('SUM(p.product_commision) as product_commission'))
            ->whereIn('p.appointment_id', fn ($q) => $q->select('appointment_id')->from('tbl_appointment')->where('is_invoiced', 1))
            ->groupBy('p.staff_id');

        $rows = DB::table('tbl_appointment as a')
            ->where('a.is_invoiced', 1)
            ->joinSub($serviceSub, 's', fn ($j) => $j->on('a.appointment_id', '=', 's.appointment_id'))
            ->leftJoinSub($productSub, 'p', fn ($j) => $j->on('s.staff_id', '=', 'p.staff_id'))
            ->select(
                'a.date', 's.staff_id',
                DB::raw('SUM(IFNULL(s.service_commission,0)) as service_commission'),
                DB::raw('SUM(IFNULL(s.service_tip,0)) as service_tip'),
                DB::raw('IFNULL(p.product_commission,0) as product_commission'),
                DB::raw('(SUM(IFNULL(s.service_commission,0)) + SUM(IFNULL(s.service_tip,0)) + IFNULL(p.product_commission,0)) as total_earn')
            )
            ->where('s.staff_id', $id)
            ->groupBy('a.date', 's.staff_id', 'p.product_commission')
            ->orderBy('a.date', 'desc')->get();

        $items = $rows->map(fn ($r) => [
            'date' => $r->date,
            'service_commission' => Money::str($r->service_commission),
            'tips' => Money::str($r->service_tip),
            'product_commission' => Money::str($r->product_commission),
            'total_earning' => Money::str($r->total_earn),
        ])->all();

        return [array_slice($items, ($page - 1) * $perPage, $perPage), count($items)];
    }

    /** web: AssignServicesGetTableData */
    public function services(int $id, int $page, int $perPage): array
    {
        $rows = DB::table('tbl_appointment_service as a')
            ->leftJoin('tbl_appointment as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->leftJoin('tbl_service as c', 'a.service_id', '=', 'c.id')
            ->select(
                'c.service_name', 'c.duration', 'c.price',
                DB::raw('SUM(a.service_commission) as total_service_commission'),
                DB::raw('SUM(a.service_tip) as total_service_tip'),
                DB::raw('COUNT(DISTINCT a.appointment_id) as appointmentCount')
            )
            ->where('a.staff_id', $id)->where('b.is_invoiced', 1)
            ->groupBy('a.service_id', 'c.service_name', 'c.duration', 'c.price')
            ->orderByDesc(DB::raw('SUM(b.total_amt)'))->orderBy('c.duration')->get();

        $items = $rows->map(fn ($r) => [
            'service_name' => $r->service_name,
            'duration' => (int) $r->duration,
            'price' => Money::str($r->price),
            'appointment_count' => (int) $r->appointmentCount,
            'commission' => Money::str($r->total_service_commission),
            'tips' => Money::str($r->total_service_tip),
            'total_earning' => Money::str($r->total_service_commission + $r->total_service_tip),
        ])->all();

        return [array_slice($items, ($page - 1) * $perPage, $perPage), count($items)];
    }

    /** web: AppointmentGetTableData (invoiced appointments of that staff member) */
    public function appointments(int $id, array $f, int $page, int $perPage): array
    {
        $base = DB::table('tbl_appointment as a')
            ->leftJoin('tbl_appointment_service as s', 'a.appointment_id', '=', 's.appointment_id')
            ->leftJoin('users as u', function ($join) {
                $join->on('s.staff_id', '=', 'u.id')->where('u.role', '=', 'Staff');
            })
            ->leftJoin('customers as c', 'a.customer_id', '=', 'c.customer_id')
            ->where('s.staff_id', $id)->where('is_invoiced', 1);

        if (!empty($f['start_date']) && !empty($f['end_date'])) {
            $base->whereBetween('a.date', [$f['start_date'], $f['end_date']]);
        }
        if (!empty($f['day_type'])) {
            [$from, $to] = ['Morning' => ['06:00:00', '11:59:59'], 'Afternoon' => ['12:00:00', '16:59:59'], 'Evening' => ['17:00:00', '22:00:00']][$f['day_type']];
            $base->whereBetween('a.slot_start', [$from, $to]);
        }
        if (!empty($f['q'])) {
            $like = '%' . $f['q'] . '%';
            $base->where(fn ($s) => $s->where('a.appointment_id', 'like', $like)->orWhere('a.name', 'like', $like)->orWhere('a.phone', 'like', $like)->orWhere('u.name', 'like', $like));
        }

        $total = (int) (clone $base)->distinct()->count('a.appointment_id');
        $rows = (clone $base)->select(
            'a.appointment_id', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status', 'c.customer_name', 'c.customer_phone',
            DB::raw('GROUP_CONCAT(DISTINCT u.name SEPARATOR ", ") as staff_names')
        )->groupBy('a.appointment_id', 'c.customer_name', 'c.customer_phone', 'a.date', 'a.slot_start', 'a.slot_end', 'a.status')
            ->orderByDesc('a.date')->orderByDesc('a.slot_start')->orderByDesc('a.appointment_id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($r) => [
            'id' => (int) $r->appointment_id,
            'date' => $r->date,
            'start' => substr($r->slot_start, 0, 5),
            'end' => substr($r->slot_end, 0, 5),
            'start_label' => AppointmentReader::timeLabel($r->slot_start),
            'end_label' => AppointmentReader::timeLabel($r->slot_end),
            'status' => (int) $r->status,
            'status_label' => Appointment::statusLabel((int) $r->status),
            'customer' => ['name' => $r->customer_name, 'phone' => $r->customer_phone],
            'staff_names' => $r->staff_names ?? '',
        ])->all(), $total];
    }
}
