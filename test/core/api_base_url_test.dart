import 'package:barbershop_app/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = '/rosen_barber/public/api/v1';

  test('a bare host becomes https with the API path', () {
    expect(
      ApiBaseUrl.normalize('abcd-1234.ngrok-free.app'),
      'https://abcd-1234.ngrok-free.app$path',
    );
  });

  test('a pasted https address keeps its host and gets the path', () {
    expect(
      ApiBaseUrl.normalize('  https://abcd.ngrok-free.app/  '),
      'https://abcd.ngrok-free.app$path',
    );
  });

  test('an address with its own path is kept', () {
    expect(
      ApiBaseUrl.normalize('https://api.example.ca/api/v1/'),
      'https://api.example.ca/api/v1',
    );
  });

  test('local and LAN hosts default to http, with the port', () {
    expect(
      ApiBaseUrl.normalize('localhost:8081'),
      'http://localhost:8081$path',
    );
    expect(ApiBaseUrl.normalize('192.168.1.20'), 'http://192.168.1.20$path');
  });

  test('rubbish is refused', () {
    expect(ApiBaseUrl.normalize(''), isNull);
    expect(ApiBaseUrl.normalize('not a url'), isNull);
    expect(ApiBaseUrl.normalize('ftp://x.com'), isNull);
  });
}
