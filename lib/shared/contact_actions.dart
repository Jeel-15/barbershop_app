import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's dialer with a customer's number. Used wherever a booking
/// shows a phone (Home, Calendar, Appointments).
Future<void> callCustomer(BuildContext context, String? phone) =>
    _open(context, Uri(scheme: 'tel', path: phone?.trim()), phone);

/// Opens the messaging app addressed to the customer.
Future<void> messageCustomer(BuildContext context, String? phone) =>
    _open(context, Uri(scheme: 'sms', path: phone?.trim()), phone);

/// Copies the number so it can be pasted anywhere (WhatsApp, a note...).
Future<void> copyPhone(BuildContext context, String? phone) async {
  if (phone == null || phone.trim().isEmpty) return;
  await Clipboard.setData(ClipboardData(text: phone.trim()));
  if (context.mounted) {
    showToast(context, 'Number copied.', kind: ToastKind.success);
  }
}

Future<void> _open(BuildContext context, Uri uri, String? phone) async {
  if (phone == null || phone.trim().isEmpty) return;
  final ok = await launchUrl(uri);
  if (!ok && context.mounted) {
    showToast(context, 'Could not open the app.', kind: ToastKind.error);
  }
}
