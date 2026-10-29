<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Appointment;
use App\Models\Gst;
use App\Models\PaymentMethod;
use App\Models\Setting;
use App\Services\Api\AppointmentReader;
use App\Services\Api\UserPresenter;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Everything the app needs at launch, in ONE request.
 */
class BootstrapController extends ApiController
{
    private const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    public function index(Request $request)
    {
        $user = $request->user();
        $setting = Setting::where('id', 1)->first();
        $gst = Gst::where('default_status', 1)->first();

        return $this->ok([
            'user' => UserPresenter::make($user),

            'shop' => [
                'name' => config('api_v1.shop_name'),
                'logo_url' => asset('assets/img/logo.png'),
                'address' => $setting->contact_address ?? null,
                'phone' => $setting->contact_phone ?? null,
                'email' => $setting->contact_email ?? null,
                'whatsapp' => $setting->whatsapp ?? null,
                'website' => $setting->website_url ?? null,
            ],

            'currency' => config('api_v1.currency'),
            'timezone' => config('app.timezone'),
            'server_time' => now()->toIso8601String(),

            // One default GST row drives every invoice. null => the web charges no tax.
            'tax' => $gst ? [
                'id' => $gst->id,
                'name' => $gst->name,
                'rate' => number_format((float) $gst->rate, 2, '.', ''),
                'type' => strtolower((string) $gst->tax_type) === 'exclude' ? 'exclude' : 'include',
            ] : null,

            'payment_methods' => PaymentMethod::orderBy('id')->get(['id', 'name'])
                ->map(fn ($p) => ['id' => $p->id, 'name' => $p->name])->values(),

            'statuses' => collect(range(0, 4))->map(fn ($code) => [
                'code' => $code,
                'key' => strtolower(Appointment::statusLabel($code)),
                'label' => Appointment::statusLabel($code),
            ])->values(),

            // What the web offers for each status. The app renders buttons from this.
            // (Single source of truth: AppointmentReader::actionMatrix, which also honours the feature flags.)
            'appointment_actions' => AppointmentReader::actionMatrix(),

            'slot_step_minutes' => $this->slotStep(),
            'shop_hours' => $this->shopHours(),

            'limits' => [
                'per_page_max' => (int) config('api_v1.per_page_max'),
                'upload_max_kb' => (int) config('api_v1.upload_max_kb'),
            ],

            'app' => [
                'api_version' => config('api_v1.version'),
                'build' => config('api_v1.build'),
                'min_app_version' => config('api_v1.min_app_version'),
                'latest_app_version' => config('api_v1.latest_app_version'),
                'feature_flags' => config('api_v1.feature_flags'),
            ],
        ]);
    }

    /**
     * Same rule the web booking engine uses (WebsiteController::slotStepMinutes).
     */
    private function slotStep(): int
    {
        $step = (int) (Setting::query()->value('service_default_duration') ?: 15);
        if ($step < 5) {
            $step = 15;
        }

        return min($step, 60);
    }

    /**
     * Shop opening hours (the rows with staff_id = 0), Monday first.
     */
    private function shopHours(): array
    {
        $rows = DB::table('tbl_slots')->where('staff_id', 0)->get()->keyBy('day_name');

        return collect(self::DAYS)->map(function ($day) use ($rows) {
            $row = $rows->get($day);

            return [
                'day' => $day,
                'is_day_off' => $row ? (bool) $row->is_day_off : false,
                'open' => $row && $row->open_time ? substr($row->open_time, 0, 5) : null,
                'close' => $row && $row->close_time ? substr($row->close_time, 0, 5) : null,
            ];
        })->values()->all();
    }
}
