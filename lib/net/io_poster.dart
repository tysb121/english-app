import 'dart:convert';
import 'dart:io';

import '../engine/api_requests.dart';
import 'poster.dart';

class IoPoster implements Poster {
  @override
  Future<Posted> send(ApiCall call) async {
    if (call.uri.scheme != 'https') return const Posted(0, 'https');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      final request = await client
          .postUrl(call.uri)
          .timeout(const Duration(seconds: 60));
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      final authorization = call.headers['Authorization'];
      if (authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      request.add(utf8.encode(jsonEncode(call.body)));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 60));
      return Posted(response.statusCode, body);
    } on Exception {
      return const Posted(0, 'network');
    } finally {
      client.close(force: true);
    }
  }
}
