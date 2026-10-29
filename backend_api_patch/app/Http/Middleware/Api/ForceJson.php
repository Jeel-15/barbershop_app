<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;

/**
 * The mobile API only speaks JSON. Without this, a request that forgets the
 * `Accept` header would be answered with an HTML redirect to the web login.
 */
class ForceJson
{
    public function handle(Request $request, Closure $next)
    {
        $request->headers->set('Accept', 'application/json');

        return $next($request);
    }
}
