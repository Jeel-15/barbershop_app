<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\RoleAdmin;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * ROLE-1 / ROLE-2 — roles and their permissions (web: RolesController).
 * Route middleware: `Role-Add|Edit|Delete`, writes need their own.
 */
class RoleController extends ApiController
{
    public function __construct(private RoleAdmin $roles)
    {
    }

    public function index()
    {
        return $this->ok(['roles' => $this->roles->roles(), 'permission_groups' => $this->roles->catalog()]);
    }

    public function show(int $id)
    {
        $r = $this->roles->find($id);

        return $r ? $this->ok(['role' => $r]) : $this->fail('Role not found.', 404);
    }

    public function store(Request $request)
    {
        $in = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('roles', 'name')],
            'permission_ids' => ['nullable', 'array'],
            'permission_ids.*' => ['integer', 'exists:permissions,id'],
        ]);
        $id = $this->roles->create($in['name'], $in['permission_ids'] ?? []);

        return $this->ok(['role' => $this->roles->find($id)], 'Role created successfully.', 201);
    }

    public function update(Request $request, int $id)
    {
        if (!$this->roles->find($id)) {
            return $this->fail('Role not found.', 404);
        }
        $in = $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('roles', 'name')->ignore($id)],
            'permission_ids' => ['nullable', 'array'],
            'permission_ids.*' => ['integer', 'exists:permissions,id'],
        ]);
        if ($refused = $this->roles->update($id, $in['name'], $in['permission_ids'] ?? [])) {
            return $this->fail($refused, 409);
        }

        return $this->ok(['role' => $this->roles->find($id)], 'Role updated successfully.');
    }

    public function destroy(int $id)
    {
        [$http, $message] = $this->roles->delete($id);

        return $http === 200 ? $this->ok([], $message) : $this->fail($message, $http);
    }
}
