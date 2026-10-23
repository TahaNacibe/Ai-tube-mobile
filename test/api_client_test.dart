import 'dart:convert';

import 'package:ai_tube_mobile/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rejects an invalid server address', () {
    final api = ApiClient('localhost:8000');
    expect(() => api.getJson('/api/health'), throwsFormatException);
  });

  test('decodes server-sent chat events', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/chat');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['memory_context'], ['User persona']);
      expect(payload['knowledge_pool_data'], ['Reference']);
      return http.Response.bytes(
        utf8.encode('data: {"token":"Hello"}\n\ndata: {"done":true}\n\n'),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final events = await ApiClient('http://192.168.1.20:8000')
        .streamChat(
          messages: const [
            {'role': 'user', 'content': 'Hi'},
          ],
          webSearch: true,
          imageSearch: false,
          memoryContext: const ['User persona'],
          knowledgePoolData: const ['Reference'],
          client: client,
        )
        .toList();
    client.close();

    expect(events, [
      {'token': 'Hello'},
      {'done': true},
    ]);
  });
}
