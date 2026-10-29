<?php

namespace App\Services\Api;

use App\Models\Gallery;
use App\Models\Testimonial;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * CONT-1 / CONT-2 — website content: testimonials and the gallery (web:
 * TestimonialController, GalleryController). Pictures use the same `public`
 * disk folders (`testimonials`, `gallery`) so the website shows them.
 */
class ContentAdmin
{
    // ------------------------------------------------------------------ testimonials

    /** @return array{0: array, 1: int} */
    public function testimonials(array $f, int $page, int $perPage): array
    {
        $q = Testimonial::query()
            ->when(isset($f['active']) && $f['active'] !== '', fn ($w) => $w->where('status', (int) $f['active']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($s) => $s->where('client_name', 'like', $like)->orWhere('review', 'like', $like)->orWhere('client_role', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->orderBy('sort_order')->orderByDesc('id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($t) => $this->testimonial($t))->all(), $total];
    }

    public function findTestimonial(int $id): ?array
    {
        $t = Testimonial::find($id);

        return $t ? $this->testimonial($t) : null;
    }

    private function testimonial(Testimonial $t): array
    {
        return [
            'id' => (int) $t->id,
            'client_name' => $t->client_name,
            'client_role' => $t->client_role,
            'review' => $t->review,
            'rating' => (int) $t->rating,
            'sort_order' => (int) $t->sort_order,
            'active' => (int) $t->status === 1,
            'image_url' => $t->image_url,
        ];
    }

    public function createTestimonial(User $user, array $in, ?UploadedFile $image): int
    {
        $t = new Testimonial();
        $t->created_by = $user->id;
        $this->fillTestimonial($t, $in);
        if ($image) {
            $t->client_image = $image->store('testimonials', 'public');
        }
        $t->save();

        return (int) $t->id;
    }

    public function updateTestimonial(int $id, array $in, ?UploadedFile $image): bool
    {
        $t = Testimonial::find($id);
        if (!$t) {
            return false;
        }
        $this->fillTestimonial($t, $in);
        if ($image) {
            $this->deleteTestimonialFile($t);
            $t->client_image = $image->store('testimonials', 'public');
        }
        $t->save();

        return true;
    }

    private function fillTestimonial(Testimonial $t, array $in): void
    {
        $t->client_name = $in['client_name'];
        $t->client_role = $in['client_role'] ?? 'Regular Client';
        $t->review = $in['review'];
        $t->rating = $in['rating'];
        $t->sort_order = $in['sort_order'] ?? 0;
        $t->status = $in['active_status'] ? 1 : 0;
    }

    public function deleteTestimonial(int $id): bool
    {
        $t = Testimonial::find($id);
        if (!$t) {
            return false;
        }
        $this->deleteTestimonialFile($t);
        $t->delete();

        return true;
    }

    /** the bundled default pictures live under frontend/ and are never removed */
    private function deleteTestimonialFile(Testimonial $t): void
    {
        if (!empty($t->client_image) && !str_starts_with($t->client_image, 'frontend/') && Storage::disk('public')->exists($t->client_image)) {
            Storage::disk('public')->delete($t->client_image);
        }
    }

    // ------------------------------------------------------------------ gallery

    /** @return array{0: array, 1: int} */
    public function gallery(int $page, int $perPage): array
    {
        $total = Gallery::count();
        $rows = Gallery::latest()->orderByDesc('id')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($g) => $this->picture($g))->all(), $total];
    }

    public function findPicture(int $id): ?array
    {
        $g = Gallery::find($id);

        return $g ? $this->picture($g) : null;
    }

    private function picture(Gallery $g): array
    {
        return [
            'id' => (int) $g->id,
            'image_url' => Media::image($g->image),
            'created_at' => optional($g->created_at)->toDateTimeString(),
        ];
    }

    public function addPicture(UploadedFile $image): int
    {
        return (int) Gallery::create(['image' => $image->store('gallery', 'public')])->id;
    }

    /** the web's replace endpoint also writes a column that does not exist and fails (Q50); here only the picture changes */
    public function replacePicture(int $id, UploadedFile $image): bool
    {
        $g = Gallery::find($id);
        if (!$g) {
            return false;
        }
        if ($g->image) {
            Storage::disk('public')->delete($g->image);
        }
        $g->image = $image->store('gallery', 'public');
        $g->save();

        return true;
    }

    public function deletePicture(int $id): bool
    {
        $g = Gallery::find($id);
        if (!$g) {
            return false;
        }
        if ($g->image) {
            Storage::disk('public')->delete($g->image);
        }
        $g->delete();

        return true;
    }
}
