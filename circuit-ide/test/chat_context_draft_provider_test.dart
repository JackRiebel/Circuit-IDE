import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/services/file_indexer.dart';
import 'package:circuit_ide/state/chat_context_draft_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('draft starts without hidden L-SDF context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final draft = container.read(chatContextDraftProvider);

    expect(draft.pinnedAttachments, isEmpty);
  });

  test('mentions become removable draft attachments', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(chatContextDraftProvider.notifier)
        .addMention(
          const IndexedFile(
            relativePath: 'lib/main.dart',
            fileName: 'main.dart',
            extension: '.dart',
            isDirectory: false,
          ),
        );

    final attachment = container
        .read(chatContextDraftProvider)
        .userAttachments
        .single;
    expect(attachment.id, 'mention:lib/main.dart');
    expect(attachment.label, 'main.dart');

    container
        .read(chatContextDraftProvider.notifier)
        .removeAttachment(attachment.id);
    expect(container.read(chatContextDraftProvider).userAttachments, isEmpty);
  });

  test('slash commands are stripped and serialized as attachments', () async {
    final root = await Directory.systemTemp.createTemp('chat_draft_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    await File(p.join(root.path, 'README.md')).writeAsString('hello map\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(fileTreeProvider.notifier).openDirectory(root.path);

    final result = await container
        .read(chatContextDraftProvider.notifier)
        .parseSlashCommands('/file README.md\nPlease explain this');

    expect(result.message, 'Please explain this');
    expect(result.attachments, hasLength(1));
    expect(
      result.attachments.map((attachment) => attachment.type),
      contains(ContextAttachmentType.file),
    );
    expect(result.attachments.single.content, contains('hello map'));
  });

  test(
    'image slash command attaches screenshot visual evidence metadata',
    () async {
      final root = await Directory.systemTemp.createTemp('chat_image_draft_');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final screenshot = File(p.join(root.path, 'screen.png'))
        ..writeAsBytesSync(_pngBytes(width: 1280, height: 720));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final result = await container
          .read(chatContextDraftProvider.notifier)
          .parseSlashCommands(
            '/image ${p.basename(screenshot.path)}\nReview it',
          );

      expect(result.message, 'Review it');
      expect(result.attachments, hasLength(1));
      final attachment = result.attachments.single;
      expect(attachment.type, ContextAttachmentType.image);
      expect(attachment.path, screenshot.path);
      expect(attachment.content, contains('Dimensions: 1280 x 720px'));
      expect(attachment.metadata['artifactRole'], 'visual_evidence');
      expect(attachment.metadata['visionInputStatus'], 'metadata_only');
    },
  );
}

Uint8List _pngBytes({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setAll(0, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  bytes.setAll(12, const [0x49, 0x48, 0x44, 0x52]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(16, width);
  data.setUint32(20, height);
  return bytes;
}
