import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/context_attachment.dart';

class ScreenshotContextAttachmentBuilder {
  const ScreenshotContextAttachmentBuilder();

  static const supportedExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp'};

  bool isSupportedImagePath(String path) {
    return supportedExtensions.contains(p.extension(path).toLowerCase());
  }

  Future<ContextAttachment?> build(String path) async {
    if (!isSupportedImagePath(path)) return null;
    final file = File(path);
    if (!await file.exists()) {
      return ContextAttachment(
        id: 'image:${p.normalize(path)}',
        type: ContextAttachmentType.image,
        label: p.basename(path),
        path: path,
        content:
            'Image attachment could not be read because the file is missing.',
        resolutionStatus: ContextAttachmentResolutionStatus.missing,
        estimatedTokens: 18,
        createdAt: DateTime.now(),
      );
    }

    final bytes = await file.readAsBytes();
    final dimensions = _dimensionsFor(bytes);
    final extension = p.extension(path).replaceFirst('.', '').toUpperCase();
    final mimeType = _mimeTypeForExtension(p.extension(path));
    final facts = [
      'Image attachment for visual-evidence review.',
      'File: ${p.basename(path)}',
      'Format: ${extension.isEmpty ? 'Unknown' : extension}',
      'Size: ${_formatBytes(bytes.length)}',
      if (dimensions != null)
        'Dimensions: ${dimensions.width} x ${dimensions.height}px'
      else
        'Dimensions: not detected',
      'Visual evidence status: screenshot/image file is attached as context metadata.',
      'OCR status: not extracted locally.',
      'Vision model status: not sent as pixel input by the current Circuit connector.',
      'Visual analysis contract: do not claim to inspect pixels, read text, identify UI details, or infer layout from this image unless the user described those details in text.',
      'Safe use: cite the screenshot as provided evidence, ask for a description or OCR/vision integration when pixel-level review is required, and preserve file metadata in any handoff artifact.',
      'Recommended artifact role: visual evidence appendix for UX reviews, bug reports, implementation plans, and customer handoff packages.',
    ];

    return ContextAttachment(
      id: 'image:${p.normalize(path)}',
      type: ContextAttachmentType.image,
      label: p.basename(path),
      path: path,
      content: facts.join('\n'),
      resolutionStatus: ContextAttachmentResolutionStatus.resolved,
      estimatedTokens: 48,
      metadata: {
        'artifactRole': 'visual_evidence',
        'format': extension.isEmpty ? 'unknown' : extension,
        'mimeType': mimeType,
        'byteSize': bytes.length,
        if (dimensions != null) 'width': dimensions.width,
        if (dimensions != null) 'height': dimensions.height,
        'ocrStatus': 'not_extracted',
        'visionInputStatus': 'metadata_only',
        'providerPixelInputSupported': false,
        'analysisReliability': 'metadata_only',
        'visualAnalysisContract':
            'Do not infer screenshot contents from pixels; use metadata and user-provided description only.',
        'recommendedArtifactRole': 'visual_evidence_appendix',
        'recommendedFollowUp':
            'Ask for OCR/vision integration or a user description before making pixel-level claims.',
        'handoffUse':
            'Attach as visual evidence metadata; request OCR/vision integration before relying on unseen pixels.',
      },
      createdAt: DateTime.now(),
    );
  }

  _ImageDimensions? _dimensionsFor(Uint8List bytes) {
    return _pngDimensions(bytes) ??
        _jpegDimensions(bytes) ??
        _gifDimensions(bytes);
  }

  _ImageDimensions? _pngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    final data = ByteData.sublistView(bytes);
    return _ImageDimensions(data.getUint32(16), data.getUint32(20));
  }

  _ImageDimensions? _gifDimensions(Uint8List bytes) {
    if (bytes.length < 10) return null;
    final header = String.fromCharCodes(bytes.take(6));
    if (header != 'GIF87a' && header != 'GIF89a') return null;
    final data = ByteData.sublistView(bytes);
    return _ImageDimensions(
      data.getUint16(6, Endian.little),
      data.getUint16(8, Endian.little),
    );
  }

  _ImageDimensions? _jpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    var offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xff) return null;
      final marker = bytes[offset + 1];
      offset += 2;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (marker == 0xd9 || marker == 0xda) return null;
      if (offset + 2 > bytes.length) return null;
      final segmentLength = (bytes[offset] << 8) + bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        return null;
      }
      final isStartOfFrame =
          marker >= 0xc0 &&
          marker <= 0xcf &&
          marker != 0xc4 &&
          marker != 0xc8 &&
          marker != 0xcc;
      if (isStartOfFrame && segmentLength >= 7) {
        final height = (bytes[offset + 3] << 8) + bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) + bytes[offset + 6];
        return _ImageDimensions(width, height);
      }
      offset += segmentLength;
    }
    return null;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  String _mimeTypeForExtension(String extension) {
    return switch (extension.toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}

class _ImageDimensions {
  final int width;
  final int height;

  const _ImageDimensions(this.width, this.height);
}
