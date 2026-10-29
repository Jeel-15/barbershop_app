<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

/**
 * Base class for the mobile app API (v1).
 *
 * Every response uses one envelope:
 *   success: { "status": 1, "message": "...", "data": {...}, "meta": {...}? }
 *   failure: { "status": 0, "message": "...", "errors": {...}?, "request_id": "..." }
 * (`status` mirrors the 1/0 the web admin already returns from its JSON endpoints.)
 */
abstract class ApiController extends Controller
{
    protected function ok(array $data = [], string $message = 'OK', int $http = 200, array $meta = [])
    {
        $body = [
            'status' => 1,
            'message' => $message,
            // An empty array must serialize as {} so the app always receives an object.
            'data' => $data === [] ? (object) [] : $data,
        ];

        if ($meta !== []) {
            $body['meta'] = $meta;
        }

        return response()->json($body, $http);
    }

    protected function fail(string $message, int $http = 422, array $extra = [])
    {
        return response()->json(array_merge([
            'status' => 0,
            'message' => $message,
            'request_id' => request()->attributes->get('request_id'),
        ], $extra), $http);
    }

    /**
     * Standard paginated list: items + meta {page, per_page, total, has_more}.
     */
    protected function listing(array $items, int $total, int $page, int $perPage, array $extraMeta = [], string $message = 'OK')
    {
        return $this->ok(['items' => array_values($items)], $message, 200, array_merge([
            'page' => $page,
            'per_page' => $perPage,
            'total' => $total,
            'has_more' => ($page * $perPage) < $total,
        ], $extraMeta));
    }

    /**
     * Reads ?page= and ?per_page= with the limits from config/api_v1.php.
     *
     * @return array{0:int,1:int} [page, per_page]
     */
    protected function pageParams(Request $request): array
    {
        $max = (int) config('api_v1.per_page_max', 50);
        $page = max(1, (int) $request->query('page', 1));
        $per = (int) $request->query('per_page', config('api_v1.per_page_default', 20));
        $per = max(1, min($max, $per ?: (int) config('api_v1.per_page_default', 20)));

        return [$page, $per];
    }
}
