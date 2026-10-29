<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;

/**
 * Same as the web's `staff.only` middleware: only users whose `users.role` is
 * "Staff" (User::isStaffUser) may enter, e.g. the Working Hours page.
 */
class RequireStaff
{
    public function handle(Request $request, Closure $next)
    {
        $user = $request->user();

        if (!$user || !$user->isStaffUser()) {
            return response()->json([
                'status' => 0,
                'message' => 'This area is only for staff members.',
                'request_id' => $request->attributes->get('request_id'),
            ], 403);
        }

        return $next($request);
    }
}
