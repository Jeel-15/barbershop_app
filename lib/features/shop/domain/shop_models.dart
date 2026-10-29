import 'package:barbershop_app/core/utils/money.dart';

/// One weekday of the shop's opening hours (web: Slot Configuration).
class ShopDay {
  const ShopDay({
    required this.day,
    required this.isDayOff,
    required this.open,
    required this.close,
    required this.breaks,
  });

  factory ShopDay.fromJson(Map<String, dynamic> j) => ShopDay(
    day: (j['day'] ?? '').toString(),
    isDayOff: j['is_day_off'] == true,
    open: j['open_time']?.toString(),
    close: j['close_time']?.toString(),
    breaks: [
      for (final b in (j['breaks'] as List? ?? const []))
        (
          start: (b['break_start'] ?? '').toString(),
          end: (b['break_end'] ?? '').toString(),
        ),
    ],
  );

  final String day;
  final bool isDayOff;

  /// `HH:mm` or null.
  final String? open;
  final String? close;

  /// Kept as they are: the web's page has no break editor, but saving
  /// replaces them, so they are sent back unchanged.
  final List<({String start, String end})> breaks;

  ShopDay copyWith({
    bool? isDayOff,
    Object? open = _keep,
    Object? close = _keep,
  }) => ShopDay(
    day: day,
    isDayOff: isDayOff ?? this.isDayOff,
    open: identical(open, _keep) ? this.open : open as String?,
    close: identical(close, _keep) ? this.close : close as String?,
    breaks: breaks,
  );

  static const _keep = Object();

  Map<String, dynamic> toJson() => {
    'day': day,
    'is_day_off': isDayOff,
    if (open != null) 'open_time': open,
    if (close != null) 'close_time': close,
    'breaks': [
      for (final b in breaks) {'break_start': b.start, 'break_end': b.end},
    ],
  };
}

/// A shop closure (web: Shop Closures).
class ShopClosureItem {
  const ShopClosureItem({
    required this.id,
    required this.date,
    required this.fullDay,
    required this.start,
    required this.end,
    required this.label,
    required this.reason,
  });

  factory ShopClosureItem.fromJson(Map<String, dynamic> j) => ShopClosureItem(
    id: (j['id'] as num).toInt(),
    date: (j['date'] ?? '').toString(),
    fullDay: j['full_day'] == true,
    start: j['start_time']?.toString(),
    end: j['end_time']?.toString(),
    label: (j['label'] ?? '').toString(),
    reason: j['reason']?.toString(),
  );

  final int id;

  /// `yyyy-MM-dd`.
  final String date;
  final bool fullDay;

  /// `HH:mm` (partial closures).
  final String? start;
  final String? end;

  /// "Full Day Close" or "09:00 AM - 11:00 AM".
  final String label;
  final String? reason;
}

/// What the Add / Update Closure form sends.
class ClosureInput {
  const ClosureInput({
    required this.date,
    required this.fullDay,
    required this.start,
    required this.end,
    required this.reason,
  });

  final String date;
  final bool fullDay;
  final String? start;
  final String? end;
  final String reason;

  Map<String, dynamic> toJson() => {
    'date': date,
    'full_day': fullDay,
    if (!fullDay && start != null) 'start_time': start,
    if (!fullDay && end != null) 'end_time': end,
    'reason': reason.trim(),
  };
}

/// "General Business Settings".
class GeneralSettings {
  const GeneralSettings({
    required this.reminderDays,
    required this.defaultDuration,
    required this.serviceFee,
    required this.invoiceMail,
  });

  factory GeneralSettings.fromJson(Map<String, dynamic> j) => GeneralSettings(
    reminderDays: (j['service_reminder_day'] as num?)?.toInt() ?? 1,
    defaultDuration: (j['service_default_duration'] as num?)?.toInt() ?? 30,
    serviceFee: Money.parse(j['service_fee']),
    invoiceMail: j['invoice_mail_send_status'] == true,
  );

  final int reminderDays;
  final int defaultDuration;
  final Money serviceFee;
  final bool invoiceMail;
}

/// "Contact Details" (website footer, contact page, header, booking pages).
class ContactSettings {
  const ContactSettings(this.values);

  factory ContactSettings.fromJson(Map<String, dynamic> j) =>
      ContactSettings({for (final k in keys) k: (j[k] ?? '').toString()});

  /// API field names, in the web's order.
  static const keys = [
    'footer_about',
    'contact_address',
    'contact_phone',
    'whatsapp',
    'contact_email',
    'support_email',
    'website_url',
    'facebook_url',
    'instagram_url',
    'tiktok_url',
    'youtube_url',
    'twitter_url',
    'linkedin_url',
  ];

  final Map<String, String> values;

  String operator [](String k) => values[k] ?? '';
}

class ShopSettings {
  const ShopSettings({required this.general, required this.contact});

  factory ShopSettings.fromJson(Map<String, dynamic> j) => ShopSettings(
    general: GeneralSettings.fromJson(
      Map<String, dynamic>.from((j['general'] as Map?) ?? const {}),
    ),
    contact: ContactSettings.fromJson(
      Map<String, dynamic>.from((j['contact'] as Map?) ?? const {}),
    ),
  );

  final GeneralSettings general;
  final ContactSettings contact;
}
