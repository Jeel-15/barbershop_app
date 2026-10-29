<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\ContentAdmin;
use Illuminate\Http\Request;

/**
 * CONT-1 testimonials, CONT-2 gallery (web: TestimonialController, GalleryController).
 * Pictures need multipart, so editing accepts POST as well as PUT.
 */
class ContentController extends ApiController
{
    public function __construct(private ContentAdmin $content)
    {
    }

    // ------------------------------------------------------------------ testimonials

    public function testimonials(Request $request)
    {
        $f = $request->validate(['q' => ['nullable', 'string', 'max:100'], 'active' => ['nullable', 'in:0,1']]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->content->testimonials($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function testimonial(int $id)
    {
        $t = $this->content->findTestimonial($id);

        return $t ? $this->ok(['testimonial' => $t]) : $this->fail('Testimonial not found.', 404);
    }

    public function createTestimonial(Request $request)
    {
        $id = $this->content->createTestimonial($request->user(), $this->testimonialInput($request), $request->file('image'));

        return $this->ok(['testimonial' => $this->content->findTestimonial($id)], 'Testimonial added successfully.', 201);
    }

    public function updateTestimonial(Request $request, int $id)
    {
        if (!$this->content->findTestimonial($id)) {
            return $this->fail('Testimonial not found.', 404);
        }
        $this->content->updateTestimonial($id, $this->testimonialInput($request), $request->file('image'));

        return $this->ok(['testimonial' => $this->content->findTestimonial($id)], 'Testimonial updated successfully.');
    }

    public function deleteTestimonial(int $id)
    {
        return $this->content->deleteTestimonial($id) ? $this->ok([], 'Testimonial deleted successfully.') : $this->fail('Testimonial not found.', 404);
    }

    private function testimonialInput(Request $request): array
    {
        $in = $request->validate([
            'client_name' => ['required', 'string', 'max:255'],
            'client_role' => ['nullable', 'string', 'max:255'],
            'review' => ['required', 'string', 'max:2000'],
            'rating' => ['required', 'integer', 'min:1', 'max:5'],
            'sort_order' => ['nullable', 'integer', 'min:0'],
            'active_status' => ['required', 'boolean'],
            'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,gif,webp', 'max:' . (int) config('api_v1.upload_max_kb', 2048)],
        ]);
        $in['active_status'] = $request->boolean('active_status');

        return $in;
    }

    // ------------------------------------------------------------------ gallery

    public function gallery(Request $request)
    {
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->content->gallery($page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function addPicture(Request $request)
    {
        $in = $request->validate(['image' => ['required', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)]]);
        $id = $this->content->addPicture($request->file('image'));

        return $this->ok(['picture' => $this->content->findPicture($id)], 'Image added successfully', 201);
    }

    public function replacePicture(Request $request, int $id)
    {
        if (!$this->content->findPicture($id)) {
            return $this->fail('Image not found.', 404);
        }
        $request->validate(['image' => ['required', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)]]);
        $this->content->replacePicture($id, $request->file('image'));

        return $this->ok(['picture' => $this->content->findPicture($id)], 'Image updated successfully');
    }

    public function deletePicture(int $id)
    {
        return $this->content->deletePicture($id) ? $this->ok([], 'Image deleted successfully') : $this->fail('Image not found.', 404);
    }
}
