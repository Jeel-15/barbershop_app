import 'package:barbershop_app/features/auth/domain/perm.dart';

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
    this.permissionsVersion,
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
      permissionsVersion: j['permissions_version']?.toString(),
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

  /// The server's fingerprint of this user's role, permissions and scope
  /// (null while the server does not send one). When a response header shows a
  /// different one, an administrator changed this user's access.
  final String? permissionsVersion;

  /// True when [other] may do and see exactly what this user may.
  bool sameAccessAs(AuthUser other) {
    if (role != other.role ||
        home != other.home ||
        isStaff != other.isStaff ||
        isBarber != other.isBarber ||
        permissions.length != other.permissions.length ||
        !permissions.containsAll(other.permissions) ||
        roles.length != other.roles.length) {
      return false;
    }
    for (var i = 0; i < roles.length; i++) {
      if (roles[i] != other.roles[i]) return false;
    }
    final a = modules.toJson();
    final b = other.modules.toJson();
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  bool can(String permission) => permissions.contains(permission);

  bool canAny(Iterable<String> list) => list.any(permissions.contains);

  // Named questions. Each is exactly what the server asks for that action, so a
  // button is shown only when pressing it can work (a user is never offered
  // something the server will refuse).

  /// New invoice (the bar's centre button, the invoice list's +).
  bool get canCreateInvoice => can(Perm.posInvoiceAdd);

  bool get canEditInvoice => can(Perm.posInvoiceEdit);

  /// "Complete" on a booking creates its invoice, so it needs the same as a new one.
  bool get canCompleteBooking => canCreateInvoice;

  /// Mailing an invoice: the server asks for Add or Edit (viewing alone is not enough).
  bool get canMailInvoice =>
      canAny(const [Perm.posInvoiceAdd, Perm.posInvoiceEdit]);

  /// A staff member's services: read with any Staff permission, changed with Edit.
  bool get canSeeStaffServices => modules.staff;
  bool get canAssignStaffServices => can(Perm.staffEdit);

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
