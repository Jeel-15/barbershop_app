<?php

namespace App\Services\Api;

use Closure;
use Illuminate\Contracts\Cache\LockTimeoutException;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Throwable;

/**
 * Serialises "check that the time is free, then write" for one staff member and
 * one day, so two phones cannot book the same slot at the same moment.
 *
 * Uses a cache lock. If the cache backend cannot hand out a lock at all (e.g.
 * Windows file-lock contention) the work still runs unlocked: the overlap check
 * inside the database transaction remains, which is as safe as the web is.
 */
class SlotGuard
{
    public static function run(string $key, Closure $work)
    {
        $lock = Cache::lock('slot:' . $key, 15);
        $held = false;

        try {
            $held = $lock->block(5);
        } catch (LockTimeoutException $e) {
            throw new HttpException(409, 'Another booking is being saved for this time. Please try again.');
        } catch (Throwable $e) {
            $held = false;   // cannot lock: continue without
        }

        try {
            return $work();
        } finally {
            if ($held) {
                $lock->release();
            }
        }
    }
}
