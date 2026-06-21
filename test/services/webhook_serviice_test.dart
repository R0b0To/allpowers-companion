import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/services/webhook_service.dart';

// Note: The HTTP calls in WebhookService can be tested with a real mock
// (e.g. using package:http/testing.dart MockClient). For now we test the
// URL-validation fast-paths that return without making a network request.
void main() {
  group('WebhookService', () {
    late WebhookService service;

    setUp(() => service = WebhookService());

    group('fire', () {
      test('returns false for empty URL (no network call)', () async {
        final result = await service.fire('');
        expect(result, false);
      });

      test('returns false for malformed URL', () async {
        final result = await service.fire('not a url');
        expect(result, false);
      });

      test('returns false for URL with no host', () async {
        final result = await service.fire('http://');
        expect(result, false);
      });
    });

    group('test', () {
      test('returns null for empty URL', () async {
        final result = await service.test('');
        expect(result, isNull);
      });

      test('returns null for malformed URL', () async {
        final result = await service.test(':::bad:::');
        expect(result, isNull);
      });
    });
  });
}