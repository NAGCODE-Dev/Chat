import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackendClient {
  BackendClient(String baseUrl, {this.apiToken})
    : baseUrl = _normalize(baseUrl);

  final String baseUrl;
  final String? apiToken;

  // Wi-Fi e Tailscale podem ter picos de latência. O timeout existe para
  // devolver o controle quando o notebook está realmente fora do ar, sem
  // transformar uma oscilação curta em erro na interface.
  static const _timeout = Duration(seconds: 20);
  static const _voiceTimeout = Duration(seconds: 180);

  static String _normalize(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
    if (apiToken != null && apiToken!.isNotEmpty)
      'authorization': 'Bearer $apiToken',
  };

  Map<String, String> _jsonHeaders([String contentType = 'application/json']) =>
      {..._headers, 'content-type': contentType};

  Future<http.Response> _get(String path, {Duration timeout = _timeout}) =>
      _guard(http.get(_uri(path), headers: _headers), timeout: timeout);

  Future<http.Response> _post(
    String path, {
    Object? body,
    String contentType = 'application/json',
    Duration timeout = _timeout,
  }) => _guard(
    http.post(_uri(path), headers: _jsonHeaders(contentType), body: body),
    timeout: timeout,
  );

  Future<http.Response> _put(String path, {Object? body}) => _guard(
    http.put(_uri(path), headers: _jsonHeaders(), body: body),
    timeout: _timeout,
  );

  Future<http.Response> _patch(String path, {Object? body}) => _guard(
    http.patch(_uri(path), headers: _jsonHeaders(), body: body),
    timeout: _timeout,
  );

  Future<http.Response> _delete(String path) =>
      _guard(http.delete(_uri(path), headers: _headers), timeout: _timeout);

  Future<http.Response> _guard(
    Future<http.Response> request, {
    required Duration timeout,
  }) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw const BackendException(
        'O notebook demorou para responder. Verifique a conexão e tente de novo.',
      );
    } on SocketException {
      throw const BackendException(
        'Não foi possível alcançar o notebook. Verifique se ele está ligado e na mesma rede.',
      );
    } on http.ClientException {
      throw const BackendException(
        'Não foi possível alcançar o notebook. Verifique se ele está ligado e na mesma rede.',
      );
    }
  }

  Future<Map<String, dynamic>> health() async {
    final response = await _get('/health');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> conversations() async {
    final response = await _get('/api/conversations');
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['conversations'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> messages(int conversationId) async {
    final response = await _get('/api/conversations/$conversationId/messages');
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['messages'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> deleteConversation(int conversationId) async {
    _ensureSuccess(await _delete('/api/conversations/$conversationId'));
  }

  Future<List<Map<String, dynamic>>> wishlist() async =>
      _list(await _get('/api/wishlist'), 'items');

  Future<void> addWishlist(Map<String, dynamic> item) async {
    final response = await _post('/api/wishlist', body: jsonEncode(item));
    _ensureSuccess(response);
  }

  Future<void> updateWishlist(int id, Map<String, dynamic> changes) async {
    final response = await _patch(
      '/api/wishlist/$id',
      body: jsonEncode(changes),
    );
    _ensureSuccess(response);
  }

  Future<void> deleteWishlist(int id) async {
    _ensureSuccess(await _delete('/api/wishlist/$id'));
  }

  Future<List<Map<String, dynamic>>> memories() async =>
      _list(await _get('/api/memories'), 'memories');

  Future<Map<String, dynamic>> greeting() async {
    final response = await _get('/api/memories/greeting');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importMemories(String text) async {
    final response = await _post(
      '/api/memories/import',
      body: jsonEncode({'text': text}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> addMemory(Map<String, dynamic> memory) async {
    final response = await _post('/api/memories', body: jsonEncode(memory));
    _ensureSuccess(response);
  }

  Future<void> deleteMemory(int id) async {
    _ensureSuccess(await _delete('/api/memories/$id'));
  }

  Future<Map<String, dynamic>> memoryEmbeddingStatus() async {
    final response = await _get('/api/memories/embeddings/status');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> reindexMemoryEmbeddings() async {
    final response = await _post('/api/memories/embeddings/reindex');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> devices() async =>
      _list(await _get('/api/devices'), 'devices');

  Future<void> addDevice(Map<String, dynamic> device) async {
    final response = await _post('/api/devices', body: jsonEncode(device));
    _ensureSuccess(response);
  }

  Future<void> deleteDevice(int id) async {
    _ensureSuccess(await _delete('/api/devices/$id'));
  }

  Future<String> wakeDevice(int id) async {
    final response = await _post(
      '/api/devices/$id/wake',
      body: jsonEncode({'confirmed': true}),
    );
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['message']
        as String;
  }

  Future<Map<String, dynamic>> settings() async {
    final response = await _get('/api/settings');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> updateModel(String provider, String model) async {
    final response = await _put(
      '/api/settings/model',
      body: jsonEncode({'provider': provider, 'model': model}),
    );
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> models(String provider) async => _list(
    await _get(
      '/api/settings/models?provider=${Uri.encodeQueryComponent(provider)}',
    ),
    'models',
  );

  Future<Map<String, dynamic>> uploadAttachment(
    String filename,
    Uint8List bytes, {
    String? mime,
  }) async {
    final query = <String, String>{'filename': filename};
    if (mime != null && mime.trim().isNotEmpty) {
      query['mime'] = mime.trim();
    }
    final path = Uri(
      path: '/api/attachments',
      queryParameters: query,
    ).toString();
    final response = await _post(
      path,
      body: bytes,
      contentType: mime ?? 'application/octet-stream',
      timeout: const Duration(seconds: 60),
    );
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['attachment']
        as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> attachments() async =>
      _list(await _get('/api/attachments'), 'attachments');

  Future<Map<String, dynamic>> attachment(int id) async {
    final response = await _get('/api/attachments/$id');
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['attachment']
        as Map<String, dynamic>;
  }

  Future<Uint8List> attachmentBytes(int id) async {
    final response = await _get('/api/attachments/$id/content');
    _ensureSuccess(response);
    return response.bodyBytes;
  }

  Future<void> deleteAttachment(int id) async {
    _ensureSuccess(await _delete('/api/attachments/$id'));
  }

  Future<Map<String, dynamic>> ubuntuStatus() async {
    final response = await _get('/api/ubuntu/status');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> ubuntuTasks() async =>
      _list(await _get('/api/ubuntu/tasks'), 'tasks');

  Future<Map<String, dynamic>> runUbuntuTask(String prompt) async {
    final response = await _post(
      '/api/ubuntu/tasks',
      body: jsonEncode({'prompt': prompt, 'confirmed': true}),
      timeout: const Duration(seconds: 300),
    );
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['task']
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> warmupModels() async {
    final response = await _post('/api/models/warmup', body: '{}');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> claimPairing(String code) async {
    final response = await _post(
      '/api/pairing/claim',
      body: jsonEncode({'code': code}),
      timeout: const Duration(seconds: 3),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createPairingSession() async {
    final response = await _post('/api/pairing/sessions', body: '{}');
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pairingStatus() async {
    final response = await _get('/api/pairing/status');
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
    final response = await _post(
      '/api/voice/transcribe',
      contentType: 'audio/wav',
      body: wavAudio,
      timeout: _voiceTimeout,
    );
    _ensureSuccess(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['text']
        as String;
  }

  Future<Uint8List> synthesize(String text) async {
    final response = await _post(
      '/api/voice/synthesize',
      body: jsonEncode({'text': text}),
      timeout: _voiceTimeout,
    );
    _ensureSuccess(response);
    return response.bodyBytes;
  }

  Future<Map<String, bool>> voiceStatus() async {
    final response = await _get('/api/voice/status');
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
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 401) {
      throw const BackendException(
        'Token inválido. Confira o token da API nas configurações.',
      );
    }
    final detail = response.body.trim();
    throw BackendException(
      'O notebook respondeu com erro ${response.statusCode}'
      '${detail.isEmpty ? '.' : ': $detail'}',
    );
  }
}
