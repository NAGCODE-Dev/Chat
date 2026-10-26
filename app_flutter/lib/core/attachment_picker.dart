import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

const maxAttachmentBytes = 20 * 1024 * 1024;

class PickedAttachment {
  const PickedAttachment({
    required this.name,
    required this.bytes,
    this.mime,
  });

  final String name;
  final Uint8List bytes;
  final String? mime;
}

/// Abre o seletor do sistema e devolve o arquivo em memória.
///
/// O limite de 20 MiB espelha o backend; assim a pessoa recebe o aviso antes
/// de esperar o envio de um arquivo que seria recusado.
Future<PickedAttachment?> pickAttachment({bool imagesOnly = false}) async {
  final file = await FilePicker.pickFile(
    type: imagesOnly ? FileType.image : FileType.any,
  );
  if (file == null) return null;
  final length = await file.length();
  if (length != null && length > maxAttachmentBytes) {
    throw Exception('O arquivo excede o limite de 20 MiB.');
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception('O arquivo está vazio.');
  }
  if (bytes.length > maxAttachmentBytes) {
    throw Exception('O arquivo excede o limite de 20 MiB.');
  }
  return PickedAttachment(
    name: file.name,
    bytes: bytes,
    mime: _guessMime(file.name),
  );
}

String? _guessMime(String filename) {
  final index = filename.lastIndexOf('.');
  if (index <= 0 || index == filename.length - 1) return null;
  return switch (filename.substring(index + 1).toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    'csv' => 'text/csv',
    'json' => 'application/json',
    'xml' => 'application/xml',
    'yaml' || 'yml' => 'application/yaml',
    'html' => 'text/html',
    'css' => 'text/css',
    'js' => 'application/javascript',
    'dart' => 'text/x-dart',
    'py' => 'text/x-python',
    'sh' => 'application/x-sh',
    'zip' => 'application/zip',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'mp4' => 'video/mp4',
    _ => null,
  };
}
