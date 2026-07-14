import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../agent/providers/cisco_provider.dart';
import '../agent/providers/provider_interface.dart';
import '../enums/message_role.dart';
import '../models/chat_message.dart';
import 'provider_staging_probe.dart';

/// A generated fixture keeps the staging proof self-contained: it never reads
/// a customer screenshot, project file, or user attachment. The left half is
/// red and the right half is blue; the expected color is intentionally absent
/// from the request prompt so a successful reply demonstrates pixel handling.
class VisionStagingProbeFixture {
  static const width = 160;
  static const height = 96;
  static const expectedLeftColor = 'RED';

  final Uint8List pngBytes;

  VisionStagingProbeFixture._(this.pngBytes);

  factory VisionStagingProbeFixture.create() =>
      VisionStagingProbeFixture._(_twoColorPng(width: width, height: height));

  String get sha256 => crypto.sha256.convert(pngBytes).toString();

  ProviderImageInput toProviderInput() => ProviderImageInput(
    id: 'staging-vision-two-color-fixture',
    label: 'staging-vision-fixture.png',
    mimeType: 'image/png',
    base64Data: base64Encode(pngBytes),
    byteLength: pngBytes.length,
    width: width,
    height: height,
    estimatedTokens: 96,
  );
}

/// Records only redacted fixture/lifecycle facts; it cannot reveal the model's
/// raw response, the protected endpoint, or any credential.
class VisionStagingProbeResult {
  final ProviderStagingProbeResult lifecycle;
  final String fixtureSha256;
  final int width;
  final int height;

  const VisionStagingProbeResult({
    required this.lifecycle,
    required this.fixtureSha256,
    required this.width,
    required this.height,
  });

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'fixtureSha256': fixtureSha256,
    'fixtureWidth': width,
    'fixtureHeight': height,
    'expectedVisualDetailRecognized': true,
    'providerLifecycle': lifecycle.toJson(),
  };

  String toRedactedJsonLine() => jsonEncode(toJson());
}

/// Executes the real image-capable Cisco adapter against a protected staging
/// deployment. No response text is persisted or printed: it is held only long
/// enough to verify that the model identified the pixel-only left-side color.
class VisionStagingProbe {
  static const _prompt =
      'Inspect the attached image. Reply with the single uppercase English color that fills its left half.';

  final ProviderStagingProbeConfig config;
  final CiscoProvider Function(ProviderStagingProbeConfig config) _provider;
  final VisionStagingProbeFixture Function() _fixture;

  VisionStagingProbe({
    required this.config,
    CiscoProvider Function(ProviderStagingProbeConfig config)? provider,
    VisionStagingProbeFixture Function()? fixture,
  }) : _provider = provider ?? _createProvider,
       _fixture = fixture ?? VisionStagingProbeFixture.create;

  Future<VisionStagingProbeResult> run() async {
    final provider = _provider(config);
    final fixture = _fixture();
    final response = StringBuffer();
    try {
      await connectProviderForStaging(provider, config);
      final lifecycle = await inspectProviderStagingStream(
        provider.chatWithRequest(
          ProviderChatRequest(
            messages: [
              ChatMessage(
                id: 'vision-staging-probe',
                role: MessageRole.user,
                content: _prompt,
                timestamp: DateTime.now().toUtc(),
              ),
            ],
            model: config.model,
            tools: const [],
            temperature: 0,
            maxTokens: 12,
            images: [fixture.toProviderInput()],
          ),
        ),
        expectedProtocolVersion: provider.protocol.version,
        timeout: config.timeout,
        onContent: response.write,
      );
      if (!matchesVisionProbeResponse(response.toString())) {
        throw const ProviderStagingProbeFailure(
          'The staging vision model did not identify the fixture detail from image pixels.',
        );
      }
      return VisionStagingProbeResult(
        lifecycle: lifecycle,
        fixtureSha256: fixture.sha256,
        width: VisionStagingProbeFixture.width,
        height: VisionStagingProbeFixture.height,
      );
    } on ProviderStagingProbeFailure {
      rethrow;
    } catch (_) {
      throw const ProviderStagingProbeFailure(
        'The staging vision probe did not complete a valid image lifecycle.',
      );
    } finally {
      response.clear();
      provider.cancelActiveRequest();
    }
  }

  static CiscoProvider _createProvider(ProviderStagingProbeConfig config) =>
      CiscoProvider(
        accessToken: config.accessToken,
        tokenExpiry: config.accessToken == null
            ? null
            : DateTime.now().add(const Duration(minutes: 5)),
        appKey: config.appKey,
        chatBaseUrl: config.chatBaseUri.toString(),
      );
}

/// Accepts an exact standalone answer or a concise explanatory answer while
/// refusing a response that never names the visual left-side color.
bool matchesVisionProbeResponse(String response) =>
    RegExp(r'\bRED\b', caseSensitive: false).hasMatch(response);

Uint8List _twoColorPng({required int width, required int height}) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // PNG filter: none
    for (var x = 0; x < width; x++) {
      final isLeft = x < width ~/ 2;
      raw.add(<int>[
        if (isLeft) 0xe5 else 0x1e,
        if (isLeft) 0x39 else 0x88,
        if (isLeft) 0x35 else 0xe5,
      ]);
    }
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width, Endian.big)
    ..setUint32(4, height, Endian.big)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // truecolor RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final output = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(_pngChunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_pngChunk('IDAT', ZLibEncoder().convert(raw.takeBytes())))
    ..add(_pngChunk('IEND', const []));
  return output.takeBytes();
}

List<int> _pngChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final length = ByteData(4)..setUint32(0, data.length, Endian.big);
  final crc = ByteData(4)
    ..setUint32(0, _crc32([...typeBytes, ...data]), Endian.big);
  return [
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ (crc.isOdd ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
