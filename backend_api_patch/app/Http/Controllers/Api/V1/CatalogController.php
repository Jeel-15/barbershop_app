<?php

namespace App\Http\Controllers\Api\V1;

use App\Services\Api\CatalogAdmin;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * CAT-1 .. CAT-3 — services, service categories, products (web: ServiceController,
 * ServicecategoryController, ProductController). Permissions per route (see routes/api.php).
 *
 * Pictures need a multipart request. PHP does not read multipart bodies on PUT, so
 * editing accepts POST as well as PUT.
 */
class CatalogController extends ApiController
{
    public function __construct(private CatalogAdmin $catalog)
    {
    }

    // ------------------------------------------------------------------ services

    public function services(Request $request)
    {
        $f = $request->validate([
            'q' => ['nullable', 'string', 'max:100'],
            'category_id' => ['nullable', 'integer', 'min:1'],
            'active' => ['nullable', 'in:0,1'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->catalog->services($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function service(int $id)
    {
        $s = $this->catalog->findService($id);

        return $s ? $this->ok(['service' => $s]) : $this->fail('Service not found.', 404);
    }

    public function createService(Request $request)
    {
        $in = $this->serviceInput($request, true);
        $id = $this->catalog->createService($request->user(), $in, $request->file('image'));

        return $this->ok(['service' => $this->catalog->findService($id)], 'Service created successfully.', 201);
    }

    public function updateService(Request $request, int $id)
    {
        if (!$this->catalog->findService($id)) {
            return $this->fail('Service not found.', 404);
        }
        $this->catalog->updateService($id, $this->serviceInput($request, false), $request->file('image'));

        return $this->ok(['service' => $this->catalog->findService($id)], 'Service updated successfully.');
    }

    public function deleteService(int $id)
    {
        return $this->catalog->deleteService($id) ? $this->ok([], 'Service deleted successfully.') : $this->fail('Service not found.', 404);
    }

    public function homeSection(Request $request, int $id)
    {
        $in = $request->validate(['home_section' => ['nullable', 'in:signature_grooming']]);
        if (!$this->catalog->setHomeSection($id, $in['home_section'] ?? null)) {
            return $this->fail('Service not found.', 404);
        }

        return $this->ok(['service' => $this->catalog->findService($id)], 'Website section updated successfully.');
    }

    private function serviceInput(Request $request, bool $imageRequired): array
    {
        $in = $request->validate([
            'category_id' => ['required', 'integer', Rule::exists('tbl_service_category', 'id')->whereNull('deleted_at')],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0', 'max:99999999'],
            'duration' => ['required', 'integer', 'min:1', 'max:1440'],
            'image' => [$imageRequired ? 'required' : 'nullable', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)],
            'commission' => ['nullable', 'numeric', 'min:0', 'max:100'],
            'description' => ['nullable', 'string'],
            'active_status' => ['required', 'boolean'],
            'eligible_for_tip' => ['required', 'boolean'],
        ]);
        $in['active_status'] = $request->boolean('active_status');
        $in['eligible_for_tip'] = $request->boolean('eligible_for_tip');

        return $in;
    }

    // ------------------------------------------------------------------ categories

    public function categories(Request $request)
    {
        $request->validate(['q' => ['nullable', 'string', 'max:100']]);

        return $this->ok(['items' => $this->catalog->categories($request->query('q') ?: null)]);
    }

    public function category(int $id)
    {
        $c = $this->catalog->findCategory($id);

        return $c ? $this->ok(['category' => $c]) : $this->fail('Category not found.', 404);
    }

    public function createCategory(Request $request)
    {
        $id = $this->catalog->createCategory($request->user(), $this->categoryInput($request), $request->file('image'));

        return $this->ok(['category' => $this->catalog->findCategory($id)], 'Category created successfully.', 201);
    }

    public function updateCategory(Request $request, int $id)
    {
        if (!$this->catalog->findCategory($id)) {
            return $this->fail('Category not found.', 404);
        }
        $this->catalog->updateCategory($id, $this->categoryInput($request), $request->file('image'));

        return $this->ok(['category' => $this->catalog->findCategory($id)], 'Category updated successfully.');
    }

    public function deleteCategory(int $id)
    {
        return $this->catalog->deleteCategory($id) ? $this->ok([], 'Category deleted successfully.') : $this->fail('Category not found.', 404);
    }

    private function categoryInput(Request $request): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
            'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)],
        ]);
    }

    // ------------------------------------------------------------------ products

    public function products(Request $request)
    {
        $f = $request->validate([
            'q' => ['nullable', 'string', 'max:100'],
            'category_id' => ['nullable', 'integer', 'min:1'],
            'active' => ['nullable', 'in:0,1'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $this->catalog->products($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function product(int $id)
    {
        $p = $this->catalog->findProduct($id);

        return $p ? $this->ok(['product' => $p]) : $this->fail('Product not found.', 404);
    }

    public function createProduct(Request $request)
    {
        $id = $this->catalog->createProduct($request->user(), $this->productInput($request, true), $request->file('image'));

        return $this->ok(['product' => $this->catalog->findProduct($id)], 'Product created successfully.', 201);
    }

    public function updateProduct(Request $request, int $id)
    {
        if (!$this->catalog->findProduct($id)) {
            return $this->fail('Product not found.', 404);
        }
        $this->catalog->updateProduct($id, $this->productInput($request, false), $request->file('image'));

        return $this->ok(['product' => $this->catalog->findProduct($id)], 'Product updated successfully.');
    }

    public function deleteProduct(int $id)
    {
        return $this->catalog->deleteProduct($id) ? $this->ok([], 'Product deleted successfully.') : $this->fail('Product not found.', 404);
    }

    private function productInput(Request $request, bool $imageRequired): array
    {
        $in = $request->validate([
            'category_id' => ['required', 'integer', Rule::exists('tbl_service_category', 'id')->whereNull('deleted_at')],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0', 'max:99999999'],
            'stock' => ['required', 'integer', 'min:0'],
            'commission' => ['required', 'numeric', 'min:0'],
            'active_status' => ['required', 'boolean'],
            'image' => [$imageRequired ? 'required' : 'nullable', 'image', 'mimes:jpg,jpeg,png,gif', 'max:' . (int) config('api_v1.upload_max_kb', 2048)],
            'description' => ['nullable', 'string'],
        ]);
        $in['active_status'] = $request->boolean('active_status');

        return $in;
    }
}
