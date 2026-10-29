<?php

namespace App\Services\Api;

use Illuminate\Support\Facades\Storage;

/**
 * Image URLs the way the web's calendar builds staff avatars: the file may live
 * on the public disk, under public/storage, or directly under public/.
 */
class Media
{
    /** a catalog picture, or null when there is none / the file is gone */
    public static function image(?string $path): ?string
    {
        if (empty($path)) {
            return null;
        }
        $path = ltrim(str_replace('\\', '/', $path), '/');

        if (Storage::disk('public')->exists($path) || file_exists(public_path('storage/' . $path))) {
            return asset('storage/' . $path);
        }

        return file_exists(public_path($path)) ? asset($path) : null;
    }

    public static function avatar(?string $path): string
    {
        $default = asset('assets/img/user.png');

        if (empty($path)) {
            return $default;
        }

        $path = ltrim(str_replace('\\', '/', $path), '/');

        if (Storage::disk('public')->exists($path) || file_exists(public_path('storage/' . $path))) {
            return asset('storage/' . $path);
        }
        if (file_exists(public_path($path))) {
            return asset($path);
        }

        return $default;
    }
}
