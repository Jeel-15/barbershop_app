<?php

namespace App\Services\Api;

use App\Models\Product;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * CAT-1 .. CAT-3 — services, service categories and products (web:
 * ServiceController, ServicecategoryController, ProductController).
 * Images go to the same `public` disk folders the web uses.
 */
class CatalogAdmin
{
    // ------------------------------------------------------------------ services

    /** @return array{0: array, 1: int} */
    public function services(array $f, int $page, int $perPage): array
    {
        // web: inner join to the category (a soft-deleted category still lists its services)
        $q = Service::query()
            ->join('tbl_service_category', 'tbl_service.category_id', '=', 'tbl_service_category.id')
            ->select('tbl_service.*', 'tbl_service_category.category_name')
            ->when(!empty($f['category_id']), fn ($w) => $w->where('tbl_service.category_id', $f['category_id']))
            ->when(isset($f['active']) && $f['active'] !== '', fn ($w) => $w->where('tbl_service.status', (int) $f['active']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($s) => $s->where('tbl_service.service_name', 'like', $like)
                    ->orWhere('tbl_service_category.category_name', 'like', $like)
                    ->orWhere('tbl_service.duration', 'like', $like)
                    ->orWhere('tbl_service.price', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->orderBy('tbl_service_category.category_name')->orderBy('tbl_service.service_name')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($s) => $this->service($s))->all(), $total];
    }

    public function findService(int $id): ?array
    {
        $s = Service::query()
            ->join('tbl_service_category', 'tbl_service.category_id', '=', 'tbl_service_category.id')
            ->select('tbl_service.*', 'tbl_service_category.category_name')
            ->where('tbl_service.id', $id)->first();

        return $s ? $this->service($s) : null;
    }

    private function service(Service $s): array
    {
        return [
            'id' => (int) $s->id,
            'name' => $s->service_name,
            'category_id' => (int) $s->category_id,
            'category_name' => $s->category_name ?? optional($s->category)->category_name,
            'price' => Money::str($s->price),
            'duration' => (int) $s->duration,
            'active' => (int) $s->status === 1,
            'eligible_for_tip' => (int) $s->tip_status === 1,
            'commission_percent' => $s->commission === null ? null : Money::str($s->commission),
            'description' => $s->description,
            'image_url' => Media::image($s->service_img),
            'home_section' => $s->home_section,
        ];
    }

    public function createService(User $user, array $in, ?UploadedFile $image): int
    {
        $s = new Service();
        $s->created_by = $user->id;
        $this->fillService($s, $in);
        if ($image) {
            $s->service_img = $image->store('service_images', 'public');
        }
        $s->save();

        return (int) $s->id;
    }

    public function updateService(int $id, array $in, ?UploadedFile $image): bool
    {
        $s = Service::find($id);
        if (!$s) {
            return false;
        }
        $this->fillService($s, $in);
        if ($image) {
            $this->deleteFile($s->service_img);
            $s->service_img = $image->store('service_images', 'public');
        }
        $s->save();

        return true;
    }

    private function fillService(Service $s, array $in): void
    {
        $s->category_id = $in['category_id'];
        $s->service_name = $in['name'];
        $s->price = $in['price'];
        $s->duration = $in['duration'];
        $s->status = $in['active_status'] ? 1 : 0;
        $s->tip_status = $in['eligible_for_tip'] ? 1 : 0;
        $s->commission = $in['commission'] ?? null;
        $s->description = $in['description'] ?? null;
    }

    public function deleteService(int $id): bool
    {
        $s = Service::find($id);
        if (!$s) {
            return false;
        }
        $this->deleteFile($s->service_img);
        $s->delete();

        return true;
    }

    public function setHomeSection(int $id, ?string $section): bool
    {
        $s = Service::find($id);
        if (!$s) {
            return false;
        }
        $s->home_section = $section ?: null;
        $s->save();

        return true;
    }

    // ------------------------------------------------------------------ categories

    public function categories(?string $q = null): array
    {
        return ServiceCategory::query()
            ->when($q, fn ($w) => $w->where('category_name', 'like', "%{$q}%"))
            ->orderBy('category_name')->get()
            ->map(fn ($c) => $this->category($c))->all();
    }

    public function findCategory(int $id): ?array
    {
        $c = ServiceCategory::find($id);

        return $c ? $this->category($c) : null;
    }

    private function category(ServiceCategory $c): array
    {
        return [
            'id' => (int) $c->id,
            'name' => $c->category_name,
            'description' => $c->description,
            'image_url' => Media::image($c->service_image),
        ];
    }

    public function createCategory(User $user, array $in, ?UploadedFile $image): int
    {
        $c = new ServiceCategory();
        $c->created_by = $user->id;
        $c->category_name = $in['name'];
        $c->description = $in['description'] ?? null;
        if ($image) {
            $c->service_image = $image->store('service_images', 'public');
        }
        $c->save();

        return (int) $c->id;
    }

    public function updateCategory(int $id, array $in, ?UploadedFile $image): bool
    {
        $c = ServiceCategory::find($id);
        if (!$c) {
            return false;
        }
        $c->category_name = $in['name'];
        $c->description = $in['description'] ?? null;
        if ($image) {
            $this->deleteFile($c->service_image);
            $c->service_image = $image->store('service_images', 'public');
        }
        $c->save();

        return true;
    }

    /** web: soft delete only; its services stay (they vanish from the public site) */
    public function deleteCategory(int $id): bool
    {
        $c = ServiceCategory::find($id);
        if (!$c) {
            return false;
        }
        $c->delete();

        return true;
    }

    // ------------------------------------------------------------------ products

    /** @return array{0: array, 1: int} */
    public function products(array $f, int $page, int $perPage): array
    {
        $q = Product::query()
            ->join('tbl_service_category', 'tbl_product.category_id', '=', 'tbl_service_category.id')
            ->select('tbl_product.*', 'tbl_service_category.category_name')
            ->when(!empty($f['category_id']), fn ($w) => $w->where('tbl_product.category_id', $f['category_id']))
            ->when(isset($f['active']) && $f['active'] !== '', fn ($w) => $w->where('tbl_product.status', (int) $f['active']))
            ->when(!empty($f['q']), function ($w) use ($f) {
                $like = '%' . $f['q'] . '%';
                $w->where(fn ($s) => $s->where('tbl_product.product_name', 'like', $like)
                    ->orWhere('tbl_service_category.category_name', 'like', $like)
                    ->orWhere('tbl_product.price', 'like', $like));
            });

        $total = (clone $q)->count();
        $rows = $q->orderBy('tbl_product.product_name')->forPage($page, $perPage)->get();

        return [$rows->map(fn ($p) => $this->product($p))->all(), $total];
    }

    public function findProduct(int $id): ?array
    {
        $p = Product::query()
            ->join('tbl_service_category', 'tbl_product.category_id', '=', 'tbl_service_category.id')
            ->select('tbl_product.*', 'tbl_service_category.category_name')
            ->where('tbl_product.id', $id)->first();

        return $p ? $this->product($p) : null;
    }

    private function product(Product $p): array
    {
        return [
            'id' => (int) $p->id,
            'name' => $p->product_name,
            'category_id' => (int) $p->category_id,
            'category_name' => $p->category_name,
            'price' => Money::str($p->price),
            'stock' => (int) $p->stock,
            'commission_percent' => Money::str($p->commission),
            'active' => (int) $p->status === 1,
            'description' => $p->description,
            'image_url' => Media::image($p->product_img),
        ];
    }

    public function createProduct(User $user, array $in, ?UploadedFile $image): int
    {
        $p = new Product();
        $p->created_by = $user->id;
        $this->fillProduct($p, $in);
        if ($image) {
            $p->product_img = $image->store('product_images', 'public');
        }
        $p->save();

        return (int) $p->id;
    }

    public function updateProduct(int $id, array $in, ?UploadedFile $image): bool
    {
        $p = Product::find($id);
        if (!$p) {
            return false;
        }
        $this->fillProduct($p, $in);
        if ($image) {
            $this->deleteFile($p->product_img);
            $p->product_img = $image->store('product_images', 'public');
        }
        $p->save();

        return true;
    }

    private function fillProduct(Product $p, array $in): void
    {
        $p->category_id = $in['category_id'];
        $p->product_name = $in['name'];
        $p->price = $in['price'];
        $p->stock = $in['stock'];
        $p->commission = $in['commission'];
        $p->status = $in['active_status'] ? 1 : 0;
        $p->description = $in['description'] ?? null;
    }

    public function deleteProduct(int $id): bool
    {
        $p = Product::find($id);
        if (!$p) {
            return false;
        }
        $this->deleteFile($p->product_img);
        $p->delete();

        return true;
    }

    private function deleteFile(?string $path): void
    {
        if ($path && Storage::disk('public')->exists($path)) {
            Storage::disk('public')->delete($path);
        }
    }
}
