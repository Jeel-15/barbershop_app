/// The signed-in person and what they may do. Everything in the app (menus,
/// buttons, routes) is decided from [permissions] and [modules] exactly as the
/// server sent them, never from role names.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.roles,
    required this.isStaff,
    required this.isBarber,
    required this.profileImageUrl,
    required this.permissions,
    required this.modules,
    required this.home,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) {
    return AuthUser(
      id: (j['id'] as num).toInt(),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      phone: j['phone']?.toString(),
      role: (j['role'] ?? '').toString(),
      roles: [for (final r in (j['roles'] as List? ?? const [])) r.toString()],
      isStaff: j['is_staff'] == true,
      isBarber: j['is_barber'] == true,
      profileImageUrl: j['profile_image_url']?.toString(),
      permissions: {
        for (final p in (j['permissions'] as List? ?? const [])) p.toString(),
      },
      modules: AppModules.fromJson(
        Map<String, dynamic>.from((j['modules'] as Map?) ?? const {}),
      ),
      home: (j['home'] ?? 'dashboard').toString(),
    );
  }

  final int id;
  final String name;
  final String email;
  final String? phone;

  /// Panel role stored on the user (`Admin`, `Staff`, `Accountant`...). Staff
  /// scoping follows this value, like the web (Q24).
  final String role;

  /// Spatie roles (`Super-admin`, `Manager`...), for display only.
  final List<String> roles;
  final bool isStaff;
  final bool isBarber;
  final String? profileImageUrl;
  final Set<String> permissions;
  final AppModules modules;

  /// Which module the web would land on after sign-in.
  final String home;

  bool can(String permission) => permissions.contains(permission);

  bool canAny(Iterable<String> list) => list.any(permissions.contains);

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }

  /// Short role label for headers: the most specific spatie role, else the panel role.
  String get roleLabel => roles.isNotEmpty ? roles.first : role;
}

/// Server-computed visibility flags for the app's modules (`/bootstrap`).
class AppModules {
  const AppModules(this._flags);

  factory AppModules.fromJson(Map<String, dynamic> j) =>
      AppModules({for (final e in j.entries) e.key: e.value == true});

  final Map<String, bool> _flags;

  bool operator [](String key) => _flags[key] ?? false;

  bool get dashboard => this['dashboard'];
  bool get appointments => this['appointments'];
  bool get calendar => this['calendar'];
  bool get invoices => this['invoices'];
  bool get invoiceWrite => this['invoice_write'];
  bool get reports => this['reports'];
  bool get staffReport => this['staff_report'];
  bool get customers => this['customers'];
  bool get services => this['services'];
  bool get serviceCategories => this['service_categories'];
  bool get products => this['products'];
  bool get gst => this['gst'];
  bool get shopClosures => this['shop_closures'];
  bool get slots => this['slots'];
  bool get staff => this['staff'];
  bool get workingHours => this['working_hours'];
  bool get testimonials => this['testimonials'];
  bool get gallery => this['gallery'];
  bool get settings => this['settings'];
  bool get paymentMethods => this['payment_methods'];
  bool get roles => this['roles'];
  bool get profile => this['profile'];

  Map<String, bool> toJson() => Map.of(_flags);
}
