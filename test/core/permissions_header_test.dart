import 'dart:convert';
import 'dart:typed_data';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers by path: `{status, headers}`.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.byPath);

  final Map<String, (int, Map<String, List<String>>)> byPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, headers) =
        byPath[options.path] ?? (200, const <String, List<String>>{});
    return ResponseBody.fromString(
      jsonEncode(
        status < 300
            ? {'status': 1, 'message': 'OK', 'data': <String, dynamic>{}}
            : {'status': 0, 'message': 'no'},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _v1 = {
  'x-permissions-version': ['abc123'],
};

({ApiClient api, List<String> versions, List<String> forbidden}) _build(
  Map<String, (int, Map<String, List<String>>)> byPath,
) {
  final versions = <String>[];
  final forbidden = <String>[];
  final api = ApiClient(
    baseUrl: 'http://test/api/v1',
    readToken: () => 't',
    onPermissionsVersion: versions.add,
    onForbidden: () => forbidden.add('403'),
    dio: Dio()..httpClientAdapter = _Adapter(byPath),
    log: false,
  );
  return (api: api, versions: versions, forbidden: forbidden);
}

void main() {
  group('X-Permissions-Version', () {
    test('a signed-in answer with the header reports the version', () async {
      final t = _build({'/appointments': (200, _v1)});
      await t.api.get('/appointments');
      expect(t.versions, ['abc123']);
      expect(t.forbidden, isEmpty);
    });

    test('the header name is case-insensitive', () async {
      final t = _build({
        '/appointments': (
          200,
          {
            'X-PERMISSIONS-VERSION': ['ZZ9'],
          },
        ),
      });
      await t.api.get('/appointments');
      expect(t.versions, ['ZZ9']);
    });

    test('no header (an older server) triggers nothing', () async {
      final t = _build({'/appointments': (200, const {})});
      await t.api.get('/appointments');
      expect(t.versions, isEmpty);
      expect(t.forbidden, isEmpty);
    });

    test('/bootstrap and /auth/* never report (no refresh loop)', () async {
      final t = _build({
        '/bootstrap': (200, _v1),
        '/auth/me': (200, _v1),
        '/auth/login': (200, _v1),
      });
      await t.api.get('/bootstrap');
      await t.api.get('/auth/me');
      await t.api.post('/auth/login');
      expect(t.versions, isEmpty);
    });

    test('an error answer that carries the header still reports it', () async {
      final t = _build({'/customers': (422, _v1)});
      await expectLater(
        t.api.get('/customers'),
        throwsA(isA<ValidationFailure>()),
      );
      expect(t.versions, ['abc123']);
    });
  });

  group('403', () {
    test('calls the forbidden handler and still throws the failure', () async {
      final t = _build({'/staff': (403, _v1)});
      await expectLater(t.api.get('/staff'), throwsA(isA<ForbiddenFailure>()));
      expect(t.forbidden, ['403']);
      expect(t.versions, isEmpty); // the 403 handler covers it
    });

    test('a 403 from /bootstrap does not start another refresh', () async {
      final t = _build({'/bootstrap': (403, _v1)});
      await expectLater(
        t.api.get('/bootstrap'),
        throwsA(isA<ForbiddenFailure>()),
      );
      expect(t.forbidden, isEmpty);
    });
  });
}
