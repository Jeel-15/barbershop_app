<?php

namespace App\Http\Middleware\Api;

use Closure;
use Illuminate\Contracts\Cache\LockTimeoutException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\RateLimiter;
use Throwable;

/**
 * Rate limit that answers with the API envelope.
 *
 * Usage on a route:  ApiRateLimit::class . ':login,10,60,email'
 *   name, max attempts, window seconds, optional "email" to also key on the
 *   submitted email (so one IP cannot hammer many accounts and many IPs cannot
 *   hammer one account unnoticed).
 *
 * Own implementation instead of `throttle:` because that alias is re-ordered
 * ahead of the envelope middleware and would answer in HTML. The "check, then
 * count" step runs under a cache lock: with the file cache, parallel requests
 * otherwise all pass the check before any of them is counted, which would let a
 * burst of simultaneous login attempts slip through.
 */
class ApiRateLimit
{
    public function handle(Request $request, Closure $next, string $name = 'api', int $max = 60, int $seconds = 60, ?string $by = null)
    {
        $who = $request->user('sanctum')?->id ?: $request->ip();
        $key = 'api-rl:' . $name . '|' . $who;
        if ($by === 'email') {
            $key .= '|' . strtolower(trim((string) $request->input('email')));
        }

        try {
            $retry = Cache::lock('lock:' . $key, 5)->block(3, fn () => $this->attempt($key, $max, $seconds));
        } catch (LockTimeoutException $e) {
            $retry = 1; // heavy contention: refuse rather than let a burst through
        } catch (Throwable $e) {
            // The cache backend could not hand out a lock (e.g. Windows file-lock contention
            // when many requests arrive at once). Never turn that into a 500: fall back to the
            // plain, unlocked check, which still limits normal (sequential) traffic.
            $retry = $this->attempt($key, $max, $seconds);
        }

        if ($retry > 0) {
            return response()->json([
                'status' => 0,
                'message' => 'Too many attempts. Please try again in ' . $retry . ' seconds.',
                'retry_after' => $retry,
                'request_id' => $request->attributes->get('request_id'),
            ], 429, ['Retry-After' => $retry]);
        }

        return $next($request);
    }

    /**
     * @return int 0 when the request may proceed, otherwise seconds until the limit resets
     */
    private function attempt(string $key, int $max, int $seconds): int
    {
        if (RateLimiter::tooManyAttempts($key, $max)) {
            return RateLimiter::availableIn($key);
        }

        RateLimiter::hit($key, $seconds);

        return 0;
    }
}
