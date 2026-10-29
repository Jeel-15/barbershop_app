/// Everything that can go wrong talking to the API, as one small hierarchy.
/// The network layer turns every error into one of these; screens switch on
/// the type and never see Dio exceptions or raw status codes.
sealed class Failure implements Exception {
  const Failure(this.message, {this.requestId, this.statusCode});

  /// The server's sentence when it sent one, otherwise a friendly default.
  final String message;

  /// Server `request_id`: shown as a "Support code" so a problem can be found in the API log.
  final String? requestId;
  final int? statusCode;

  /// What to tell the user.
  String get userMessage => message;

  /// Whether trying again could help.
  bool get retryable => false;

  @override
  String toString() => '$runtimeType($statusCode): $message';
}

/// No connection, DNS failure, refused connection.
final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'No connection. Check your internet and try again.',
  ]);

  @override
  bool get retryable => true;
}

final class TimeoutFailure extends Failure {
  const TimeoutFailure([
    super.message = 'The server took too long to answer. Please try again.',
  ]);

  @override
  bool get retryable => true;
}

/// 401: no token, expired token, signed out elsewhere.
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([
    super.message = 'Your session has ended. Please sign in again.',
    String? requestId,
  ]) : super(requestId: requestId, statusCode: 401);
}

/// 403: the account lacks the permission (the menu entry should vanish).
final class ForbiddenFailure extends Failure {
  const ForbiddenFailure([
    super.message = 'You do not have permission to do this.',
    String? requestId,
  ]) : super(requestId: requestId, statusCode: 403);
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure([
    super.message = 'That item no longer exists.',
    String? requestId,
  ]) : super(requestId: requestId, statusCode: 404);
}

/// 409: the action clashes with the current state (slot taken, already confirmed...).
/// The message is the server's explanation; the screen should also refresh.
final class ConflictFailure extends Failure {
  const ConflictFailure(super.message, {super.requestId})
    : super(statusCode: 409);
}

/// 422: field errors, keyed by field name, ready to show under the inputs.
final class ValidationFailure extends Failure {
  const ValidationFailure(
    super.message, {
    this.fieldErrors = const {},
    super.requestId,
  }) : super(statusCode: 422);

  final Map<String, List<String>> fieldErrors;

  String? errorFor(String field) {
    final list = fieldErrors[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  @override
  String get userMessage =>
      fieldErrors.values.expand((e) => e).firstOrNull ?? message;
}

/// 429: too many requests.
final class RateLimitedFailure extends Failure {
  const RateLimitedFailure({this.retryAfter, String? requestId})
    : super(
        'Too many requests. Please wait a moment and try again.',
        requestId: requestId,
        statusCode: 429,
      );

  final Duration? retryAfter;

  @override
  bool get retryable => true;
}

/// 5xx.
final class ServerFailure extends Failure {
  const ServerFailure([
    super.message = 'Something went wrong on our side. Please try again.',
    int? statusCode,
    String? requestId,
  ]) : super(statusCode: statusCode ?? 500, requestId: requestId);

  @override
  bool get retryable => true;
}

final class UnknownFailure extends Failure {
  const UnknownFailure([
    super.message = 'Something unexpected happened. Please try again.',
  ]);

  @override
  bool get retryable => true;
}
