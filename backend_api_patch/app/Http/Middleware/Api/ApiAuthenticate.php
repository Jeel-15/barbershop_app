<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

/**
 * Sanctum bearer authentication for the mobile API.
 *
 * Same rules as the web login: a deactivated account (`active_status != 1`) is
 * refused, and its token is revoked on the spot. Soft-deleted users cannot
 * authenticate at all (their token no longer resolves to a user).
 *
 * This replaces the `auth:sanctum` alias on purpose: Laravel re-orders aliased
 * middleware by a priority list, which could run it before the JSON/envelope
 * middleware and turn a 401 into an HTML redirect.
 */
class ApiAuthenticate
{
    public function handle(Request $request, Closure $next)
    {
        $user = Auth::guard('sanctum')->user();

        if (!$user) {
            return response()->json([
                'status' => 0,
                'message' => 'Unauthenticated.',
                'request_id' => $request->attributes->get('request_id'),
            ], 401);
        }

        if ((int) $user->active_status !== 1) {
            $user->currentAccessToken()?->delete();

            return response()->json([
                'status' => 0,
                'message' => 'This account is deactivated. Please reach out to the support team.',
                'request_id' => $request->attributes->get('request_id'),
            ], 403);
        }

        Auth::shouldUse('sanctum');
        $request->setUserResolver(fn () => $user);

        return $next($request);
    }
}
