<?php

namespace App\Http\Controllers\Api\V1;

/**
 * Catch-all for `/api/v1/*` URLs that match no route, so an unknown endpoint
 * also answers with the API envelope (a plain router 404 would bypass the
 * route middleware).
 */
class FallbackController extends ApiController
{
    public function __invoke()
    {
        return $this->fail('Endpoint not found.', 404);
    }
}
