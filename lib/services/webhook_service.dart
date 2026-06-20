import 'package:http/http.dart' as http;

import '../utils/logger.dart';

/// Fires HTTP GET webhooks (e.g. Tapo / Voice Monkey smart-plug triggers).
///
/// Both methods swallow all errors so a failed webhook never interrupts the
/// automation sequence. The difference is what they return:
/// - [fire] returns a simple bool (used by the engine where only success/fail matters).
/// - [test] returns the raw status code or null (used by test buttons in the UI).
final class WebhookService {
  static const _timeout = Duration(seconds: 8);

  /// Fires a GET request and returns true on HTTP 200.
  /// Errors and non-200 responses both return false.
  Future<bool> fire(String url) async {
    if (url.isEmpty) return false;

    final uri = _parseUri(url);
    if (uri == null) {
      Log.w('WebhookService', 'Invalid URL: $url');
      return false;
    }

    try {
      final response = await http.get(uri).timeout(_timeout);
      final success = response.statusCode == 200;
      Log.d('WebhookService', 'fire → ${response.statusCode} ($url)');
      return success;
    } catch (e) {
      Log.e('WebhookService', 'fire failed ($url)', e);
      return false;
    }
  }

  /// Fires a GET request and returns the HTTP status code, or null on error.
  /// Used by "test" buttons in the UI to give the user precise feedback.
  Future<int?> test(String url) async {
    if (url.isEmpty) return null;

    final uri = _parseUri(url);
    if (uri == null) {
      Log.w('WebhookService', 'Invalid URL for test: $url');
      return null;
    }

    try {
      final response = await http.get(uri).timeout(_timeout);
      Log.d('WebhookService', 'test → ${response.statusCode} ($url)');
      return response.statusCode;
    } catch (e) {
      Log.e('WebhookService', 'test failed ($url)', e);
      return null;
    }
  }

  /// Parses and validates the URL, returning null if it is malformed.
  Uri? _parseUri(String url) {
    try {
      final uri = Uri.parse(url.trim());
      if (!uri.hasScheme || !uri.hasAuthority) return null;
      return uri;
    } catch (_) {
      return null;
    }
  }
}