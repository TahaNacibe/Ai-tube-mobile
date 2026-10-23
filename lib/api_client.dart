import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient(this.baseUrl);

  String baseUrl;

  Uri _uri(String path) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const FormatException('Enter your server address.');
    }
    final root = Uri.tryParse(normalized);
    if (root == null ||
        !root.hasScheme ||
        !const {'http', 'https'}.contains(root.scheme) ||
        root.host.isEmpty ||
        root.path != '' && root.path != '/') {
      throw const FormatException(
        'Use a server address such as http://192.168.1.20:8000.',
      );
    }
    return root.replace(path: path);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await http
        .get(_uri(path))
        .timeout(const Duration(seconds: 10));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(
          _uri(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _decodeResponse(response);
  }

  Future<void> checkConnection() async {
    final health = await getJson('/api/health');
    if (health['ok'] != true) {
      throw Exception('The server did not report a healthy status.');
    }
  }

  Stream<Map<String, dynamic>> streamChat({
    required List<Map<String, String>> messages,
    required bool webSearch,
    required bool imageSearch,
    required List<String> memoryContext,
    required List<String> knowledgePoolData,
    required http.Client client,
  }) async* {
    final request = http.Request('POST', _uri('/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'messages': messages,
        'web_search': webSearch,
        'image_search': imageSearch,
        'memory_context': memoryContext,
        'knowledge_pool_data': knowledgePoolData,
      });
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw Exception(_errorMessage(body, response.statusCode));
    }

    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final separator = buffer.indexOf('\n\n');
        final crlfSeparator = buffer.indexOf('\r\n\r\n');
        final index = separator < 0
            ? crlfSeparator
            : crlfSeparator < 0
            ? separator
            : separator < crlfSeparator
            ? separator
            : crlfSeparator;
        if (index < 0) break;
        final separatorLength = index == crlfSeparator ? 4 : 2;
        final event = buffer.substring(0, index);
        buffer = buffer.substring(index + separatorLength);
        final data = event
            .split(RegExp(r'\r?\n'))
            .where((line) => line.startsWith('data:'))
            .map((line) => line.substring(5).trimLeft())
            .join('\n');
        if (data.isNotEmpty) yield _decodeJson(data);
      }
    }
    final remaining = buffer
        .split(RegExp(r'\r?\n'))
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trimLeft())
        .join('\n');
    if (remaining.isNotEmpty) yield _decodeJson(remaining);
  }
}

Map<String, dynamic> _decodeResponse(http.Response response) {
  final payload = _decodeJson(response.body);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(_errorMessage(response.body, response.statusCode, payload));
  }
  return payload;
}

Map<String, dynamic> _decodeJson(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    return {'message': body};
  }
  return {'message': body};
}

String _errorMessage(
  String body,
  int statusCode, [
  Map<String, dynamic>? payload,
]) {
  final detail = payload?['error'] ?? payload?['message'];
  final cleanBody = body
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return (detail is String && detail.isNotEmpty)
      ? detail
      : cleanBody.isNotEmpty
      ? cleanBody
      : 'Request failed ($statusCode).';
}
