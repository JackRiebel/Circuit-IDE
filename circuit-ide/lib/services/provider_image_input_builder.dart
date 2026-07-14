import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../agent/providers/provider_interface.dart';
import '../models/context_attachment.dart';

class ProviderImageInputBuildResult {
  final List<ProviderImageInput> images;
  final List<String> errors;

  const ProviderImageInputBuildResult({
    this.images = const [],
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
}

/// Reads only validated image attachments into request-local provider payloads.
/// The source path and raw pixels never enter persisted Studio prompt/history.
class ProviderImageInputBuilder {
  const ProviderImageInputBuilder();

  /// A synchronous preflight check for persisted OCR provenance. [build]
  /// performs the authoritative source-file hash comparison immediately before
  /// dispatch, because an attachment can outlive a changed image on disk.
  static bool hasHashBoundOcrProvenance(ContextAttachment attachment) {
    if (attachment.metadata['hasOcrFallback'] != true) return false;
    final text = attachment.metadata['ocrText']?.toString().trim() ?? '';
    final sourceHash =
        attachment.metadata['ocrSourceImageSha256']?.toString().trim() ?? '';
    return text.isNotEmpty && RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHash);
  }

  Future<ProviderImageInputBuildResult> build({
    required List<ContextAttachment> attachments,
    required ProviderCapabilities capabilities,
  }) async {
    final imageAttachments = attachments
        .where((attachment) => attachment.type == ContextAttachmentType.image)
        .toList(growable: false);
    if (imageAttachments.isEmpty) {
      return const ProviderImageInputBuildResult();
    }
    if (!capabilities.supportsImageInput) {
      final unhandled = <ContextAttachment>[];
      final errors = <String>[];
      for (final attachment in imageAttachments) {
        if (attachment.metadata['hasOcrFallback'] != true) {
          unhandled.add(attachment);
          continue;
        }
        final error = await _validateOcrFallback(attachment);
        if (error != null) errors.add('${attachment.label}: $error');
      }
      if (errors.isNotEmpty) {
        return ProviderImageInputBuildResult(errors: errors);
      }
      if (unhandled.isEmpty) {
        // OCR text is already part of the attachment prompt block. Do not send
        // pixels to a model that has not advertised vision support. Every OCR
        // fallback was hash-validated against the current source file above.
        return const ProviderImageInputBuildResult();
      }
      return const ProviderImageInputBuildResult(
        errors: [
          'The selected model does not accept image input. Remove the screenshot, add a verified OCR fallback, or choose a vision-capable model.',
        ],
      );
    }

    final images = <ProviderImageInput>[];
    final errors = <String>[];
    for (final attachment in imageAttachments) {
      final path = attachment.path;
      final mimeType = attachment.metadata['mimeType'] as String?;
      if (path == null || path.trim().isEmpty) {
        errors.add('${attachment.label}: image source is unavailable.');
        continue;
      }
      if (mimeType == null ||
          !capabilities.supportedImageMimeTypes.contains(mimeType)) {
        errors.add(
          '${attachment.label}: ${mimeType ?? 'unknown format'} is not supported by the selected model.',
        );
        continue;
      }
      final file = File(path);
      if (!await file.exists()) {
        errors.add('${attachment.label}: image file is missing.');
        continue;
      }
      final length = await file.length();
      if (capabilities.maxImageBytes <= 0) {
        final limit = capabilities.maxImageBytes <= 0
            ? 'the model does not declare an image size limit'
            : 'the ${_formatBytes(capabilities.maxImageBytes)} image limit';
        errors.add('${attachment.label}: image exceeds $limit.');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length != length) {
        errors.add(
          '${attachment.label}: image changed while it was being read.',
        );
        continue;
      }
      final ocrError = await _validateOcrFallback(
        attachment,
        sourceBytes: bytes,
      );
      if (ocrError != null) {
        errors.add('${attachment.label}: $ocrError');
        continue;
      }
      final prepared = await _prepareImage(
        bytes,
        sourceMimeType: mimeType,
        maxImageBytes: capabilities.maxImageBytes,
        maxImageDimension: capabilities.maxImageDimension,
      );
      if (prepared == null) {
        errors.add(
          '${attachment.label}: image data could not be decoded for the selected model.',
        );
        continue;
      }
      if (prepared.bytes.length > capabilities.maxImageBytes) {
        errors.add(
          '${attachment.label}: image still exceeds the ${_formatBytes(capabilities.maxImageBytes)} image limit after resizing.',
        );
        continue;
      }
      images.add(
        ProviderImageInput(
          id: attachment.id,
          label: attachment.label,
          mimeType: prepared.mimeType,
          base64Data: base64Encode(prepared.bytes),
          byteLength: prepared.bytes.length,
          width: prepared.width,
          height: prepared.height,
          estimatedTokens: _estimateImageTokens(
            prepared.width,
            prepared.height,
            prepared.bytes.length,
          ),
          wasResized: prepared.wasResized,
        ),
      );
    }
    return ProviderImageInputBuildResult(images: images, errors: errors);
  }

  Future<String?> _validateOcrFallback(
    ContextAttachment attachment, {
    Uint8List? sourceBytes,
  }) async {
    if (attachment.metadata['hasOcrFallback'] != true) return null;
    if (!hasHashBoundOcrProvenance(attachment)) {
      return 'OCR fallback is missing hash-bound text provenance. Remove and reattach the image to extract OCR again.';
    }
    final path = attachment.path?.trim() ?? '';
    if (path.isEmpty) {
      return 'OCR fallback source image is unavailable for hash verification. Remove and reattach the image.';
    }
    Uint8List bytes;
    if (sourceBytes != null) {
      bytes = sourceBytes;
    } else {
      final file = File(path);
      if (!await file.exists()) {
        return 'OCR fallback source image is missing. Remove and reattach the image.';
      }
      try {
        bytes = await file.readAsBytes();
      } on FileSystemException {
        return 'OCR fallback source image could not be read. Remove and reattach the image.';
      }
    }
    final expected =
        attachment.metadata['ocrSourceImageSha256']?.toString().trim() ?? '';
    if (sha256.convert(bytes).toString() != expected) {
      return 'OCR fallback no longer matches the attached image. Remove and reattach the image to refresh OCR.';
    }
    return null;
  }

  int _estimateImageTokens(int? width, int? height, int byteLength) {
    if (width != null && height != null && width > 0 && height > 0) {
      // Deliberately conservative estimate for budget display. Provider usage
      // events remain the source of truth after a request completes.
      return ((width * height) / 750).ceil().clamp(85, 4096);
    }
    return (byteLength / 900).ceil().clamp(85, 4096);
  }

  Future<_PreparedImage?> _prepareImage(
    Uint8List source, {
    required String sourceMimeType,
    required int maxImageBytes,
    required int maxImageDimension,
  }) async {
    ui.Codec? sourceCodec;
    ui.Image? sourceImage;
    try {
      sourceCodec = await ui.instantiateImageCodec(source);
      final frame = await sourceCodec.getNextFrame();
      sourceImage = frame.image;
      final sourceWidth = sourceImage.width;
      final sourceHeight = sourceImage.height;
      final largestDimension = sourceWidth > sourceHeight
          ? sourceWidth
          : sourceHeight;
      final needsResize =
          source.length > maxImageBytes ||
          (maxImageDimension > 0 && largestDimension > maxImageDimension);
      if (!needsResize) {
        return _PreparedImage(
          bytes: source,
          mimeType: sourceMimeType,
          width: sourceWidth,
          height: sourceHeight,
        );
      }

      final constrainedDimension = maxImageDimension > 0
          ? maxImageDimension
          : largestDimension;
      var scale = (constrainedDimension / largestDimension).clamp(0.01, 1.0);
      _PreparedImage? latestResize;
      for (var attempt = 0; attempt < 5; attempt++) {
        final targetWidth = (sourceWidth * scale).round().clamp(1, sourceWidth);
        final targetHeight = (sourceHeight * scale).round().clamp(
          1,
          sourceHeight,
        );
        final resized = await _encodeResizedPng(
          source,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        if (resized == null) return null;
        latestResize = resized;
        if (resized.bytes.length <= maxImageBytes) return resized;
        final byteScale = (maxImageBytes / resized.bytes.length).clamp(
          0.15,
          0.85,
        );
        scale *= byteScale;
      }
      return latestResize;
    } catch (_) {
      return null;
    } finally {
      sourceImage?.dispose();
      sourceCodec?.dispose();
    }
  }

  Future<_PreparedImage?> _encodeResizedPng(
    Uint8List source, {
    required int targetWidth,
    required int targetHeight,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        source,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      return _PreparedImage(
        bytes: bytes.buffer.asUint8List(),
        mimeType: 'image/png',
        width: image.width,
        height: image.height,
        wasResized: true,
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PreparedImage {
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final bool wasResized;

  const _PreparedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    this.wasResized = false,
  });
}
