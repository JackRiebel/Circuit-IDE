import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class OcrTextBlock {
  final String text;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;

  const OcrTextBlock({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  bool get hasValidRegion =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1 &&
      y + height <= 1;

  Map<String, Object> toJson() => {
    'text': text,
    'confidence': confidence,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static OcrTextBlock? fromJson(Map<Object?, Object?> value) {
    final text = value['text']?.toString().trim() ?? '';
    final confidence = _double(value['confidence']);
    final x = _double(value['x']);
    final y = _double(value['y']);
    final width = _double(value['width']);
    final height = _double(value['height']);
    if (text.isEmpty ||
        confidence == null ||
        x == null ||
        y == null ||
        width == null ||
        height == null) {
      return null;
    }
    final block = OcrTextBlock(
      text: text,
      confidence: confidence.clamp(0, 1).toDouble(),
      x: x,
      y: y,
      width: width,
      height: height,
    );
    return block.hasValidRegion ? block : null;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class OcrExtraction {
  final String engine;
  final String sourceImageSha256;
  final List<OcrTextBlock> blocks;

  const OcrExtraction({
    required this.engine,
    required this.sourceImageSha256,
    required this.blocks,
  });

  String get text => blocks.map((block) => block.text).join('\n');

  double get averageConfidence => blocks.isEmpty
      ? 0
      : blocks.fold<double>(0, (sum, block) => sum + block.confidence) /
            blocks.length;

  Map<String, Object> toMetadata() => {
    'ocrEngine': engine,
    'ocrSourceImageSha256': sourceImageSha256,
    'ocrText': text,
    'ocrAverageConfidence': averageConfidence,
    'ocrBlocks': blocks.map((block) => block.toJson()).toList(growable: false),
    'ocrBoundingBoxCount': blocks.length,
    'hasOcrFallback': true,
  };
}

/// Local, on-device OCR first; a structured, hash-bound sidecar is supported
/// for approved offline/enterprise extractors. Plain text sidecars remain
/// descriptive context but are intentionally not treated as OCR fallback.
class LocalOcrService {
  static const _channel = MethodChannel('circuitcode/local_ocr');

  const LocalOcrService();

  Future<OcrExtraction?> extract({
    required String imagePath,
    required Uint8List imageBytes,
  }) async {
    final hash = sha256.convert(imageBytes).toString();
    final sidecar = await _structuredSidecar(imagePath, hash);
    if (sidecar != null) return sidecar;
    if (!Platform.isMacOS) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('recognizeText', {
        'path': imagePath,
      });
      return _fromPlatformResponse(raw, sourceImageSha256: hash);
    } catch (_) {
      // Local OCR is an optional transparent fallback. Missing platform
      // channels, test bindings, unreadable input, and Vision failures must
      // leave the image as metadata-only context rather than failing a turn.
      return null;
    }
  }

  Future<OcrExtraction?> _structuredSidecar(
    String imagePath,
    String hash,
  ) async {
    final candidates = [
      '$imagePath.ocr.json',
      '${p.withoutExtension(imagePath)}.ocr.json',
    ];
    final seen = <String>{};
    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (!seen.add(normalized)) continue;
      final file = File(normalized);
      if (!await file.exists()) continue;
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is! Map) continue;
        final sourceHash = raw['sourceImageSha256']?.toString().trim() ?? '';
        if (sourceHash.isEmpty || sourceHash != hash) continue;
        final blocks = _blocks(raw['blocks']);
        if (blocks.isEmpty) continue;
        return OcrExtraction(
          engine: raw['engine']?.toString().trim().isNotEmpty == true
              ? raw['engine'].toString().trim()
              : 'approved_sidecar',
          sourceImageSha256: hash,
          blocks: blocks,
        );
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  OcrExtraction? _fromPlatformResponse(
    Object? raw, {
    required String sourceImageSha256,
  }) {
    if (raw is! Map) return null;
    final blocks = _blocks(raw['blocks']);
    if (blocks.isEmpty) return null;
    final engine = raw['engine']?.toString().trim();
    return OcrExtraction(
      engine: engine == null || engine.isEmpty ? 'macos_vision' : engine,
      sourceImageSha256: sourceImageSha256,
      blocks: blocks,
    );
  }

  List<OcrTextBlock> _blocks(Object? raw) {
    if (raw is! Iterable) return const [];
    return raw
        .whereType<Map>()
        .map((item) => OcrTextBlock.fromJson(item))
        .whereType<OcrTextBlock>()
        .toList(growable: false);
  }
}
