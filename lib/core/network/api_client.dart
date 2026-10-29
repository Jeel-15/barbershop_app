import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/failure.dart';

/// A successful API answer, already unwrapped from the envelope
/// `{status: 1, message, data, meta?}`.
class ApiResponse {
  const ApiResponse({
    required this.data,
    this.meta = const {},
    this.message = 'OK',
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic> meta;
  final String message;
}

typedef TokenReader = FutureOr<String?> Function();

/// The only place that talks HTTP. Adds the bearer token, turns every error
/// into a [Failure], retries safe reads a couple of times, and logs one line
/// per call in debug builds (never bodies, tokens or personal data).
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenReader readToken,
    void Function()? onUnauthorized,
    Dio? dio,
    bool log = kDebugMode,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 12)
      ..sendTimeout = const Duration(seconds: 30)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers = {'Accept': 'application/json'}
      ..validateStatus = (s) => s != null && s >= 200 && s < 300;

    _dio.interceptors.addAll([
      _AuthInterceptor(readToken, onUnauthorized),
      _RetryInterceptor(_dio),
      if (log) _LogInterceptor(),
    ]);
  }

  final Dio _dio;

  Future<ApiResponse> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _send('GET', path, query: query, cancelToken: cancelToken);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) => _send(
    'POST',
    path,
    body: body,
    query: query,
    headers: headers,
    cancelToken: cancelToken,
  );

  Future<ApiResponse> put(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) => _send('PUT', path, body: body, cancelToken: cancelToken);

  Future<ApiResponse> patch(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) => _send('PATCH', path, body: body, cancelToken: cancelToken);

  Future<ApiResponse> delete(String path, {CancelToken? cancelToken}) =>
      _send('DELETE', path, cancelToken: cancelToken);

  Future<ApiResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(method: method, headers: headers),
      );
      return parseEnvelope(res.data);
    } on DioException catch (e) {
      throw failureFromDio(e);
    }
  }

  /// Exposed for tests.
  @visibleForTesting
  static ApiResponse parseEnvelope(Object? raw) {
    if (raw is! Map) {
      throw const UnknownFailure('The server sent an unexpected answer.');
    }
    final json = Map<String, dynamic>.from(raw);
    if (json['status'] == 0) {
      throw ServerFailure(
        json['message']?.toString() ?? 'The request failed.',
        null,
        json['request_id']?.toString(),
      );
    }
    final data = json['data'];
    final meta = json['meta'];
    return ApiResponse(
      data: data is Map ? Map<String, dynamic>.from(data) : const {},
      meta: meta is Map ? Map<String, dynamic>.from(meta) : const {},
      message: json['message']?.toString() ?? 'OK',
    );
  }

  /// Maps a Dio error (and the API's failure envelope) to a [Failure].
  @visibleForTesting
  static Failure failureFromDio(DioException e) {
    if (e.error is Failure) return e.error! as Failure;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.cancel:
        return const UnknownFailure('Cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkFailure(
          'The secure connection could not be verified.',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    final res = e.response;
    if (res == null) return const NetworkFailure();

    final body = res.data;
    final json = body is Map
        ? Map<String, dynamic>.from(body)
        : const <String, dynamic>{};
    final message = json['message']?.toString();
    final requestId = json['request_id']?.toString();
    final code = res.statusCode ?? 0;

    switch (code) {
      case 401:
        return UnauthorizedFailure(
          message ?? 'Your session has ended. Please sign in again.',
          requestId,
        );
      case 403:
        return ForbiddenFailure(
          message ?? 'You do not have permission to do this.',
          requestId,
        );
      case 404:
        return NotFoundFailure(
          message ?? 'That item no longer exists.',
          requestId,
        );
      case 409:
        return ConflictFailure(
          message ?? 'That action is no longer possible.',
          requestId: requestId,
        );
      case 422:
        final raw = json['errors'];
        final fields = <String, List<String>>{};
        if (raw is Map) {
          raw.forEach((k, v) {
            fields[k.toString()] = v is List
                ? v.map((x) => x.toString()).toList()
                : [v.toString()];
          });
        }
        return ValidationFailure(
          message ?? 'Please check the highlighted fields.',
          fieldErrors: fields,
          requestId: requestId,
        );
      case 429:
        final after = int.tryParse(res.headers.value('retry-after') ?? '');
        return RateLimitedFailure(
          retryAfter: after == null ? null : Duration(seconds: after),
          requestId: requestId,
        );
      default:
        if (code >= 500) {
          return ServerFailure(
            message ?? 'Something went wrong on our side. Please try again.',
            code,
            requestId,
          );
        }
        return UnknownFailure(
          message ?? 'Something unexpected happened. Please try again.',
        );
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._readToken, this._onUnauthorized);

  final TokenReader _readToken;
  final void Function()? _onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final isLogin = err.requestOptions.path.contains('auth/login');
    if (err.response?.statusCode == 401 && !isLogin) {
      _onUnauthorized?.call();
    }
    handler.next(err);
  }
}

/// Safe reads (GET) are retried twice on network trouble, timeouts and 502-504.
/// Writes are never retried automatically (money and schedule must not repeat).
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;
  static const _max = 2;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final o = err.requestOptions;
    final attempt = (o.extra['attempt'] as int?) ?? 0;
    final transient =
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        {502, 503, 504}.contains(err.response?.statusCode);

    if (o.method == 'GET' &&
        transient &&
        attempt < _max &&
        err.type != DioExceptionType.cancel) {
      await Future<void>.delayed(
        Duration(milliseconds: 400 * math.pow(2, attempt).toInt()),
      );
      o.extra['attempt'] = attempt + 1;
      try {
        final res = await _dio.fetch<dynamic>(o);
        return handler.resolve(res);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}

class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['t0'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  void _line(RequestOptions o, Object status, [String? requestId]) {
    final t0 = o.extra['t0'] as int?;
    final ms = t0 == null
        ? ''
        : ' ${DateTime.now().millisecondsSinceEpoch - t0}ms';
    debugPrint(
      '[api] ${o.method} ${o.path} -> $status$ms${requestId == null ? '' : ' ($requestId)'}',
    );
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _line(response.requestOptions, response.statusCode ?? 0);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final body = err.response?.data;
    final id = body is Map ? body['request_id']?.toString() : null;
    _line(err.requestOptions, err.response?.statusCode ?? err.type.name, id);
    handler.next(err);
  }
}
