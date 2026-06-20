import 'package:http/http.dart' as http;

/// Fires HTTP GET webhooks (e.g. Tapo/Voice Monkey smart-plug triggers).
class WebhookService {
  static const _timeout = Duration(seconds: 5);

  /// Fires a GET request and swallows errors. Used by the automation
  /// engine, where a failed webhook shouldn't interrupt the charging
  /// sequence.
  Future<bool> fire(String url) async {
    if (url.isEmpty) return false;
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Same idea as [fire], but returns the raw status code (or null on
  /// failure) for the "send test" buttons in the UI.
  Future<int?> test(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      return response.statusCode;
    } catch (_) {
      return null;
    }
  }
}