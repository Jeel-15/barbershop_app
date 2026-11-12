/// Every permission the server knows, spelled exactly as it is stored (spatie).
///
/// The one place these strings live: screens ask `user.can(Perm.x)` or a named
/// question on [AuthUser], never a loose string. `test/permissions_contract_test.dart`
/// checks this list against the server's own list and routes, so a typo or a new
/// server permission cannot slip by unnoticed (a wrong name silently hides a button).
abstract final class Perm {
  static const appointmentView = 'Appointment-View';
  static const calendarView = 'Calender-View'; // sic: the server spells it so

  static const customerAdd = 'Customer-Add';
  static const customerEdit = 'Customer-Edit';
  static const customerDelete = 'Customer-Delete';

  static const dashboardTodayAppointments = 'Dashboard-Today_Appointments';
  static const dashboardUpcomingAppointments =
      'Dashboard-Upcoming_Appointments';
  static const dashboardTopServices = 'Dashboard-Top_Services';
  static const dashboardTopSellingProduct = 'Dashboard-Top_Selling_Product';

  static const galleryAdd = 'Gallery-Add';
  static const galleryDelete = 'Gallery-Delete';

  static const generalSettingUpdate = 'General_Setting-Update';
  static const paymentSettingUpdate = 'Payment_Setting-Update';
  static const settingPaymentMethod = 'Setting-Payment_Method';

  static const gstAdd = 'Gst-Add';
  static const gstEdit = 'Gst-Edit';
  static const gstDelete = 'Gst-Delete';

  static const posInvoiceAdd = 'Pos_invoice-Add';
  static const posInvoiceEdit = 'Pos_invoice-Edit';
  static const posInvoiceShowAll = 'Pos_invoice-Show_All';

  static const productAdd = 'Product-Add';
  static const productEdit = 'Product-Edit';
  static const productDelete = 'Product-Delete';

  static const reportView = 'Report-View';

  static const roleAdd = 'Role-Add';
  static const roleEdit = 'Role-Edit';
  static const roleDelete = 'Role-Delete';

  static const serviceCategoryAdd = 'Service_Category-Add';
  static const serviceCategoryEdit = 'Service_Category-Edit';
  static const serviceCategoryDelete = 'Service_Category-Delete';

  static const serviceAdd = 'Service-Add';
  static const serviceEdit = 'Service-Edit';
  static const serviceDelete = 'Service-Delete';

  static const shopClosuresAdd = 'Shop_Closures-Add';
  static const shopClosuresEdit = 'Shop_Closures-Edit';
  static const shopClosuresDelete = 'Shop_Closures-Delete';

  static const slotUpdate = 'Slot-Update';

  static const staffAdd = 'Staff-Add';
  static const staffEdit = 'Staff-Edit';
  static const staffDelete = 'Staff-Delete';

  static const testimonialAdd = 'Testimonial-Add';
  static const testimonialEdit = 'Testimonial-Edit';
  static const testimonialDelete = 'Testimonial-Delete';

  /// All of them (the contract test reads this).
  static const all = <String>[
    appointmentView,
    calendarView,
    customerAdd,
    customerEdit,
    customerDelete,
    dashboardTodayAppointments,
    dashboardUpcomingAppointments,
    dashboardTopServices,
    dashboardTopSellingProduct,
    galleryAdd,
    galleryDelete,
    generalSettingUpdate,
    paymentSettingUpdate,
    settingPaymentMethod,
    gstAdd,
    gstEdit,
    gstDelete,
    posInvoiceAdd,
    posInvoiceEdit,
    posInvoiceShowAll,
    productAdd,
    productEdit,
    productDelete,
    reportView,
    roleAdd,
    roleEdit,
    roleDelete,
    serviceCategoryAdd,
    serviceCategoryEdit,
    serviceCategoryDelete,
    serviceAdd,
    serviceEdit,
    serviceDelete,
    shopClosuresAdd,
    shopClosuresEdit,
    shopClosuresDelete,
    slotUpdate,
    staffAdd,
    staffEdit,
    staffDelete,
    testimonialAdd,
    testimonialEdit,
    testimonialDelete,
  ];
}
