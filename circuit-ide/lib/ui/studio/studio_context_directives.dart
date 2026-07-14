import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../models/context_attachment.dart';
import '../../services/screenshot_comparison.dart';
import '../../services/screenshot_context_attachment_builder.dart';

const _directiveUuid = Uuid();

/// The prompt left after request-local Studio context directives are removed.
///
/// The attachment list is deliberately request-local. It is constructed before
/// a turn begins and must not become part of a thread transcript or a global
/// context cache.
class StudioContextDirectiveResult {
  final String message;
  final List<ContextAttachment> attachments;

  const StudioContextDirectiveResult({
    required this.message,
    required this.attachments,
  });
}

Future<StudioContextDirectiveResult> extractStudioContextDirectives(
  String text, {
  required String? rootPath,
}) async {
  final messageLines = <String>[];
  final attachments = <ContextAttachment>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('/')) {
      messageLines.add(rawLine);
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    final command = parts.first.toLowerCase();
    final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    switch (command) {
      case '/image':
      case '/screenshot':
        final attachment = await _buildImageAttachment(rootPath, arg);
        if (attachment != null) attachments.add(attachment);
        break;
      case '/compare':
        attachments.addAll(
          await _buildScreenshotComparisonAttachments(rootPath, arg),
        );
        break;
      default:
        messageLines.add(rawLine);
    }
  }
  return StudioContextDirectiveResult(
    message: messageLines.join('\n').trim(),
    attachments: attachments,
  );
}

Future<ContextAttachment?> _buildImageAttachment(
  String? rootPath,
  String rawPath,
) async {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) {
    return ContextAttachment(
      id: _directiveUuid.v4(),
      type: ContextAttachmentType.image,
      label: 'Missing image path',
      content:
          'The /image command needs a PNG, JPG, GIF, or WebP path. Example: /image screenshots/home.png',
      resolutionStatus: ContextAttachmentResolutionStatus.missing,
      estimatedTokens: 24,
      metadata: const {
        'artifactRole': 'visual_evidence',
        'visionInputStatus': 'missing_path',
      },
      createdAt: DateTime.now(),
    );
  }
  final imagePath = _resolvePath(rootPath, trimmed);
  return const ScreenshotContextAttachmentBuilder().build(imagePath);
}

Future<List<ContextAttachment>> _buildScreenshotComparisonAttachments(
  String? rootPath,
  String raw,
) async {
  final directive = ScreenshotComparisonDirective.tryParse(raw);
  if (directive == null) {
    return [
      ContextAttachment(
        id: _directiveUuid.v4(),
        type: ContextAttachmentType.note,
        label: 'Invalid screenshot comparison',
        content:
            'Use /compare reference.png | current.png. Optional region findings use `| current: description @ 0.10,0.20,0.30,0.15`.',
        resolutionStatus: ContextAttachmentResolutionStatus.missing,
        estimatedTokens: 32,
        metadata: const {
          'artifactRole': 'visual_comparison',
          'comparisonStatus': 'invalid_directive',
        },
        createdAt: DateTime.now(),
      ),
    ];
  }
  final comparison = await const ScreenshotComparisonAttachmentBuilder().build(
    referencePath: _resolvePath(rootPath, directive.referencePath),
    currentPath: _resolvePath(rootPath, directive.currentPath),
    findings: directive.findings,
  );
  return comparison.attachments;
}

String _resolvePath(String? rootPath, String value) {
  if (p.isAbsolute(value)) return p.normalize(value);
  return rootPath == null
      ? p.normalize(value)
      : p.normalize(p.join(rootPath, value));
}

Future<List<ContextAttachment>> debugStudioImageDirectiveAttachments(
  String text, {
  String? rootPath,
}) async {
  final result = await extractStudioContextDirectives(text, rootPath: rootPath);
  return result.attachments;
}

Future<String> debugStudioImageDirectiveMessage(
  String text, {
  String? rootPath,
}) async {
  final result = await extractStudioContextDirectives(text, rootPath: rootPath);
  return result.message;
}
