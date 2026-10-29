<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;

/**
 * Mirror of the web's `not.staff` middleware: users stored with role Staff (this
 * includes Manager accounts, docs/API_PLAN.md Q24) cannot open the admin reports.
 */
class RequireNotStaff
{
    public function handle(Request $request, Closure $next)
    {
        $user = $request->user();

        if (!$user || $user->isStaffUser()) {
            return response()->json([
                'status' => 0,
                'message' => 'These reports are for administrators only.',
                'request_id' => $request->attributes->get('request_id'),
            ], 403);
        }

        return $next($request);
    }
}
