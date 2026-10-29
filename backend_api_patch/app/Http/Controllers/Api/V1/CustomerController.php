<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Customer;
use App\Services\Api\CustomerService;
use Illuminate\Http\Request;

/**
 * CUST-1 .. CUST-6 — mirrors CustomerController. The module needs one of
 * Customer-Add / Edit / Delete (route middleware); writes need their own.
 */
class CustomerController extends ApiController
{
    public function index(Request $request, CustomerService $customers)
    {
        $f = $request->validate([
            'q' => ['nullable', 'string', 'max:100'],
            'status' => ['nullable', 'in:0,1'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $customers->paginate($f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function show(CustomerService $customers, int $id)
    {
        $profile = $customers->profile($id);

        return $profile ? $this->ok(['customer' => $profile]) : $this->fail('Customer not found.', 404);
    }

    public function appointments(Request $request, CustomerService $customers, int $id)
    {
        if (!Customer::where('customer_id', $id)->exists()) {
            return $this->fail('Customer not found.', 404);
        }

        $f = $request->validate([
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d'],
            'status' => ['nullable', 'integer', 'between:0,4'],
            'staff_id' => ['nullable', 'integer', 'min:1'],
            'day_type' => ['nullable', 'in:Morning,Afternoon,Evening'],
            'q' => ['nullable', 'string', 'max:100'],
        ]);
        [$page, $perPage] = $this->pageParams($request);
        [$rows, $total] = $customers->appointments($id, $f, $page, $perPage);

        return $this->listing($rows, $total, $page, $perPage);
    }

    public function store(Request $request, CustomerService $customers)
    {
        $customer = $customers->create($this->input($request));

        return $this->ok(['customer' => CustomerService::present($customer)], 'Customer created successfully.', 201);
    }

    public function update(Request $request, CustomerService $customers, int $id)
    {
        $customer = Customer::where('customer_id', $id)->first();
        if (!$customer) {
            return $this->fail('Customer not found.', 404);
        }

        return $this->ok(['customer' => CustomerService::present($customers->update($customer, $this->input($request)))], 'Customer updated successfully.');
    }

    public function destroy(CustomerService $customers, int $id)
    {
        $customer = Customer::where('customer_id', $id)->first();
        if (!$customer) {
            return $this->fail('Customer not found.', 404);
        }

        $refused = $customers->delete($customer);

        return $refused ? $this->fail($refused, 409) : $this->ok([], 'Customer deleted successfully.');
    }

    /** same rules as the web's store/update */
    private function input(Request $request): array
    {
        return $request->validate([
            'full_name' => ['required', 'string', 'max:255'],
            'phone_number' => ['required', 'string', 'max:20'],
            'email' => ['nullable', 'email', 'max:255'],
            'status' => ['nullable', 'integer'],
        ]);
    }
}
