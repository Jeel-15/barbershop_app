<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\ShopAdmin;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * CAT-4 / CAT-5 / SHOP-1 .. SHOP-3 — GST, payment methods, shop settings,
 * shop hours and closures. Permissions per route (see routes/api.php).
 */
class ShopController extends ApiController
{
    public function __construct(private ShopAdmin $shop)
    {
    }

    // ------------------------------------------------------------------ GST

    public function gstIndex()
    {
        return $this->ok(['items' => $this->shop->gstList()]);
    }

    public function gstCreate(Request $request)
    {
        $id = $this->shop->createGst($request->user(), $this->gstInput($request));

        return $this->ok(['gst' => $this->shop->findGst($id)], 'GST record created successfully.', 201);
    }

    public function gstUpdate(Request $request, int $id)
    {
        if (!$this->shop->findGst($id)) {
            return $this->fail('GST record not found.', 404);
        }
        $this->shop->updateGst($id, $this->gstInput($request));

        return $this->ok(['gst' => $this->shop->findGst($id)], 'GST record updated successfully.');
    }

    public function gstDefault(int $id)
    {
        return $this->shop->makeGstDefault($id)
            ? $this->ok(['gst' => $this->shop->findGst($id)], 'Default GST changed.')
            : $this->fail('GST record not found.', 404);
    }

    public function gstDelete(int $id)
    {
        [$found, $wasDefault] = $this->shop->deleteGst($id);
        if (!$found) {
            return $this->fail('GST record not found.', 404);
        }

        // web: allowed; the shop is then left with no tax on new invoices (Q16), so say so
        return $this->ok(['no_default_gst' => $wasDefault], $wasDefault
            ? 'GST record deleted. There is no default GST now, new invoices will have no tax.'
            : 'GST record deleted successfully.');
    }

    private function gstInput(Request $request): array
    {
        $in = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'rate' => ['required', 'numeric', 'min:0', 'max:100'],
            'tax_type' => ['required', 'in:include,exclude'],
            'is_default' => ['required', 'boolean'],
        ]);
        $in['is_default'] = $request->boolean('is_default');

        return $in;
    }

    // ------------------------------------------------------------------ payment methods

    public function paymentIndex()
    {
        return $this->ok(['items' => $this->shop->payments()]);
    }

    public function paymentCreate(Request $request)
    {
        $in = $request->validate(['name' => ['required', 'string', 'max:255', 'unique:tbl_payment_method,name']]);

        return $this->ok(['payment_method' => $this->shop->createPayment($in['name'])], 'Payment method created successfully', 201);
    }

    public function paymentUpdate(Request $request, int $id)
    {
        $in = $request->validate(['name' => ['required', 'string', 'max:255', Rule::unique('tbl_payment_method', 'name')->ignore($id)]]);
        $m = $this->shop->updatePayment($id, $in['name']);

        return $m ? $this->ok(['payment_method' => $m], 'Payment method updated successfully') : $this->fail('Payment method not found.', 404);
    }

    public function paymentDelete(int $id)
    {
        return $this->shop->deletePayment($id) ? $this->ok([], 'Payment method deleted successfully') : $this->fail('Payment method not found.', 404);
    }

    // ------------------------------------------------------------------ settings

    public function settings()
    {
        return $this->ok($this->shop->settings());
    }

    public function settingsGeneral(Request $request)
    {
        $in = $request->validate([
            'service_reminder_day' => ['required', 'integer', 'min:1'],
            'service_default_duration' => ['required', 'integer', 'min:1'],
            'service_fee' => ['required', 'numeric', 'min:0'],
            'invoice_mail_send_status' => ['required', 'boolean'],
        ]);
        $in['invoice_mail_send_status'] = $request->boolean('invoice_mail_send_status');
        $this->shop->updateGeneral($in);

        return $this->ok($this->shop->settings(), 'Setting Updated Successfully.');
    }

    public function settingsContact(Request $request)
    {
        $in = $request->validate([
            'footer_about' => ['nullable', 'string', 'max:2000'],
            'contact_address' => ['required', 'string', 'max:500'],
            'contact_phone' => ['required', 'string', 'max:50'],
            'contact_email' => ['required', 'email', 'max:150'],
            'support_email' => ['nullable', 'email', 'max:150'],
            'whatsapp' => ['nullable', 'string', 'max:30'],
            'website_url' => ['nullable', 'string', 'max:255'],
            'facebook_url' => ['nullable', 'string', 'max:255'],
            'instagram_url' => ['nullable', 'string', 'max:255'],
            'tiktok_url' => ['nullable', 'string', 'max:255'],
            'youtube_url' => ['nullable', 'string', 'max:255'],
            'twitter_url' => ['nullable', 'string', 'max:255'],
            'linkedin_url' => ['nullable', 'string', 'max:255'],
        ]);
        $this->shop->updateContact($in);

        return $this->ok($this->shop->settings(), 'Contact details updated successfully. Changes are live on the website.');
    }

    // ------------------------------------------------------------------ shop hours

    public function hours()
    {
        return $this->ok(['days' => $this->shop->hours()]);
    }

    public function saveHours(Request $request)
    {
        $in = $request->validate([
            'days' => ['required', 'array', 'min:1', 'max:7'],
            'days.*.day' => ['required', 'distinct', Rule::in(ShopAdmin::DAYS)],
            'days.*.is_day_off' => ['required', 'boolean'],
            'days.*.open_time' => ['nullable', 'date_format:H:i'],
            'days.*.close_time' => ['nullable', 'date_format:H:i'],
            'days.*.breaks' => ['nullable', 'array', 'max:10'],
            'days.*.breaks.*.break_start' => ['required', 'date_format:H:i'],
            'days.*.breaks.*.break_end' => ['required', 'date_format:H:i'],
        ]);

        $errors = [];
        foreach ($in['days'] as $i => $d) {
            $off = filter_var($d['is_day_off'], FILTER_VALIDATE_BOOLEAN);
            $in['days'][$i]['is_day_off'] = $off;
            foreach ($d['breaks'] ?? [] as $n => $b) {
                if ($b['break_end'] <= $b['break_start']) {
                    $errors["days.$i.breaks.$n.break_end"] = 'A break must end after it starts.';
                }
            }
            if (!$off) {
                if (empty($d['open_time']) || empty($d['close_time'])) {
                    $errors["days.$i.open_time"] = 'Opening and closing time are required for an open day.';
                } elseif ($d['close_time'] <= $d['open_time']) {
                    $errors["days.$i.close_time"] = 'Closing time must be after opening time.';
                }
            }
        }
        if ($errors) {
            return $this->fail('The given data was invalid.', 422, ['errors' => array_map(fn ($m) => [$m], $errors)]);
        }

        $this->shop->saveHours($in['days']);

        return $this->ok(['days' => $this->shop->hours()], 'Slot configuration stored successfully.');
    }

    // ------------------------------------------------------------------ closures

    public function closures(Request $request)
    {
        $f = $request->validate([
            'q' => ['nullable', 'string', 'max:100'],
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->shop->closures($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function closure(int $id)
    {
        $c = $this->shop->findClosure($id);

        return $c ? $this->ok(['closure' => $c]) : $this->fail('Shop closure not found.', 404);
    }

    public function closureCreate(Request $request)
    {
        $id = $this->shop->createClosure($request->user(), $this->closureInput($request));

        return $this->ok(['closure' => $this->shop->findClosure($id)], 'Shop closure created successfully.', 201);
    }

    public function closureUpdate(Request $request, int $id)
    {
        if (!$this->shop->findClosure($id)) {
            return $this->fail('Shop closure not found.', 404);
        }
        $this->shop->updateClosure($request->user(), $id, $this->closureInput($request));

        return $this->ok(['closure' => $this->shop->findClosure($id)], 'Shop closure updated successfully.');
    }

    public function closureDelete(int $id)
    {
        return $this->shop->deleteClosure($id) ? $this->ok([], 'Shop closure deleted successfully.') : $this->fail('Shop closure not found.', 404);
    }

    private function closureInput(Request $request): array
    {
        $in = $request->validate([
            'date' => ['required', 'date_format:Y-m-d'],
            'full_day' => ['required', 'boolean'],
            'start_time' => ['nullable', 'date_format:H:i'],
            'end_time' => ['nullable', 'date_format:H:i'],
            'reason' => ['nullable', 'string', 'max:2000'],
        ]);
        $in['full_day'] = $request->boolean('full_day');

        return $in;
    }
}
