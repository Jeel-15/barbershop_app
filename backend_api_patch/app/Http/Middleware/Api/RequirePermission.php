<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;

/**
 * Permission gate with the same semantics as the web's `canany:` middleware:
 * the user needs at least ONE of the listed spatie permissions.
 *
 * Usage: RequirePermission::class . ':Appointment-View'
 *        RequirePermission::class . ':Staff-Add,Staff-Edit,Staff-Delete'
 */
class RequirePermission
{
    public function handle(Request $request, Closure $next, ...$permissions)
    {
        $user = $request->user();

        if (!$user || !$user->canAny($permissions)) {
            return response()->json([
                'status' => 0,
                'message' => 'You do not have permission to do this (' . implode(' or ', $permissions) . ').',
                'request_id' => $request->attributes->get('request_id'),
            ], 403);
        }

        return $next($request);
    }
}
