<?php

namespace App\Services\Api;

use Illuminate\Support\Facades\DB;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;

/**
 * ROLE-1 / ROLE-2 — roles and the permissions they grant (web: RolesController).
 * Permissions themselves are not editable from the app (D6).
 */
class RoleAdmin
{
    /** Super-admin, Staff, POS Manager: the web hides delete for these and code refers to them by id */
    public const LOCKED_IDS = [1, 2, 4];
    /** code refers to these by name (panel role, form options) */
    public const LOCKED_NAMES = ['Super-admin', 'Staff', 'Accountant', 'POS Manager'];

    public function roles(): array
    {
        $users = DB::table('model_has_roles')->select('role_id', DB::raw('COUNT(*) as n'))->groupBy('role_id')->pluck('n', 'role_id');

        return Role::with('permissions:id')->orderBy('id')->get()->map(fn ($r) => [
            'id' => (int) $r->id,
            'name' => $r->name,
            'permission_ids' => $r->permissions->pluck('id')->map(fn ($i) => (int) $i)->sort()->values()->all(),
            'users_count' => (int) ($users[$r->id] ?? 0),
            'locked' => in_array((int) $r->id, self::LOCKED_IDS, true),
            'created_at' => optional($r->created_at)->toDateString(),
        ])->all();
    }

    public function find(int $id): ?array
    {
        return collect($this->roles())->firstWhere('id', $id);
    }

    /** permissions grouped by their prefix (Staff-Add -> "Staff"), like the web role form */
    public function catalog(): array
    {
        return Permission::orderBy('id')->get()
            ->groupBy(fn ($p) => explode('-', $p->name)[0])
            ->map(fn ($items, $group) => ['group' => $group, 'permissions' => $items->map(fn ($p) => ['id' => (int) $p->id, 'name' => $p->name])->values()->all()])
            ->values()->all();
    }

    public function create(string $name, array $permissionIds): int
    {
        return DB::transaction(function () use ($name, $permissionIds) {
            $role = Role::create(['name' => $name, 'guard_name' => 'web']);
            $role->syncPermissions(Permission::whereIn('id', $permissionIds)->pluck('name'));

            return (int) $role->id;
        });
    }

    /** @return string|null refusal message */
    public function update(int $id, string $name, array $permissionIds): ?string
    {
        $role = Role::find($id);
        if (!$role) {
            return 'Role not found.';
        }
        if ($name !== $role->name && in_array($role->name, self::LOCKED_NAMES, true)) {
            return 'The "' . $role->name . '" role is used by the system and cannot be renamed.';
        }
        DB::transaction(function () use ($role, $name, $permissionIds) {
            $role->name = $name;
            $role->save();
            $role->syncPermissions(Permission::whereIn('id', $permissionIds)->pluck('name'));
        });

        return null;
    }

    /** @return array{0: int, 1: string} [http, message] */
    public function delete(int $id): array
    {
        $role = Role::find($id);
        if (!$role) {
            return [404, 'Role not found.'];
        }
        if (in_array((int) $id, self::LOCKED_IDS, true) || in_array($role->name, self::LOCKED_NAMES, true)) {
            return [409, 'The "' . $role->name . '" role is used by the system and cannot be deleted.'];
        }
        if (DB::table('model_has_roles')->where('role_id', $id)->exists()) {
            return [409, 'This role is still assigned to staff. Give them another role first.'];
        }
        $role->delete();

        return [200, 'Role deleted successfully.'];
    }
}
