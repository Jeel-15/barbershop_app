<?php

namespace App\Services\Api;

use App\Models\Breaks;
use App\Models\Gst;
use App\Models\PaymentMethod;
use App\Models\Setting;
use App\Models\ShopClosure;
use App\Models\Slot;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * CAT-4 / CAT-5 / SHOP-1 .. SHOP-3 — GST, payment methods, shop settings, the
 * shop's opening hours and one-off closures (web: GstController,
 * PaymentmethodController, SettingController, SlotController, ShopcloseController).
 */
class ShopAdmin
{
    public const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    // ------------------------------------------------------------------ GST

    public function gstList(): array
    {
        return Gst::orderByDesc('default_status')->orderBy('id')->get()->map(fn ($g) => $this->gst($g))->all();
    }

    public function findGst(int $id): ?array
    {
        $g = Gst::find($id);

        return $g ? $this->gst($g) : null;
    }

    private function gst(Gst $g): array
    {
        return [
            'id' => (int) $g->id,
            'name' => $g->name,
            'rate' => Money::str($g->rate),
            'tax_type' => strtolower((string) ($g->tax_type ?? 'include')) === 'exclude' ? 'exclude' : 'include',
            'is_default' => (int) $g->default_status === 1,
        ];
    }

    /** web: making one GST the default clears the flag on all the others */
    public function createGst(User $user, array $in): int
    {
        return DB::transaction(function () use ($user, $in) {
            if ($in['is_default']) {
                Gst::query()->update(['default_status' => 0]);
            }
            $g = new Gst();
            $g->created_by = $user->id;
            $g->name = $in['name'];
            $g->rate = $in['rate'];
            $g->tax_type = $in['tax_type'];
            $g->default_status = $in['is_default'] ? 1 : 0;
            $g->save();

            return (int) $g->id;
        });
    }

    public function updateGst(int $id, array $in): bool
    {
        return DB::transaction(function () use ($id, $in) {
            $g = Gst::find($id);
            if (!$g) {
                return false;
            }
            if ($in['is_default']) {
                Gst::where('id', '!=', $g->id)->update(['default_status' => 0]);
            }
            $g->name = $in['name'];
            $g->rate = $in['rate'];
            $g->tax_type = $in['tax_type'];
            $g->default_status = $in['is_default'] ? 1 : 0;   // web: a save without the flag also un-defaults it
            $g->save();

            return true;
        });
    }

    public function makeGstDefault(int $id): bool
    {
        return DB::transaction(function () use ($id) {
            $g = Gst::find($id);
            if (!$g) {
                return false;
            }
            Gst::where('id', '!=', $id)->update(['default_status' => 0]);
            $g->default_status = 1;
            $g->save();

            return true;
        });
    }

    /** @return array{0: bool, 1: bool} [found, wasDefault] */
    public function deleteGst(int $id): array
    {
        $g = Gst::find($id);
        if (!$g) {
            return [false, false];
        }
        $was = (int) $g->default_status === 1;
        $g->delete();

        return [true, $was];
    }

    // ------------------------------------------------------------------ payment methods

    public function payments(): array
    {
        return PaymentMethod::orderBy('id')->get()->map(fn ($m) => ['id' => (int) $m->id, 'name' => $m->name])->all();
    }

    public function createPayment(string $name): array
    {
        $m = PaymentMethod::create(['name' => $name]);

        return ['id' => (int) $m->id, 'name' => $m->name];
    }

    public function updatePayment(int $id, string $name): ?array
    {
        $m = PaymentMethod::find($id);
        if (!$m) {
            return null;
        }
        $m->update(['name' => $name]);

        return ['id' => (int) $m->id, 'name' => $m->name];
    }

    public function deletePayment(int $id): bool
    {
        $m = PaymentMethod::find($id);
        if (!$m) {
            return false;
        }
        $m->delete();

        return true;
    }

    // ------------------------------------------------------------------ settings

    public function settings(): array
    {
        $s = Setting::where('id', 1)->first();
        if (!$s) {
            return ['general' => null, 'contact' => null];
        }

        return [
            'general' => [
                'service_reminder_day' => (int) $s->service_reminder_day,
                'service_default_duration' => (int) $s->service_default_duration,
                'service_fee' => Money::str($s->service_fee),
                'invoice_mail_send_status' => (int) $s->invoice_send_sts === 1,
            ],
            'contact' => [
                'footer_about' => $s->footer_about,
                'contact_address' => $s->contact_address,
                'contact_phone' => $s->contact_phone,
                'contact_email' => $s->contact_email,
                'support_email' => $s->support_email,
                'whatsapp' => $s->whatsapp,
                'website_url' => $s->website_url,
                'facebook_url' => $s->facebook_url,
                'instagram_url' => $s->instagram_url,
                'tiktok_url' => $s->tiktok_url,
                'youtube_url' => $s->youtube_url,
                'twitter_url' => $s->twitter_url,
                'linkedin_url' => $s->linkedin_url,
            ],
        ];
    }

    public function updateGeneral(array $in): void
    {
        $s = Setting::findOrFail(1);
        $s->service_reminder_day = $in['service_reminder_day'];
        $s->service_default_duration = $in['service_default_duration'];
        $s->service_fee = $in['service_fee'];
        $s->invoice_send_sts = $in['invoice_mail_send_status'] ? 1 : 0;
        $s->save();
    }

    public function updateContact(array $in): void
    {
        $s = Setting::findOrFail(1);
        $urls = ['website_url', 'facebook_url', 'instagram_url', 'tiktok_url', 'youtube_url', 'twitter_url', 'linkedin_url'];
        $data = [
            'footer_about' => $in['footer_about'] ?? null,
            'contact_address' => $in['contact_address'],
            'contact_phone' => $in['contact_phone'],
            'contact_email' => $in['contact_email'],
            'support_email' => ($in['support_email'] ?? null) ?: null,
            'whatsapp' => preg_replace('/\D+/', '', (string) ($in['whatsapp'] ?? '')),   // web: digits only
        ];
        foreach ($urls as $field) {
            $data[$field] = ($in[$field] ?? null) ?: null;
        }
        $s->fill($data);
        $s->save();
    }

    // ------------------------------------------------------------------ shop hours

    /** web: SlotController::index (the shop's own rows are staff_id = 0) */
    public function hours(): array
    {
        $slots = Slot::where('staff_id', 0)->with('breaks')->get()->keyBy('day_name');

        return array_map(function ($day) use ($slots) {
            $s = $slots->get($day);

            return [
                'day' => $day,
                'slot_id' => $s ? (int) $s->id : null,
                'is_day_off' => $s ? (bool) $s->is_day_off : false,
                'open_time' => $s && $s->open_time ? substr($s->open_time, 0, 5) : null,
                'close_time' => $s && $s->close_time ? substr($s->close_time, 0, 5) : null,
                'breaks' => $s ? $s->breaks->where('break_type', 1)->sortBy('break_start')->values()->map(fn ($b) => [
                    'break_start' => substr($b->break_start, 0, 5),
                    'break_end' => substr($b->break_end, 0, 5),
                ])->all() : [],
            ];
        }, self::DAYS);
    }

    /** web: SlotController::store — per listed day: hours, day-off flag, breaks replaced */
    public function saveHours(array $days): void
    {
        DB::transaction(function () use ($days) {
            foreach ($days as $d) {
                $slot = Slot::firstOrNew(['staff_id' => 0, 'day_name' => $d['day']]);
                $slot->is_day_off = $d['is_day_off'] ? 1 : 0;
                $slot->open_time = $d['open_time'] ?? null;
                $slot->close_time = $d['close_time'] ?? null;
                $slot->save();

                Breaks::where('slot_id', $slot->id)->delete();
                foreach ($d['breaks'] ?? [] as $b) {
                    Breaks::create([
                        'slot_id' => $slot->id,
                        'break_start' => $b['break_start'],
                        'break_end' => $b['break_end'],
                        'break_type' => 1,
                    ]);
                }
            }
        });
    }

    // ------------------------------------------------------------------ closures

    /** @return array{0: array, 1: int} */
    public function closures(array $f, int $page, int $perPage): array
    {
        $q = ShopClosure::query()
            ->when(!empty($f['from']), fn ($w) => $w->where('date', '>=', $f['from']))
            ->when(!empty($f['to']), fn ($w) => $w->where('date', '<=', $f['to']))
            ->when(!empty($f['q']), fn ($w) => $w->where('reason', 'like', '%' . $f['q'] . '%'));

        $total = (clone $q)->count();
        $rows = $q->orderByDesc('date')->orderByDesc('id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($c) => $this->closure($c))->all(), $total];
    }

    public function findClosure(int $id): ?array
    {
        $c = ShopClosure::find($id);

        return $c ? $this->closure($c) : null;
    }

    private function closure(ShopClosure $c): array
    {
        $full = (int) $c->closure_status === 1;
        $start = $full ? null : $c->start_time;
        $end = $full ? null : $c->end_time;

        return [
            'id' => (int) $c->id,
            'date' => $c->date->toDateString(),
            'full_day' => $full,
            'start_time' => $start ? substr($start, 0, 5) : null,
            'end_time' => $end ? substr($end, 0, 5) : null,
            'label' => $full ? 'Full Day Close' : Carbon::parse($start)->format('h:i A') . ' - ' . Carbon::parse($end)->format('h:i A'),
            'reason' => $c->reason,
        ];
    }

    public function createClosure(User $user, array $in): int
    {
        $c = new ShopClosure();
        $c->created_by = $user->id;
        $this->fillClosure($c, $in);
        $c->save();

        return (int) $c->id;
    }

    public function updateClosure(User $user, int $id, array $in): bool
    {
        $c = ShopClosure::find($id);
        if (!$c) {
            return false;
        }
        $c->created_by = $user->id;   // web: the editor becomes the creator
        $this->fillClosure($c, $in);
        $c->save();

        return true;
    }

    public function deleteClosure(int $id): bool
    {
        $c = ShopClosure::find($id);
        if (!$c) {
            return false;
        }
        $c->delete();

        return true;
    }

    private function fillClosure(ShopClosure $c, array $in): void
    {
        $full = (bool) $in['full_day'];
        $start = $end = null;
        if (!$full) {
            [$start, $end] = $this->partialWindow($in['start_time'] ?? null, $in['end_time'] ?? null);
        }
        $c->date = $in['date'];
        $c->closure_status = $full ? 1 : 0;
        $c->start_time = $start;
        $c->end_time = $end;
        $c->reason = $in['reason'] ?? null;
    }

    /** web: end must be after start; an end that is not (00:55) is moved 12 hours on (12:55) when that fixes it */
    private function partialWindow(?string $startTime, ?string $endTime): array
    {
        if (!$startTime || !$endTime) {
            throw ValidationException::withMessages(['start_time' => ['Start time and end time are required for a partial-day closure.']]);
        }

        $start = Carbon::parse('2000-01-01 ' . $startTime);
        $end = Carbon::parse('2000-01-01 ' . $endTime);

        if (!$end->gt($start)) {
            $plus12 = $end->copy()->addHours(12);
            if ($plus12->gt($start) && $plus12->isSameDay($start)) {
                $end = $plus12;
            }
        }
        if (!$end->gt($start)) {
            throw ValidationException::withMessages(['end_time' => ['End time must be after start time for a partial-day closure.']]);
        }

        return [$start->format('H:i:s'), $end->format('H:i:s')];
    }
}
