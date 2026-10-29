<?php

/**
 * Settings for the Admin/Staff mobile API (v1). This file is new and only read
 * by the code under app/Http/Controllers/Api/V1 and app/Services/Api.
 */
return [

    'version' => 'v1',
    'build' => '1.0.0-p0',

    // Shop identity shown in the app (the web hard-codes these in its views).
    'shop_name' => 'Rosenthal Barbershop',
    'currency' => ['code' => 'CAD', 'symbol' => '$'],

    // Token lifetime in days and how many devices one user may stay signed in on.
    'token_days' => 30,
    'max_devices' => 5,

    // Pagination limits for list endpoints.
    'per_page_default' => 20,
    'per_page_max' => 50,

    // Uploads (same limits as the web forms): kilobytes.
    'upload_max_kb' => 2048,

    // The app refuses to run below this version and is nudged below `latest`.
    'min_app_version' => '1.0.0',
    'latest_app_version' => '1.0.0',

    // Behaviour switches the app reads from /bootstrap. Flip here, no app release needed.
    'feature_flags' => [
        // Complete a booked appointment into an invoice. OFF: the web cannot do this today.
        'complete_from_appointment' => true,
        // Show corrected (non-web) figures beside the web's numbers in reports.
        'strict_numbers' => false,
    ],

    // Tables/columns the code relies on. /health verifies them.
    'required_schema' => [
        'tables' => [
            'users', 'customers', 'roles', 'permissions', 'model_has_roles', 'role_has_permissions',
            'tbl_appointment', 'tbl_appointment_service', 'tbl_appointment_product',
            'tbl_service', 'tbl_service_category', 'tbl_product', 'tbl_gst', 'tbl_payment_method',
            'tbl_setting', 'tbl_slots', 'tbl_breaks', 'tbl_shop_closure', 'tbl_staff_service',
            'personal_access_tokens', 'password_reset_otps',
        ],
        'columns' => [
            'tbl_appointment' => ['booking_code', 'is_invoiced', 'invoice_number', 'invoice_created_by', 'total_amt', 'total_tax', 'total_tip'],
            'tbl_appointment_service' => ['requested_staff_id', 'is_first_available', 'service_commission', 'service_tip'],
            'tbl_breaks' => ['slot_id', 'staff_id', 'break_type'],
            'tbl_setting' => ['service_default_duration', 'service_fee', 'invoice_send_sts'],
        ],
    ],
];
