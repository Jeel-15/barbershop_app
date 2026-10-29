<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\StaffService;
use App\Models\User;
use App\Services\Api\StaffAdmin;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * STAFF-1 .. STAFF-12 — staff administration (web: StaffController, StaffServiceController).
 * The list / form / write routes need `Staff-Add|Edit|Delete` (route middleware, per action).
 * The profile numbers (STAFF-3..6) follow the web rule: the staff member themself, or `Staff-Add|Edit`.
 *
 * Pictures need a multipart request, so editing accepts POST as well as PUT.
 */
class StaffController extends ApiController
{
    public function __construct(private StaffAdmin $staff)
    {
    }

    public function index(Request $request)
    {
        $f = $request->validate([
            'q' => ['nullable', 'string', 'max:100'],
            'barber' => ['nullable', 'in:0,1'],
            'active' => ['nullable', 'in:0,1'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->staff->paginate($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function formOptions()
    {
        return $this->ok($this->staff->formOptions());
    }

    public function show(Request $request, int $id)
    {
        $user = $this->staff->find($id);
        if (!$user || $user->role !== 'Staff') {      // web: the profile page is for panel Staff only
            return $this->fail('Staff member not found.', 404);
        }
        if ($denied = $this->profileAccess($request, $id)) {
            return $denied;
        }
        $f = $request->validate([
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
        ]);

        return $this->ok(['staff' => $this->staff->one($id), 'summary' => $this->staff->profile($id, $f)]);
    }

    public function earnings(Request $request, int $id)
    {
        return $this->profileList($request, $id, fn ($p, $n) => $this->staff->earnings($id, $p, $n));
    }

    public function services(Request $request, int $id)
    {
        return $this->profileList($request, $id, fn ($p, $n) => $this->staff->services($id, $p, $n));
    }

    public function appointments(Request $request, int $id)
    {
        $f = $request->validate([
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
            'day_type' => ['nullable', 'in:Morning,Afternoon,Evening'],
            'q' => ['nullable', 'string', 'max:100'],
        ]);

        return $this->profileList($request, $id, fn ($p, $n) => $this->staff->appointments($id, $f, $p, $n));
    }

    private function profileList(Request $request, int $id, callable $fetch)
    {
        $user = $this->staff->find($id);
        if (!$user || $user->role !== 'Staff') {
            return $this->fail('Staff member not found.', 404);
        }
        if ($denied = $this->profileAccess($request, $id)) {
            return $denied;
        }
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $fetch($page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    /** web: staff_profile — `id == me` or Staff-Edit / Staff-Add */
    private function profileAccess(Request $request, int $id)
    {
        $me = $request->user();
        if ($id !== (int) $me->id && !$me->can('Staff-Edit') && !$me->can('Staff-Add')) {
            return $this->fail('You do not have permission to do this (Staff-Edit or Staff-Add).', 403);
        }

        return null;
    }

    // ------------------------------------------------------------------ write

    public function store(Request $request)
    {
        $in = $this->input($request, null);
        $id = $this->staff->create($request->user(), $in, $request->file('profile_image'));

        return $this->ok(['staff' => $this->staff->one($id)], 'Staff added successfully', 201);
    }

    public function update(Request $request, int $id)
    {
        $user = $this->staff->find($id);
        if (!$user) {
            return $this->fail('Staff member not found.', 404);
        }
        $this->staff->update($user, $this->input($request, $id), $request->file('profile_image'));

        return $this->ok(['staff' => $this->staff->one($id)], 'Staff updated successfully');
    }

    public function destroy(Request $request, int $id)
    {
        $user = $this->staff->find($id);
        if (!$user) {
            return $this->fail('Staff member not found.', 404);
        }
        if ($id === (int) $request->user()->id) {
            return $this->fail('You cannot delete your own account.', 409);
        }
        if (preg_match('/^first\s+available/i', trim((string) $user->name))) {
            return $this->fail('"First available" is a system entry that the booking calendar needs. It cannot be deleted.', 409);
        }
        $this->staff->delete($user);

        return $this->ok([], 'Staff deleted successfully');
    }

    public function password(Request $request, int $id)
    {
        $in = $request->validate([
            'new_password' => ['required', 'string', 'min:6'],
            'confirm_password' => ['required', 'same:new_password'],
        ], [
            'new_password.required' => 'Please enter a new password',
            'new_password.min' => 'Password must be at least 6 characters long',
            'confirm_password.required' => 'Please confirm your password',
            'confirm_password.same' => 'Passwords do not match',
        ]);
        $user = $this->staff->find($id);
        if (!$user) {
            return $this->fail('Staff member not found.', 404);
        }
        $this->staff->changePassword($user, $in['new_password']);

        return $this->ok([], 'Password changed successfully');
    }

    // ------------------------------------------------------------------ assigned services

    public function assigned(int $id)
    {
        $user = $this->staff->find($id);
        if (!$user || $user->role !== 'Staff') {
            return $this->fail('Staff not found', 404);
        }

        return $this->ok(['staff_id' => (int) $user->id, 'is_barber' => (int) $user->is_barber === 1, 'service_ids' => StaffService::idsForStaff($id)]);
    }

    public function assign(Request $request, int $id)
    {
        $user = $this->staff->find($id);
        if (!$user || $user->role !== 'Staff') {
            return $this->fail('Staff not found', 404);
        }
        $in = $request->validate([
            'service_ids' => ['present', 'array', 'max:200'],
            'service_ids.*' => ['integer', Rule::exists('tbl_service', 'id')->whereNull('deleted_at')],
        ]);
        $this->staff->syncServices($user, $in['service_ids']);

        return $this->ok(['service_ids' => StaffService::idsForStaff($id)], 'Services assigned successfully');
    }

    // ------------------------------------------------------------------ input

    /** web rules; the e-mail must be unique case-insensitively (also against deleted accounts, like the web) */
    private function input(Request $request, ?int $id): array
    {
        $role = (int) $request->input('role_id');
        $roleName = \App\Models\Role::where('id', $role)->value('name');
        $barber = $roleName !== 'Accountant' && $request->boolean('is_barber');

        $in = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', Rule::unique('users', 'email')->ignore($id)],
            'phone' => ['nullable', 'string', 'max:20'],
            'password' => [$id === null ? 'required' : 'nullable', 'string', 'min:6'],
            'is_barber' => ['nullable', 'boolean'],
            'service_ids' => [$barber ? 'required' : 'nullable', 'array', $barber ? 'min:1' : 'max:200'],
            'service_ids.*' => ['integer', Rule::exists('tbl_service', 'id')->whereNull('deleted_at')],
            'commission' => ['nullable', 'numeric', 'min:0'],
            'active_status' => ['required', 'boolean'],
            'role_id' => ['required', 'integer', Rule::in(StaffAdmin::assignableRoleIds())],
            'profile_image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)],
        ], [
            'email.unique' => 'This email is already registered. Please use a different email.',
            'email.required' => 'Please enter Staff Email',
            'email.email' => 'Enter a valid email',
        ]);

        if (User::whereRaw('LOWER(email) = ?', [strtolower($in['email'])])->when($id, fn ($q) => $q->where('id', '!=', $id))->exists()) {
            throw \Illuminate\Validation\ValidationException::withMessages(['email' => ['This email is already registered. Please use a different email.']]);
        }

        $in['is_barber'] = $barber;
        $in['active_status'] = $request->boolean('active_status');
        $in['service_ids'] = array_values(array_unique(array_map('intval', $in['service_ids'] ?? [])));

        return $in;
    }
}
