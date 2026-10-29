<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\StaffReport;
use Illuminate\Http\Request;

/**
 * ME-3 .. ME-6 — the signed-in staff member's own earnings report
 * (web: StaffreportController). Route middleware: staff only + `Report-View`.
 */
class StaffReportController extends ApiController
{
    public function summary(Request $request, StaffReport $report)
    {
        return $this->ok(['summary' => $report->summary($request->user(), $this->filters($request))]);
    }

    public function earnings(Request $request, StaffReport $report)
    {
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $report->earnings($request->user(), $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function services(Request $request, StaffReport $report)
    {
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $report->services($request->user(), $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function appointments(Request $request, StaffReport $report)
    {
        $f = $this->filters($request) + $request->validate(['q' => ['nullable', 'string', 'max:100']]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $report->appointments($request->user(), $f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    private function filters(Request $request): array
    {
        return $request->validate([
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
            'status' => ['nullable', 'integer', 'between:0,4'],
        ]);
    }
}
