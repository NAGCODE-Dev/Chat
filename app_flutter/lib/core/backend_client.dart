import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class BackendClient {
  BackendClient(String baseUrl, {this.apiToken})
    : baseUrl = _normalize(baseUrl);

  final String baseUrl;
  final String? apiToken;

  static String _normalize(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
    if (apiToken != null && apiToken!.isNotEmpty)
      'authorization': 'Bearer $apiToken',
  };

  Map<String, String> _jsonHeaders([String contentType = 'application/json']) =>
      {..._headers, 'content-type': contentType};

  Future<List<Map<String, dynamic>>> conversations() async {
    final response = await http.get(
      _uri('/api/conversations'),
      headers: _headers,
    );
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['conversations'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> messages(int conversationId) async {
    final response = await http.get(
      _uri('/api/conversations/$conversationId/messages'),
      headers: _headers,
    );
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['messages'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> deleteConversation(int conversationId) async {
    _ensureSuccess(
      await http.delete(
        _uri('/api/conversations/$conversationId'),
        headers: _headers,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> wishlist() async =>
      _list(await http.get(_uri('/api/wishlist'), headers: _headers), 'items');

  Future<void> addWishlist(Map<String, dynamic> item) async {
    final response = await http.post(
      _uri('/api/wishlist'),
      headers: _jsonHeaders(),
      body: jsonEncode(item),
    );
    _ensureSuccess(response);
  }

  Future<void> updateWishlist(int id, Map<String, dynamic> changes) async {
    final response = await http.patch(
      _uri('/api/wishlist/$id'),
      headers: _jsonHeaders(),
      body: jsonEncode(changes),
    );
    _ensureSuccess(response);
  }

  Future<void> deleteWishlist(int id) async {
    _ensureSuccess(
      await http.delete(_uri('/api/wishlist/$id'), headers: _headers),
    );
  }

  Future<List<Map<String, dynamic>>> memories() async => _list(
    await http.get(_uri('/api/memories'), headers: _headers),
    'memories',
  );

  Future<Map<String, dynamic>> greeting() async {
    final response = await http.get(
      _uri('/api/memories/greeting'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importMemories(String text) async {
    final response = await http.post(
      _uri('/api/memories/import'),
      headers: _jsonHeaders(),
      body: jsonEncode({'text': text}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> addMemory(Map<String, dynamic> memory) async {
    final response = await http.post(
      _uri('/api/memories'),
      headers: _jsonHeaders(),
      body: jsonEncode(memory),
    );
    _ensureSuccess(response);
  }

  Future<void> deleteMemory(int id) async {
    _ensureSuccess(
      await http.delete(_uri('/api/memories/$id'), headers: _headers),
    );
  }

  Future<Map<String, dynamic>> memoryEmbeddingStatus() async {
    final response = await http.get(
      _uri('/api/memories/embeddings/status'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reindexMemoryEmbeddings() async {
    final response = await http.post(
      _uri('/api/memories/embeddings/reindex'),
      headers: _headers,
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> devices() async =>
      _list(await http.get(_uri('/api/devices'), headers: _headers), 'devices');

  Future<void> addDevice(Map<String, dynamic> device) async {
    final response = await http.post(
      _uri('/api/devices'),
      headers: _jsonHeaders(),
      body: jsonEncode(device),
    );
    _ensureSuccess(response);
  }

  Future<void> deleteDevice(int id) async {
    _ensureSuccess(
      await http.delete(_uri('/api/devices/$id'), headers: _headers),
    );
  }

  Future<String> wakeDevice(int id) async {
    final response = await http.post(
      _uri('/api/devices/$id/wake'),
      headers: _jsonHeaders(),
      body: jsonEncode({'confirmed': true}),
    );
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['message']
        as String;
  }

  Future<Map<String, dynamic>> settings() async {
    final response = await http.get(_uri('/api/settings'), headers: _headers);
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> updateModel(String provider, String model) async {
    final response = await http.put(
      _uri('/api/settings/model'),
      headers: _jsonHeaders(),
      body: jsonEncode({'provider': provider, 'model': model}),
    );
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> models(String provider) async => _list(
    await http.get(
      _uri('/api/settings/models')
          .replace(queryParameters: {'provider': provider}),
      headers: _headers,
    ),
    'models',
  );

  Future<Map<String, dynamic>> warmupModels() async {
    final response = await http.post(
      _uri('/api/models/warmup'),
      headers: _jsonHeaders(),
      body: '{}',
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> claimPairing(String code) async {
    final response = await http
        .post(
          _uri('/api/pairing/claim'),
          headers: _jsonHeaders(),
          body: jsonEncode({'code': code}),
        )
        .timeout(const Duration(seconds: 3));
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _list(
    http.Response response,
    String key,
  ) async {
    _ensureSuccess(response);
    return ((jsonDecode(response.body) as Map<String, dynamic>)[key]
            as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<String> transcribe(Uint8List wavAudio) async {
    final response = await http.post(
      _uri('/api/voice/transcribe'),
      headers: _jsonHeaders('audio/wav'),
      body: wavAudio,
    );
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['text']
        as String;
  }

  Future<Uint8List> synthesize(String text) async {
    final response = await http.post(
      _uri('/api/voice/synthesize'),
      headers: _jsonHeaders(),
      body: jsonEncode({'text': text}),
    );
    _ensureSuccess(response);
    return response.bodyBytes;
  }

  Future<Map<String, bool>> voiceStatus() async {
    final response = await http.get(
      _uri('/api/voice/status'),
      headers: _headers,
    );
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'stt_available': body['stt_available'] as bool? ?? false,
      'tts_available': body['tts_available'] as bool? ?? false,
    };
  }

  WebSocketChannel connectChat() {
    final uri = Uri.parse(baseUrl).replace(
      scheme: Uri.parse(baseUrl).scheme == 'https' ? 'wss' : 'ws',
      path:
          '${Uri.parse(baseUrl).path.replaceFirst(RegExp(r'/+$'), '')}/api/ws/chat',
    );
    return IOWebSocketChannel.connect(uri, headers: _headers);
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backend respondeu HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }
}
