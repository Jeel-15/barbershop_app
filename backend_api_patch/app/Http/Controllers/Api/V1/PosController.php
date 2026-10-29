<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\PosService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * POS-1 / POS-2 / POS-8 — what the point-of-sale screen needs before an invoice
 * is saved. Route middleware: `Pos_invoice-Add` or `Pos_invoice-Edit`.
 */
class PosController extends ApiController
{
    public function catalog(Request $request, PosService $pos)
    {
        return $this->ok($pos->catalog($request->user()));
    }

    public function customerLookup(Request $request, PosService $pos)
    {
        $in = $request->validate(['phone' => ['required', 'string', 'max:255']]);

        return $this->ok(['customers' => $pos->lookup($request->user(), $in['phone'])]);
    }

    public function preview(Request $request, PosService $pos)
    {
        return $this->ok($pos->preview(self::cart($request)));
    }

    /** the cart as the app sends it (shared by preview, create and update) */
    public static function cart(Request $request): array
    {
        return $request->validate([
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.type' => ['required', 'in:service,product'],
            'items.*.id' => ['required', 'integer', 'min:1'],
            'items.*.staff_id' => ['required', 'integer', 'min:1'],
            'items.*.qty' => ['required', 'integer', 'between:1,20'],
            'service_discount' => ['nullable', 'numeric', 'between:0,100'],
            'product_discount' => ['nullable', 'numeric', 'between:0,100'],
            'tip' => ['nullable', 'numeric', 'between:0,100000'],
            'payment_method' => ['nullable', 'string', 'max:255', Rule::exists('tbl_payment_method', 'name')->whereNull('deleted_at')],
            'notes' => ['nullable', 'string', 'max:2000'],
            'customer' => ['nullable', 'array'],
            'customer.name' => ['nullable', 'string', 'max:255'],
            'customer.phone' => ['nullable', 'string', 'max:255'],
            'customer.email' => ['nullable', 'email', 'max:255'],
        ]);
    }
}
