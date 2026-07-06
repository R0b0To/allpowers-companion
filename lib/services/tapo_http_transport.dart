import 'dart:io';
import 'dart:typed_data';

/// Successful POST response. Any failure — network error, timeout, or a
/// non-200 status — is raised as an exception instead of being represented
/// here, mirroring the original inline `_post` implementation this
/// replaces: callers only ever see a [TapoHttpResponse] on success.
final class TapoHttpResponse {
  const TapoHttpResponse({required this.body, this.setCookie});
  final Uint8List body;
  final String? setCookie;
}

/// Abstraction over the HTTP transport used to talk to a Tapo plug's local
/// KLAP endpoint (`http://<ip>/app/<path>`).
///
/// Extracted from `_TapoSession` so tests can substitute a fake "device"
/// that speaks the real KLAP protocol (via [KlapCrypto]) without opening a
/// real socket — see `test/services/tapo_service_test.dart`.
abstract interface class TapoHttpTransport {
  Future<TapoHttpResponse> post(
    String ip,
    String path,
    Uint8List body, {
    Map<String, String>? queryParams,
    String? cookie,
  });
}

/// Production implementation backed by `dart:io`'s [HttpClient].
final class HttpClientTapoTransport implements TapoHttpTransport {
  HttpClientTapoTransport([HttpClient? client])
      : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<TapoHttpResponse> post(
    String ip,
    String path,
    Uint8List body, {
    Map<String, String>? queryParams,
    String? cookie,
  }) async {
    var url = 'http://$ip/app/$path';
    if (queryParams != null && queryParams.isNotEmpty) {
      url += '?${Uri(queryParameters: queryParams).query}';
    }
    final uri = Uri.parse(url);

    final request =
        await _client.postUrl(uri).timeout(const Duration(seconds: 6));

    request.headers
      ..add('Host', uri.host, preserveHeaderCase: true)
      ..add('User-Agent', 'python-requests/2.28.1', preserveHeaderCase: true)
      ..add('Accept', '*/*', preserveHeaderCase: true)
      ..add('Accept-Encoding', 'gzip, deflate', preserveHeaderCase: true)
      ..add('Connection', 'keep-alive', preserveHeaderCase: true)
      ..add('Content-Length', body.length.toString(),
          preserveHeaderCase: true);

    if (cookie != null) {
      request.headers.add('Cookie', cookie, preserveHeaderCase: true);
    }

    request.add(body);
    final response = await request.close();

    if (response.statusCode != 200) {
      await response.drain<List<int>>().timeout(const Duration(seconds: 4));
      throw HttpException(
        'HTTP ${response.statusCode} ${response.reasonPhrase}',
        uri: uri,
      );
    }

    final responseBytes =
        await _readResponse(response).timeout(const Duration(seconds: 8));

    return TapoHttpResponse(
      body: responseBytes,
      setCookie: response.headers.value('set-cookie'),
    );
  }

  Future<Uint8List> _readResponse(HttpClientResponse response) async {
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Closes the underlying [HttpClient]. Only meaningful for this real
  /// implementation — fakes used in tests have nothing to close.
  void close({bool force = false}) => _client.close(force: force);
}