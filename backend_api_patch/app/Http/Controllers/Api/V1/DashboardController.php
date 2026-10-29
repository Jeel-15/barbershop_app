<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\AppointmentReader;
use App\Services\Api\DashboardLists;
use App\Services\Api\DashboardReader;
use Illuminate\Http\Request;

/**
 * DASH-1 .. DASH-6 — mirrors DashboardController (cards, today, upcoming, top services,
 * staff performance, top selling products).
 * Permissions are applied per route (see routes/api.php).
 */
class DashboardController extends ApiController
{
    public function summary(Request $request, DashboardReader $dashboard)
    {
        return $this->ok($dashboard->summary($request->user()));
    }

    public function today(Request $request, AppointmentReader $appointments)
    {
        return $this->dashboardList($request, $appointments, 'today');
    }

    public function upcoming(Request $request, AppointmentReader $appointments)
    {
        return $this->dashboardList($request, $appointments, 'upcoming');
    }

    private function dashboardList(Request $request, AppointmentReader $appointments, string $mode)
    {
        $request->validate(['q' => ['nullable', 'string', 'max:100']]);
        [$page, $perPage] = $this->pageParams($request);

        [$rows, $total] = $appointments->paginate(
            $request->user(),
            $mode,
            ['q' => $request->query('q')],
            $page,
            $perPage
        );

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function topServices(Request $request, DashboardLists $lists)
    {
        return $this->topList($request, fn ($q, $p, $n) => $lists->topServices($q, $p, $n));
    }

    public function staffPerformance(Request $request, DashboardLists $lists)
    {
        return $this->topList($request, fn ($q, $p, $n) => $lists->staffPerformance($q, $p, $n));
    }

    public function topProducts(Request $request, DashboardLists $lists)
    {
        return $this->topList($request, fn ($q, $p, $n) => $lists->topProducts($q, $p, $n));
    }

    private function topList(Request $request, callable $fetch)
    {
        $request->validate(['q' => ['nullable', 'string', 'max:100']]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $fetch($request->query('q') ?: null, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }
}
