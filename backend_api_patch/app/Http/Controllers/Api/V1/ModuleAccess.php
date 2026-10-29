<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\User;

/**
 * Mirrors, one-to-one, the middleware that guards each admin route in
 * routes/web.php, so the mobile app shows exactly the modules the web admin
 * would let this user open.
 */
class ModuleAccess
{
    public static function for(User $user): array
    {
        $isStaff = $user->isStaffUser();

        return [
            'dashboard' => $user->canAny([
                'Dashboard-Today_Appointments',
                'Dashboard-Upcoming_Appointments',
                'Dashboard-Top_Services',
                'Dashboard-Top_Staff',
            ]),
            'appointments' => $user->can('Appointment-View'),
            'calendar' => $user->canAny(['Calender-View']),
            'invoices' => $user->canAny(['Pos_invoice-Add', 'Pos_invoice-Edit', 'Pos_invoice-Show_All']),
            'invoice_write' => $user->canAny(['Pos_invoice-Add', 'Pos_invoice-Edit']),
            'reports' => $user->canAny(['Report-View']) && !$isStaff,
            'staff_report' => $user->can('Report-View') && $isStaff,
            'customers' => $user->canAny(['Customer-Add', 'Customer-Edit', 'Customer-Delete']),
            'services' => $user->canAny(['Service-Add', 'Service-Edit', 'Service-Delete']),
            'service_categories' => $user->canAny(['Service_Category-Add', 'Service_Category-Edit', 'Service_Category-Delete']),
            'products' => $user->canAny(['Product-Add', 'Product-Edit', 'Product-Delete']),
            'gst' => $user->canAny(['Gst-Add', 'Gst-Edit', 'Gst-Delete']),
            'shop_closures' => $user->canAny(['Shop_Closures-Add', 'Shop_Closures-Edit', 'Shop_Closures-Delete']),
            'slots' => $user->canAny(['Slot-Update']),
            'staff' => $user->canAny(['Staff-Add', 'Staff-Edit', 'Staff-Delete']),
            'working_hours' => $isStaff && $user->can('Calender-View'),
            'testimonials' => $user->canAny(['Testimonial-Add', 'Testimonial-Edit', 'Testimonial-Delete']),
            'gallery' => $user->canAny(['Gallery-Add', 'Gallery-Edit', 'Gallery-Delete']),
            'settings' => $user->can('Setting-Payment_Method'),
            'payment_methods' => $user->can('Setting-Payment_Method'),
            'roles' => $user->canAny(['Role-Add', 'Role-Edit']),
            'profile' => true,
        ];
    }

    /**
     * Same landing choice as the web login (User::preferredAdminHomeRoute),
     * expressed as an app module key instead of a route name.
     */
    public static function home(User $user): string
    {
        $map = [
            'admin.dashboard' => 'dashboard',
            'admin.staff.staff-report' => 'staff_report',
            'admin.reports' => 'reports',
            'admin.invoice.index' => 'invoices',
            'admin.customers.index' => 'customers',
            'admin.profile.index' => 'profile',
        ];

        return $map[$user->preferredAdminHomeRoute()] ?? 'profile';
    }
}
