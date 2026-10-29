/// Shared by the splash and the welcome screen so the crest flies from the
/// middle of the splash into the corner of the welcome screen.
const crestHeroTag = 'rosenthal-crest';

/// Names and copy that identify the shop. The logo itself is the web
/// project's `public/assets/img/logo.png` (kept as assets/images/rosenthal_crest.png).
class AppBrand {
  static const name = 'Rosenthal Barbershop';
  static const short = 'ROSENTHAL';
  static const city = 'Edmonton, AB';

  /// The app is for the shop's own people only, never for customers.
  static const audience = 'STAFF & ADMIN';
}
