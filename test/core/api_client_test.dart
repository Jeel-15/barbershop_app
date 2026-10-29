import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted server: each request takes the next answer from the queue.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.answers);

  final List<_Answer> answers;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final a = answers.length > 1 ? answers.removeAt(0) : answers.first;
    if (a.error != null) {
      throw DioException(requestOptions: options, type: a.error!);
    }
    return ResponseBody.fromString(
      jsonEncode(a.body),
      a.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...?a.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Answer {
  const _Answer(this.status, this.body, {this.error, this.headers});

  final int status;
  final Map<String, dynamic> body;
  final DioExceptionType? error;
  final Map<String, List<String>>? headers;
}

const _ok = _Answer(200, {
  'status': 1,
  'message': 'OK',
  'data': {'x': 1},
  'meta': {'page': 1},
});

ApiClient _client(
  List<_Answer> answers, {
  String? token,
  void Function()? onUnauthorized,
  _FakeAdapter? adapter,
}) {
  final a = adapter ?? _FakeAdapter(answers);
  final dio = Dio()..httpClientAdapter = a;
  return ApiClient(
    baseUrl: 'http://test/api/v1',
    readToken: () => token,
    onUnauthorized: onUnauthorized,
    dio: dio,
    log: false,
  );
}

void main() {
  group('envelope', () {
    test('unwraps data, meta and message', () async {
      final res = await _client([_ok]).get('/me');
      expect(res.data, {'x': 1});
      expect(res.meta, {'page': 1});
      expect(res.message, 'OK');
    });

    test('an empty data answer becomes an empty map', () async {
      final res = await _client([
        const _Answer(200, {'status': 1, 'message': 'Done', 'data': {}}),
      ]).post('/x');
      expect(res.data, isEmpty);
      expect(res.message, 'Done');
    });

    test('status 0 inside a 200 is a failure', () async {
      expect(
        () => _client([
          const _Answer(200, {
            'status': 0,
            'message': 'Nope',
            'request_id': 'r1',
          }),
        ]).get('/x'),
        throwsA(
          isA<ServerFailure>().having((f) => f.requestId, 'requestId', 'r1'),
        ),
      );
    });
  });

  group('failures', () {
    Future<Failure> failing(_Answer a) async {
      try {
        await _client([a]).get('/x');
      } on Failure catch (f) {
        return f;
      }
      fail('expected a Failure');
    }

    test('401 -> Unauthorized with the server sentence', () async {
      final f = await failing(
        const _Answer(401, {
          'status': 0,
          'message': 'Session expired.',
          'request_id': 'a',
        }),
      );
      expect(f, isA<UnauthorizedFailure>());
      expect(f.userMessage, 'Session expired.');
      expect(f.requestId, 'a');
    });

    test('403 / 404 / 409', () async {
      expect(
        await failing(
          const _Answer(403, {'status': 0, 'message': 'No permission'}),
        ),
        isA<ForbiddenFailure>(),
      );
      expect(
        await failing(const _Answer(404, {'status': 0, 'message': 'Gone'})),
        isA<NotFoundFailure>(),
      );
      final c = await failing(
        const _Answer(409, {'status': 0, 'message': 'That time is taken.'}),
      );
      expect(c, isA<ConflictFailure>());
      expect(c.userMessage, 'That time is taken.');
    });

    test('422 keeps the field errors', () async {
      final f = await failing(
        const _Answer(422, {
          'status': 0,
          'message': 'The given data was invalid.',
          'errors': {
            'email': ['The email must be valid.'],
            'phone': ['Required', 'Too short'],
          },
        }),
      );
      expect(f, isA<ValidationFailure>());
      final v = f as ValidationFailure;
      expect(v.errorFor('email'), 'The email must be valid.');
      expect(v.errorFor('phone'), 'Required');
      expect(v.errorFor('name'), isNull);
      expect(v.userMessage, 'The email must be valid.');
    });

    test('429 reads Retry-After', () async {
      final f = await failing(
        const _Answer(
          429,
          {'status': 0, 'message': 'Slow'},
          headers: {
            'retry-after': ['7'],
          },
        ),
      );
      expect(f, isA<RateLimitedFailure>());
      expect((f as RateLimitedFailure).retryAfter, const Duration(seconds: 7));
    });

    test(
      '500 -> Server failure that can be retried, with the support code',
      () async {
        final f = await failing(
          const _Answer(500, {
            'status': 0,
            'message': 'Boom',
            'request_id': 'zz',
          }),
        );
        expect(f, isA<ServerFailure>());
        expect(f.retryable, isTrue);
        expect(f.requestId, 'zz');
      },
    );

    test('no connection and timeouts', () async {
      final net = _client([
        const _Answer(0, {}, error: DioExceptionType.connectionError),
      ]);
      await expectLater(net.post('/x'), throwsA(isA<NetworkFailure>()));
      final slow = _client([
        const _Answer(0, {}, error: DioExceptionType.receiveTimeout),
      ]);
      await expectLater(slow.post('/x'), throwsA(isA<TimeoutFailure>()));
    });
  });

  group('requests', () {
    test('sends the bearer token and JSON accept header', () async {
      final adapter = _FakeAdapter([_ok]);
      await _client([], token: 'tok-123', adapter: adapter).get('/me');
      expect(adapter.seen.single.headers['Authorization'], 'Bearer tok-123');
      expect(adapter.seen.single.headers['Accept'], 'application/json');
    });

    test('no token, no Authorization header', () async {
      final adapter = _FakeAdapter([_ok]);
      await _client([], adapter: adapter).get('/me');
      expect(adapter.seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      '401 calls onUnauthorized, except for the sign-in call itself',
      () async {
        var calls = 0;
        const unauthorized = _Answer(401, {'status': 0, 'message': 'x'});
        await expectLater(
          _client(
            [unauthorized],
            token: 't',
            onUnauthorized: () => calls++,
          ).get('/me'),
          throwsA(isA<UnauthorizedFailure>()),
        );
        expect(calls, 1);
        await expectLater(
          _client([
            unauthorized,
          ], onUnauthorized: () => calls++).post('/auth/login'),
          throwsA(isA<UnauthorizedFailure>()),
        );
        expect(
          calls,
          1,
          reason: 'a wrong password must not look like an expired session',
        );
      },
    );

    test('extra headers (Idempotency-Key) are sent on writes', () async {
      final adapter = _FakeAdapter([_ok]);
      await _client(
        [],
        adapter: adapter,
      ).post('/invoices', body: {'a': 1}, headers: {'Idempotency-Key': 'k1'});
      expect(adapter.seen.single.headers['Idempotency-Key'], 'k1');
      expect(adapter.seen.single.method, 'POST');
    });
  });

  group('retry', () {
    test(
      'a GET is retried after a connection error and then succeeds',
      () async {
        final adapter = _FakeAdapter([
          const _Answer(0, {}, error: DioExceptionType.connectionError),
          const _Answer(503, {'status': 0, 'message': 'busy'}),
          _ok,
        ]);
        final res = await _client([], adapter: adapter).get('/me');
        expect(res.data['x'], 1);
        expect(adapter.seen.length, 3);
      },
    );

    test('a GET gives up after two retries', () async {
      final adapter = _FakeAdapter([
        const _Answer(0, {}, error: DioExceptionType.connectionError),
      ]);
      await expectLater(
        _client([], adapter: adapter).get('/me'),
        throwsA(isA<NetworkFailure>()),
      );
      expect(adapter.seen.length, 3);
    });

    test(
      'a POST is never retried (money and schedule must not repeat)',
      () async {
        final adapter = _FakeAdapter([
          const _Answer(0, {}, error: DioExceptionType.connectionError),
        ]);
        await expectLater(
          _client([], adapter: adapter).post('/invoices', body: {}),
          throwsA(isA<NetworkFailure>()),
        );
        expect(adapter.seen.length, 1);
      },
    );

    test('4xx answers are not retried', () async {
      final adapter = _FakeAdapter([
        const _Answer(404, {'status': 0, 'message': 'x'}),
      ]);
      await expectLater(
        _client([], adapter: adapter).get('/x'),
        throwsA(isA<NotFoundFailure>()),
      );
      expect(adapter.seen.length, 1);
    });
  });
}
