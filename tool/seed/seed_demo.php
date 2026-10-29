<?php
/**
 * Fills the LOCAL dev database (barber_shop_db) with a realistic Edmonton
 * barbershop: staff with working hours, customers, six weeks of invoiced history
 * and two weeks of upcoming bookings, products, reviews, closures, shop settings.
 *
 * It follows the web's own rules (docs in the web's InvoiceController): tax is
 * 5% GST included in the price, service commission = price x service.commission,
 * tips are split evenly over the services of the invoice.
 *
 * Run:  php tool/seed/seed_demo.php        (backup first: backup_before_demo_*.sql)
 * It deletes the old appointments/customers (test debris) and builds new ones.
 * It never touches users 1, 2, 50, 51, sessions (personal_access_tokens) or the catalog.
 */

const TODAY = '2026-10-28';
const HISTORY_FROM = '2026-09-14';
const FUTURE_TO = '2026-11-11';

mt_srand(20261028);
$pdo = new PDO('mysql:host=127.0.0.1;dbname=barber_shop_db;charset=utf8mb4', 'root', '', [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
]);
$pdo->beginTransaction();

function pick(array $a) { return $a[mt_rand(0, count($a) - 1)]; }
function chance(float $p): bool { return mt_rand(0, 9999) / 10000 < $p; }
function weighted(array $items): mixed {
    $sum = array_sum(array_column($items, 1));
    $r = mt_rand(1, (int) ($sum * 100)) / 100;
    foreach ($items as [$v, $w]) { if (($r -= $w) <= 0) return $v; }
    return $items[0][0];
}
function ins(PDO $pdo, string $table, array $row): int {
    $cols = implode(',', array_map(fn ($c) => "`$c`", array_keys($row)));
    $ph = implode(',', array_fill(0, count($row), '?'));
    $pdo->prepare("INSERT INTO `$table` ($cols) VALUES ($ph)")->execute(array_values($row));
    return (int) $pdo->lastInsertId();
}
function hm(int $min): string { return sprintf('%02d:%02d:00', intdiv($min, 60), $min % 60); }
function mins(string $t): int { [$h, $m] = explode(':', $t); return $h * 60 + $m; }

$now = TODAY . ' 07:00:00';

// ---------------------------------------------------------------- clean the old test debris
foreach (['tbl_appointment_product', 'tbl_appointment_service', 'tbl_appointment', 'customers', 'tbl_shop_closure'] as $t) {
    $pdo->exec("DELETE FROM $t");
}
$pdo->exec("DELETE FROM tbl_testimonial WHERE client_name LIKE 'ZZ%'");
$pdo->exec("UPDATE users SET deleted_at='$now', active_status=0 WHERE id IN (64,65)");
$pdo->exec("DELETE FROM tbl_breaks WHERE break_type=2 AND slot_id=0");

// ---------------------------------------------------------------- shop settings
$pdo->exec('DELETE FROM tbl_setting');
ins($pdo, 'tbl_setting', [
    'id' => 1, 'service_reminder_day' => 2, 'service_default_duration' => 30, 'service_fee' => 0,
    'invoice_send_sts' => 0,
    'contact_address' => 'Edmonton, Alberta, Canada',
    'contact_phone' => '(780) 555-0140', 'contact_email' => 'hello@rosenthalbarbershop.ca',
    'support_email' => 'support@rosenthalbarbershop.ca',
    'footer_about' => 'Classic cuts, sharp fades and hot-towel shaves in the heart of Edmonton.',
    'whatsapp' => '17805550140', 'website_url' => 'https://rosenthalbarbershop.ca',
    'instagram_url' => 'https://instagram.com/rosenthalbarbershop',
    'facebook_url' => 'https://facebook.com/rosenthalbarbershop',
    'created_at' => $now, 'updated_at' => $now,
]);

// ---------------------------------------------------------------- products
$pdo->exec("UPDATE tbl_product SET stock=24, description='Light-hold hair oil for shine and a natural finish.' WHERE id=1");
$pdo->exec("UPDATE tbl_product SET stock=32, description='Rich, non-greasy shaving cream for a close, comfortable shave.' WHERE id=2");
$pdo->exec("UPDATE tbl_product SET stock=18, description='Softens and conditions the beard; cedar and amber scent.' WHERE id=3");
$products = [
    ['Matte Clay Pomade', 24.00, 28, 'Strong hold, matte finish. Works for textured and short styles.'],
    ['Classic Water Pomade', 22.00, 22, 'Medium hold, high shine, washes out easily.'],
    ['Beard Balm', 18.00, 15, 'Shapes and tames the beard with a light hold.'],
    ['Sea Salt Spray', 17.00, 14, 'Adds texture and volume for a beachy, lived-in look.'],
    ['Aftershave Balm', 20.00, 19, 'Calms skin after a shave. Alcohol free.'],
    ['Daily Shampoo', 16.00, 26, 'Gentle shampoo for everyday use.'],
    ['Barber Comb', 8.00, 40, 'Fine-tooth carbon comb, anti-static.'],
];
$productIds = [1, 2, 3];
foreach ($products as [$n, $p, $s, $d]) {
    $productIds[] = ins($pdo, 'tbl_product', [
        'product_name' => $n, 'created_by' => 1, 'category_id' => 4, 'price' => $p, 'stock' => $s,
        'commission' => 10, 'status' => 1, 'description' => $d, 'created_at' => $now, 'updated_at' => $now,
    ]);
}
$prodRows = [];
foreach ($pdo->query('SELECT id, price, commission FROM tbl_product WHERE deleted_at IS NULL AND status=1') as $r) {
    $prodRows[$r['id']] = $r;
}

// ---------------------------------------------------------------- services (the client's catalog)
$svc = [];
foreach ($pdo->query('SELECT id, price, duration, commission FROM tbl_service WHERE deleted_at IS NULL AND status=1') as $r) {
    $svc[$r['id']] = $r;
}
$activeServiceIds = implode(',', array_filter(array_keys($svc), fn ($i) => $i != 37)); // 37 = duplicate "Buzz Cut"

// ---------------------------------------------------------------- staff
$hash = $pdo->query('SELECT password FROM users WHERE id=51')->fetchColumn();
$newBarbers = [
    ['Omar Haddad', 'omar.haddad@example.com', '780 555 0151'],
    ['Tyler Brooks', 'tyler.brooks@example.com', '587 555 0152'],
    ['Jason Wong', 'jason.wong@example.com', '780 555 0153'],
    ['Andre Lavoie', 'andre.lavoie@example.com', '825 555 0154'],
];
$barbers = [42, 49];
foreach ($newBarbers as [$name, $email, $phone]) {
    $id = ins($pdo, 'users', [
        'created_by' => 1, 'name' => $name, 'email' => $email, 'phone' => $phone,
        'service_id' => $activeServiceIds, 'commission' => 50, 'is_barber' => 1, 'password' => $hash,
        'role' => 'Staff', 'active_status' => 1, 'created_at' => $now, 'updated_at' => $now,
    ]);
    ins($pdo, 'model_has_roles', ['role_id' => 2, 'model_type' => 'App\\Models\\User', 'model_id' => $id]);
    $barbers[] = $id;
}
$pdo->exec("UPDATE users SET commission=50 WHERE id IN (42,49)");
$pdo->exec("UPDATE users SET name='Mike' WHERE id=42");

// Working hours: [open, close] windows per day (1=Mon .. 7=Sun); missing day = day off.
$week = [
    42 => [2 => [[540, 780], [840, 1080]], 3 => [[540, 780], [840, 1080]], 4 => [[540, 780], [840, 1080]], 5 => [[540, 780], [840, 1080]], 6 => [[540, 780], [840, 1020]]],
    49 => [1 => [[600, 840], [900, 1140]], 2 => [[600, 840], [900, 1140]], 3 => [[600, 840], [900, 1140]], 4 => [[600, 840], [900, 1140]], 5 => [[600, 840], [900, 1140]], 6 => [[540, 780], [840, 1020]]],
    $barbers[2] => [3 => [[660, 900], [960, 1200]], 4 => [[660, 900], [960, 1200]], 5 => [[660, 900], [960, 1200]], 6 => [[540, 780], [840, 1140]], 7 => [[600, 840], [870, 1080]]],
    $barbers[3] => [1 => [[540, 780], [840, 1080]], 2 => [[540, 780], [840, 1080]], 3 => [[540, 780], [840, 1080]], 4 => [[540, 780], [840, 1080]], 5 => [[540, 780]]],
    $barbers[4] => [2 => [[720, 960], [1020, 1200]], 3 => [[720, 960], [1020, 1200]], 4 => [[720, 960], [1020, 1200]], 5 => [[720, 960], [1020, 1200]], 6 => [[600, 840], [900, 1140]]],
    $barbers[5] => [1 => [[540, 780], [840, 1080]], 3 => [[540, 780], [840, 1080]], 4 => [[540, 780], [840, 1080]], 5 => [[540, 780], [840, 1080]], 6 => [[540, 780], [840, 1080]]],
];
$dayNames = [1 => 'Monday', 2 => 'Tuesday', 3 => 'Wednesday', 4 => 'Thursday', 5 => 'Friday', 6 => 'Saturday', 7 => 'Sunday'];
foreach ($barbers as $b) {
    $pdo->prepare('DELETE FROM tbl_breaks WHERE staff_id=? AND break_type=1')->execute([$b]);
    $existing = [];
    foreach ($pdo->query("SELECT id, day_name FROM tbl_slots WHERE staff_id=$b") as $r) { $existing[$r['day_name']] = $r['id']; }
    foreach ($dayNames as $n => $dn) {
        $slotId = $existing[$dn] ?? ins($pdo, 'tbl_slots', [
            'day_name' => $dn, 'staff_id' => $b, 'is_day_off' => 0, 'created_at' => $now, 'updated_at' => $now,
        ]);
        $windows = $week[$b][$n] ?? [];
        $pdo->prepare('UPDATE tbl_slots SET is_day_off=? WHERE id=?')->execute([$windows ? 0 : 1, $slotId]);
        foreach ($windows as [$s, $e]) {
            ins($pdo, 'tbl_breaks', [
                'slot_id' => $slotId, 'staff_id' => $b, 'break_start' => hm($s), 'break_end' => hm($e),
                'break_type' => 1, 'created_at' => $now, 'updated_at' => $now,
            ]);
        }
    }
    $pdo->prepare('DELETE FROM tbl_staff_service WHERE staff_id=?')->execute([$b]);
    foreach (explode(',', $activeServiceIds) as $sid) {
        ins($pdo, 'tbl_staff_service', ['staff_id' => $b, 'service_id' => $sid, 'created_at' => $now, 'updated_at' => $now]);
    }
}

// ---------------------------------------------------------------- customers
$first = ['Liam', 'Noah', 'Ethan', 'Lucas', 'Mason', 'Logan', 'Jacob', 'Owen', 'Wyatt', 'Carter', 'Nathan', 'Caleb', 'Isaac', 'Connor', 'Dylan',
    'Ryan', 'Aiden', 'Hunter', 'Tristan', 'Gabriel', 'Mohammed', 'Ahmed', 'Omar', 'Ali', 'Hassan', 'Raj', 'Arjun', 'Amit', 'Harpreet', 'Gurpreet',
    'Jin', 'Kevin', 'Brandon', 'Tyler', 'Jordan', 'Marcus', 'Darnell', 'Andre', 'Miguel', 'Mateo', 'Luca', 'Felix', 'Nolan', 'Brayden', 'Cole',
    'Trevor', 'Shane', 'Derek', 'Greg', 'Paul', 'Peter', 'Frank', 'Tony', 'Sam', 'Ben', 'Max', 'Jack', 'Oliver', 'Henry', 'Theo'];
$last = ['Smith', 'Tremblay', 'Roy', 'Gagnon', 'Wilson', 'MacDonald', 'Campbell', 'Brown', 'Anderson', 'Patel', 'Singh', 'Khan', 'Nguyen', 'Chen', 'Lee',
    'Wong', 'Kim', 'Okafor', 'Haddad', 'Hussain', 'Ahmed', 'Sharma', 'Gill', 'Sandhu', 'Dhillon', 'Martin', 'Bouchard', 'Fraser', 'Stewart', 'Morrison',
    'Kowalski', 'Novak', 'Petrov', 'Ivanov', 'Rossi', 'Silva', 'Garcia', 'Lopez', 'Reyes', 'Cruz', 'Johnson', 'Miller', 'Taylor', 'Thompson', 'Clarke',
    'Hamilton', 'Murray', 'Ross', 'Bell', 'Wright'];
$customers = [];
$used = [];
$phoneN = 0;
while (count($customers) < 90) {
    $f = pick($first); $l = pick($last);
    if (isset($used["$f $l"])) continue;
    $used["$f $l"] = 1;
    $phoneN++;
    $phone = [780, 587, 825][$phoneN % 3] . '555' . sprintf('%04d', 100 + $phoneN);
    $customers[] = [
        'name' => "$f $l", 'phone' => $phone,
        'email' => chance(0.55) ? strtolower("$f.$l") . '@example.com' : null,
    ];
}

// ---------------------------------------------------------------- appointments
function bundle(array $svc): array {
    $cut = weighted([[25, 38], [26, 24], [27, 6], [28, 5], [29, 7], [30, 3], [31, 5]]);
    $out = [$cut];
    $kid = in_array($cut, [29, 30]);
    if (!$kid && chance(0.35)) $out[] = weighted([[33, 14], [32, 12], [34, 6]]);
    if (!$kid && chance(0.05)) $out[] = weighted([[38, 3], [39, 2], [43, 2], [45, 1], [42, 2]]);
    if (!$kid && chance(0.07)) { $out = [weighted([[35, 4], [36, 2], [46, 1]])]; if (chance(0.5)) $out[] = 33; }
    if (!$kid && chance(0.05)) $out = [weighted([[33, 5], [32, 3], [34, 2]])];
    return $out;
}

$notes = ['First visit', 'Prefers scissors on top', 'Number 2 on the sides', 'Same as last time', 'Running 5 minutes late',
    'Wedding this weekend', 'Sensitive skin, go easy on the razor', 'Please book the next one in 3 weeks'];
$payments = [['Debit', 45], ['Visa/Credit Card', 30], ['Cash', 20], ['Online', 5]];
$invoiceMakers = [1, 2, 2, 2];
$custIds = [];
$custFirstSeen = [];
$bookingSeq = [];
$weights = [];
foreach ($customers as $i => $c) { $weights[] = [$i, $i < 25 ? 6 : ($i < 55 ? 2.5 : 1)]; } // regulars come back
$stats = ['completed' => 0, 'cancelled' => 0, 'upcoming' => 0, 'revenue' => 0.0];
$taken = []; // customer|date|start, to avoid one client in two chairs at once

$d = new DateTime(HISTORY_FROM);
$end = new DateTime(FUTURE_TO);
for (; $d <= $end; $d->modify('+1 day')) {
    $date = $d->format('Y-m-d');
    $dow = (int) $d->format('N');
    $isPast = $date < TODAY;
    $daysAhead = (int) ((strtotime($date) - strtotime(TODAY)) / 86400);
    $fill = $isPast ? 0.62 : ($daysAhead <= 1 ? 0.7 : max(0.2, 0.5 - $daysAhead * 0.025));
    if ($dow >= 5 && $isPast) $fill += 0.1;   // Fri/Sat busier
    foreach ($barbers as $b) {
        foreach ($week[$b][$dow] ?? [] as [$ws, $we]) {
            $t = $ws + (chance(0.4) ? 5 * mt_rand(0, 3) : 0);
            while ($t < $we) {
                $services = bundle($svc);
                $dur = 0;
                foreach ($services as $s) $dur += (int) $svc[$s]['duration'];
                $dur = max(15, (int) (ceil($dur / 5) * 5));
                if ($t + $dur > $we) break;
                if (!chance($fill)) { $t += 15 * mt_rand(1, 3); continue; }

                $ci = weighted($weights);
                $key = "$ci|$date";
                if (isset($taken[$key])) { $t += 15; continue; }
                $taken[$key] = 1;
                $c = $customers[$ci];
                if (!isset($custIds[$ci])) {
                    $custIds[$ci] = ins($pdo, 'customers', [
                        'customer_name' => $c['name'], 'customer_phone' => $c['phone'], 'customer_email' => $c['email'],
                        'customer_status' => '1', 'created_at' => "$date 09:00:00", 'updated_at' => "$date 09:00:00",
                    ]);
                }
                $cid = $custIds[$ci];

                $bookingSeq[$date] = ($bookingSeq[$date] ?? 0) + 1;
                $code = 'BCB-' . str_replace('-', '', $date) . '-' . sprintf('%04d', $bookingSeq[$date]);
                $createdDay = (new DateTime($date))->modify('-' . mt_rand(0, 4) . ' day')->format('Y-m-d');
                if ($createdDay > TODAY) $createdDay = TODAY;
                $created = $createdDay . ' ' . sprintf('%02d:%02d:00', mt_rand(8, 20), mt_rand(0, 59));
                if ($createdDay == $date && $date == TODAY) $created = TODAY . ' 06:' . sprintf('%02d', mt_rand(0, 59)) . ':00';

                if ($isPast) {
                    $status = chance(0.06) ? 2 : 1;
                } else {
                    $status = chance($daysAhead <= 1 ? 0.7 : 0.45) ? 3 : 0;
                }

                $appt = [
                    'booking_code' => $code, 'date' => $date, 'slot_start' => hm($t), 'slot_end' => hm($t + $dur),
                    'name' => $c['name'], 'email' => $c['email'], 'phone' => $c['phone'],
                    'notes' => chance(0.12) ? pick($notes) : null, 'status' => $status, 'comment' => $c['name'],
                    'created_at' => $created, 'updated_at' => $isPast ? "$date " . hm($t + $dur) : $created,
                    'customer_id' => (string) $cid,
                ];

                $lines = [];
                $subtotal = 0.0;
                foreach ($services as $s) { $subtotal += (float) $svc[$s]['price']; }
                $soldProduct = null;
                if ($status == 1) {
                    if (chance(0.12)) { $soldProduct = pick(array_keys($prodRows)); $subtotal += (float) $prodRows[$soldProduct]['price']; }
                    $disc = chance(0.07) ? 10.0 : 0.0;
                    $discAmt = round($subtotal * $disc / 100, 2);
                    $net = $subtotal - $discAmt;
                    $tax = round($net * 5 / 105, 2);
                    $tip = chance(0.62) ? round(weighted([[0.10, 2], [0.15, 4], [0.18, 3], [0.20, 3]]) * $net * 2, 0) / 2 : 0.0;
                    $final = round($net + $tip, 2);
                    $appt += [
                        'is_invoiced' => '1',
                        'invoice_number' => 'INV-' . str_replace('-', '', $date) . '-' . sprintf('%04d', 1000 + $bookingSeq[$date]),
                        'invoice_created_by' => pick($invoiceMakers),
                        'total_amt' => $final, 'total_discount' => $discAmt, 'total_tax' => $tax, 'total_tip' => $tip,
                        'payment_method' => weighted($payments), 'discount_type' => '1',
                        'service_discount' => $disc, 'product_discount' => 0,
                    ];
                    $stats['completed']++;
                    $stats['revenue'] += $net;
                } elseif ($status == 2) {
                    $stats['cancelled']++;
                } else {
                    $stats['upcoming']++;
                }
                $apptId = ins($pdo, 'tbl_appointment', $appt);

                foreach ($services as $s) {
                    $row = [
                        'appointment_id' => $apptId, 'service_id' => $s, 'staff_id' => $b, 'requested_staff_id' => $b,
                        'is_first_available' => 0, 'product_commission' => 0, 'service_commission' => 0, 'service_tip' => 0,
                        'total_amt' => 0, 'status' => $status == 1 ? 1 : 0,
                        'comment' => $status == 1 ? 'Invoicing By POS' : 'Appointment from calendar',
                        'created_at' => $created, 'updated_at' => $appt['updated_at'],
                    ];
                    if ($status == 1) {
                        $price = (float) $svc[$s]['price'];
                        $base = $price * (1 - $disc / 100);
                        $row['service_commission'] = number_format($base * (float) $svc[$s]['commission'] / 100, 2, '.', '');
                        $row['service_tip'] = $tip / count($services);
                        $row['total_amt'] = $price;
                    }
                    ins($pdo, 'tbl_appointment_service', $row);
                }
                if ($soldProduct) {
                    ins($pdo, 'tbl_appointment_product', [
                        'appointment_id' => $apptId, 'staff_id' => $b, 'product_id' => $soldProduct, 'qty' => 1,
                        'amount' => $prodRows[$soldProduct]['price'],
                        'product_commision' => round((float) $prodRows[$soldProduct]['price'] * (float) $prodRows[$soldProduct]['commission'] / 100, 2),
                        'created_at' => $created, 'updated_at' => $appt['updated_at'],
                    ]);
                }
                $t += $dur + (chance(0.5) ? 0 : 5 * mt_rand(1, 4));
            }
        }
    }
}

// ---------------------------------------------------------------- reviews (shown on the website)
$pdo->exec("UPDATE tbl_testimonial SET status=1 WHERE id IN (1,2,3)");
$reviews = [
    ['Derek M.', 'Regular Client', 5, "Mike's skin fades are the best in the city. In and out on time, every time."],
    ['Harpreet S.', 'Beard Specialist Fan', 5, 'Hot shave with the straight razor is unreal. Feels like a proper barbershop.'],
    ['Connor B.', 'First-time Visitor', 5, 'Booked online, got a text, walked in and sat right down. Great cut and great chat.'],
    ['Amit P.', 'Regular Client', 4, 'Always clean, always friendly. Only wish they opened earlier on Sundays.'],
    ['Nolan T.', 'Skin Fade Fan', 5, 'Mutaz nailed the fade on the first try. I bring my son too, the kids cut is spot on.'],
    ['Marcus L.', 'Regular Client', 5, 'Fair prices and nobody rushes you. This is my shop now.'],
];
foreach ($reviews as $i => [$n, $role, $rate, $text]) {
    ins($pdo, 'tbl_testimonial', [
        'created_by' => 1, 'client_name' => $n, 'client_role' => $role, 'review' => $text, 'rating' => $rate,
        'client_image' => 'frontend/images/luxury/customer' . (($i % 3) + 1) . '.jpg',
        'sort_order' => $i + 4, 'status' => 1, 'created_at' => $now, 'updated_at' => $now,
    ]);
}

// ---------------------------------------------------------------- closures (Alberta stat holidays)
foreach ([
    ['2026-11-11', 1, null, null, 'Remembrance Day'],
    ['2026-12-24', 0, '09:00', '15:00', 'Christmas Eve: early close'],
    ['2026-12-25', 1, null, null, 'Christmas Day'],
    ['2026-12-26', 1, null, null, 'Boxing Day'],
    ['2027-01-01', 1, null, null, "New Year's Day"],
] as [$day, $full, $from, $to, $why]) {
    ins($pdo, 'tbl_shop_closure', [
        'created_by' => 1, 'date' => $day, 'closure_status' => $full, 'start_time' => $from, 'end_time' => $to,
        'reason' => $why, 'created_at' => $now, 'updated_at' => $now,
    ]);
}

$pdo->commit();
printf("Done. %d customers, %d completed (net revenue %.2f), %d cancelled, %d upcoming.\n",
    count($custIds), $stats['completed'], $stats['revenue'], $stats['cancelled'], $stats['upcoming']);
