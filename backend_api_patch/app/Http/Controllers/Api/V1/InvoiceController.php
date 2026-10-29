<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\PosService;
use App\Services\Api\SlotGuard;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

/**
 * POS-3 .. POS-7 — invoices (web: InvoiceController). Visibility rule of the
 * web: staff without `Pos_invoice-Show_All` only see invoices they created.
 */
class InvoiceController extends ApiController
{
    public function index(Request $request, PosService $pos)
    {
        $f = $request->validate([
            'q' => ['nullable', 'string', 'max:100'],
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $pos->paginate($request->user(), $f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function show(Request $request, PosService $pos, int $id)
    {
        $invoice = $pos->detail($request->user(), $id);

        return $invoice ? $this->ok(['invoice' => $invoice]) : $this->fail('Invoice not found.', 404);
    }

    public function store(Request $request, PosService $pos)
    {
        $in = PosController::cart($request);
        $user = $request->user();

        // A retry of the same request (flaky signal) must not create a second invoice.
        $key = $request->header('Idempotency-Key');
        if ($key === null || $key === '') {
            return $this->created($pos, $user, $pos->create($user, $in)->appointment_id);
        }
        if (strlen($key) > 100) {
            return $this->fail('Idempotency-Key is too long.', 422);
        }

        $cacheKey = 'idem:invoice:' . $user->id . ':' . sha1($key);

        return SlotGuard::run($cacheKey, function () use ($pos, $user, $in, $cacheKey) {
            if ($existing = Cache::get($cacheKey)) {
                $invoice = $pos->detail($user, (int) $existing);
                if ($invoice) {
                    return $this->ok(['invoice' => $invoice], 'Invoice already created.');
                }
            }

            $id = $pos->create($user, $in)->appointment_id;
            Cache::put($cacheKey, $id, now()->addDay());

            return $this->created($pos, $user, $id);
        });
    }

    public function update(Request $request, PosService $pos, int $id)
    {
        $in = PosController::cart($request);
        $appointment = $pos->update($request->user(), $id, $in);

        if (!$appointment) {
            return $this->fail('Invoice not found.', 404);
        }
        $pos->mailAfterSave($id);

        return $this->ok(['invoice' => $pos->detail($request->user(), $id)], 'Successfully Updated Invoice');
    }

    /** APPT-11: only when the feature flag is on (the web cannot do this yet) */
    public function complete(Request $request, PosService $pos, int $id)
    {
        if (!config('api_v1.feature_flags.complete_from_appointment')) {
            return $this->fail('Completing an appointment into an invoice is not available yet.', 404);
        }

        [$http, $message, $invoiceId] = $pos->complete($request->user(), $id, PosController::cart($request));
        if ($http !== 200) {
            return $this->fail($message, $http);
        }
        $pos->mailAfterSave($invoiceId);

        return $this->ok(['invoice' => $pos->detail($request->user(), $invoiceId)], $message);
    }

    public function email(Request $request, PosService $pos, int $id)
    {
        $in = $request->validate(['email' => ['nullable', 'email', 'max:255']]);
        [$http, $message] = $pos->sendEmail($request->user(), $id, $in['email'] ?? null);

        return $http === 200 ? $this->ok([], $message) : $this->fail($message, $http);
    }

    private function created(PosService $pos, $user, int $id)
    {
        $pos->mailAfterSave($id);

        return $this->ok(['invoice' => $pos->detail($user, $id)], 'Successfully Created Invoice', 201);
    }
}
