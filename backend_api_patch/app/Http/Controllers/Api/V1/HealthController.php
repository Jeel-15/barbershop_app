<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Throwable;

/**
 * Public liveness + schema check. Answers "is the API able to work against this
 * database?" without exposing anything sensitive. The list of what is missing
 * is only included when the app runs in the `local` environment.
 */
class HealthController extends ApiController
{
    public function index()
    {
        $db = true;
        try {
            DB::select('select 1');
        } catch (Throwable $e) {
            $db = false;
        }

        $missing = $db ? $this->missingSchema() : [];
        $ok = $db && $missing === [];

        $data = [
            'db' => $db,
            'schema_ok' => $ok,
            'version' => config('api_v1.version'),
            'build' => config('api_v1.build'),
            'time' => now()->toIso8601String(),
        ];

        if (app()->environment('local') && $missing !== []) {
            $data['missing'] = $missing;
        }

        return $this->ok($data, $ok ? 'OK' : 'Schema check failed', $ok ? 200 : 503);
    }

    /**
     * Cached for a minute so a monitoring tool polling /health costs almost nothing.
     */
    private function missingSchema(): array
    {
        return Cache::remember('api_v1_schema_missing', 60, function () {
            $missing = [];
            $schema = config('api_v1.required_schema');

            foreach ($schema['tables'] as $table) {
                if (!Schema::hasTable($table)) {
                    $missing[] = $table;
                }
            }
            foreach ($schema['columns'] as $table => $columns) {
                if (!Schema::hasTable($table)) {
                    continue; // already reported
                }
                foreach ($columns as $column) {
                    if (!Schema::hasColumn($table, $column)) {
                        $missing[] = $table . '.' . $column;
                    }
                }
            }

            return $missing;
        });
    }
}
