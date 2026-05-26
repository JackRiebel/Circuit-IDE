import 'dart:io';

import 'package:circuit_ide/models/context_attachment.dart';
import 'package:circuit_ide/services/file_indexer.dart';
import 'package:circuit_ide/state/chat_context_draft_provider.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('draft starts with visible pinned L-SDF context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final draft = container.read(chatContextDraftProvider);

    expect(draft.pinnedAttachments, hasLength(1));
    expect(draft.pinnedAttachments.single.id, 'pinned-lsdf');
    expect(
      draft.pinnedAttachments.single.type,
      ContextAttachmentType.lsdfIndex,
    );
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
        .parseSlashCommands('/map\n/file README.md\nPlease explain this');

    expect(result.message, 'Please explain this');
    expect(result.attachments, hasLength(2));
    expect(
      result.attachments.map((attachment) => attachment.type),
      containsAll([
        ContextAttachmentType.lsdfIndex,
        ContextAttachmentType.file,
      ]),
    );
    expect(result.attachments.last.content, contains('hello map'));
  });
}
