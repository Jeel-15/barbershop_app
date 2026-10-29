<?php

namespace App\Services\Api;

use Illuminate\Support\Facades\DB;

/**
 * DASH-4 / DASH-5 / DASH-6 — the dashboard's "Top Services", staff performance
 * and "Top Selling Product" tables, with the web's queries unchanged
 * (SUM(DISTINCT ...) included, docs/API_PLAN.md Q36). The lists are short, so
 * they are paged in PHP.
 */
class DashboardLists
{
    /** @return array{0: array, 1: int} */
    public function topServices(?string $q, int $page, int $perPage): array
    {
        $rows = DB::table('tbl_appointment_service as b')
            ->join('tbl_service as c', 'b.service_id', '=', 'c.id')
            ->join('tbl_appointment as d', 'b.appointment_id', '=', 'd.appointment_id')
            ->select(
                'c.service_name',
                DB::raw('SUM(DISTINCT d.total_amt) as totalRevenue'),
                DB::raw('COUNT(DISTINCT b.appointment_id) as appointmentCount')
            )
            ->when($q, fn ($w) => $w->where('c.service_name', 'like', "%{$q}%"))
            ->groupBy('c.service_name')
            ->orderByDesc('totalRevenue')->orderBy('c.service_name')
            ->get();

        return $this->slice($rows->map(fn ($r) => [
            'service_name' => $r->service_name,
            'total_revenue' => Money::str($r->totalRevenue),
            'appointment_count' => (int) $r->appointmentCount,
        ])->all(), $page, $perPage);
    }

    /** @return array{0: array, 1: int} */
    public function staffPerformance(?string $q, int $page, int $perPage): array
    {
        $rows = DB::table('tbl_appointment as a')
            ->join('tbl_appointment_service as b', 'a.appointment_id', '=', 'b.appointment_id')
            ->join('users as s', 'b.staff_id', '=', 's.id')
            ->select(
                's.id as staff_id',
                's.name as staff_name',
                DB::raw('SUM(DISTINCT a.total_amt) as totalRevenue'),
                DB::raw('COALESCE(SUM(DISTINCT b.service_commission),0) as totalCommission'),
                DB::raw('COUNT(a.appointment_id) as appointmentCount')
            )
            ->when($q, fn ($w) => $w->where('s.name', 'like', "%{$q}%"))
            ->groupBy('s.id', 's.name')
            ->orderByDesc('totalRevenue')->orderBy('s.id')
            ->get();

        return $this->slice($rows->map(fn ($r) => [
            'staff_id' => (int) $r->staff_id,
            'staff_name' => $r->staff_name,
            'total_revenue' => Money::str($r->totalRevenue),
            'total_commission' => Money::str($r->totalCommission),
            'appointment_count' => (int) $r->appointmentCount,
        ])->all(), $page, $perPage);
    }

    /** @return array{0: array, 1: int} */
    public function topProducts(?string $q, int $page, int $perPage): array
    {
        $rows = DB::table('tbl_product as p')
            ->leftJoin('tbl_appointment_product as ap', 'p.id', '=', 'ap.product_id')
            ->select('p.id', 'p.product_name', DB::raw('COALESCE(SUM(ap.qty), 0) as total_sold'))
            ->when($q, fn ($w) => $w->where('p.product_name', 'like', "%{$q}%"))
            ->groupBy('p.id', 'p.product_name')
            ->orderByDesc('total_sold')->orderBy('p.id')
            ->get();

        return $this->slice($rows->map(fn ($r) => [
            'product_id' => (int) $r->id,
            'product_name' => $r->product_name,
            'total_sold' => (int) $r->total_sold,
        ])->all(), $page, $perPage);
    }

    private function slice(array $items, int $page, int $perPage): array
    {
        return [array_slice($items, ($page - 1) * $perPage, $perPage), count($items)];
    }
}
