<?php

namespace App\Services\Api;

use App\Http\Controllers\Api\V1\ModuleAccess;
use App\Models\User;

/**
 * The one place that decides how a user looks to the app.
 */
class UserPresenter
{
    public static function make(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'phone' => $user->phone,
            'role' => $user->role,
            'roles' => $user->getRoleNames()->values(),
            'is_staff' => $user->isStaffUser(),
            'is_barber' => $user->isBarber(),
            'profile_image_url' => $user->profile_img
                ? asset('storage/' . $user->profile_img)
                : asset('assets/img/user.png'),
            'permissions' => $user->getAllPermissions()->pluck('name')->values(),
            'modules' => ModuleAccess::for($user),
            'home' => ModuleAccess::home($user),
            'permissions_version' => self::version($user),
        ];
    }

    /**
     * A short fingerprint of everything that decides what this user may see or do:
     * panel role, spatie roles, every permission, the module flags, staff/barber
     * scope. It changes whenever an admin changes any of those, and only then.
     * The app compares it with the one it holds and re-reads /bootstrap when it differs.
     *
     * $fresh drops the cached role/permission relations first, so a change made earlier
     * in the same request (e.g. a user editing their own role) is already counted.
     */
    public static function version(User $user, bool $fresh = false): string
    {
        if ($fresh) {
            $user->unsetRelation('roles')->unsetRelation('permissions');
        }

        $modules = ModuleAccess::for($user);
        ksort($modules);

        $payload = [
            'role' => (string) $user->role,
            'roles' => $user->getRoleNames()->sort()->values()->all(),
            'permissions' => $user->getAllPermissions()->pluck('name')->sort()->values()->all(),
            'modules' => $modules,
            'home' => ModuleAccess::home($user),
            'staff' => (bool) $user->isStaffUser(),
            'barber' => (bool) $user->isBarber(),
        ];

        return substr(sha1(json_encode($payload)), 0, 12);
    }
}
