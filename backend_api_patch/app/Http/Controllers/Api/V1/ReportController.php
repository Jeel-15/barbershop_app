<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\ReportAdmin;
use Illuminate\Http\Request;

/**
 * RPT-1 .. RPT-6 — admin reports (web: ReportController). Route middleware:
 * `Report-View` and not a Staff-role user (web `not.staff`).
 */
class ReportController extends ApiController
{
    public function __construct(private ReportAdmin $reports)
    {
    }

    public function appointments(Request $request)
    {
        $f = $this->filters($request, true);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total, $summary] = $this->reports->appointments($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage, ['summary' => $summary]);
    }

    public function payments(Request $request)
    {
        [$rows, $summary] = $this->reports->payments($this->filters($request));

        return $this->ok(['items' => $rows], 'OK', 200, ['summary' => $summary]);
    }

    public function staffEarnings(Request $request)
    {
        [$rows, $summary] = $this->reports->staffEarnings($this->filters($request));

        return $this->ok(['items' => $rows], 'OK', 200, ['summary' => $summary]);
    }

    public function customerInvoices(Request $request)
    {
        $f = $this->filters($request, true);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->reports->customerInvoices($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function productSales(Request $request)
    {
        $f = $this->filters($request, true);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->reports->productSales($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function topProducts(Request $request)
    {
        [$rows, $summary] = $this->reports->topProducts($this->filters($request));

        return $this->ok(['items' => $rows], 'OK', 200, ['summary' => $summary]);
    }

    private function filters(Request $request, bool $search = false): array
    {
        $rules = [
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
            'staff_id' => ['nullable', 'integer', 'min:0'],
        ];
        if ($search) {
            $rules['q'] = ['nullable', 'string', 'max:100'];
        }

        return $request->validate($rules);
    }
}
