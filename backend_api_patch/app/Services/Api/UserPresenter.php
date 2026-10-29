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
        ];
    }
}
