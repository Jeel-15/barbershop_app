<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Throwable;

/**
 * Gives every API request an id (header `X-Request-Id`) and writes one line to
 * storage/logs/api-YYYY-MM-DD.log. It never logs bodies, query strings, tokens,
 * passwords or customer phone/email.
 */
class ApiRequestLog
{
    public function handle(Request $request, Closure $next)
    {
        $id = substr(str_replace('-', '', (string) Str::uuid()), 0, 16);
        $request->attributes->set('request_id', $id);
        $started = microtime(true);

        $response = $next($request);

        $response->headers->set('X-Request-Id', $id);

        try {
            Log::build([
                'driver' => 'single',
                'path' => storage_path('logs/api-' . date('Y-m-d') . '.log'),
                'level' => 'info',
            ])->info('api', [
                'id' => $id,
                'user' => optional($request->user('sanctum'))->id,
                'method' => $request->method(),
                'path' => '/' . ltrim($request->path(), '/'),
                'status' => $response->getStatusCode(),
                'ms' => (int) round((microtime(true) - $started) * 1000),
                'ip' => $request->ip(),
            ]);
        } catch (Throwable $e) {
            // Logging must never break a request.
        }

        return $response;
    }
}
