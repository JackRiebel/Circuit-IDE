import 'dart:io';

import 'package:circuit_ide/agent/context/memories_loader.dart';
import 'package:circuit_ide/state/file_tree_provider.dart';
import 'package:circuit_ide/state/memories_provider.dart';
import 'package:circuit_ide/state/suggested_learning_provider.dart';
import 'package:circuit_ide/ui/memories/memory_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('memory documents preserve provenance and last-used metadata', () async {
    final root = await Directory.systemTemp.createTemp('memory_metadata_');
    addTearDown(() => root.delete(recursive: true));
    final createdAt = DateTime.utc(2026, 7, 1, 8);
    final usedAt = DateTime.utc(2026, 7, 2, 9, 30);

    await MemoriesLoader.saveMemory(
      root.path,
      'manual-note',
      'Use focused changes.',
      createdAt: createdAt,
    );
    final manual = (await MemoriesLoader.loadMemories(root.path)).single;
    expect(manual.provenance, MemoryProvenance.userAuthored);
    expect(manual.createdAt, createdAt);
    expect(manual.lastUsedAt, isNull);

    await MemoriesLoader.markUsed(manual, at: usedAt);
    final used = (await MemoriesLoader.loadMemories(root.path)).single;
    expect(used.lastUsedAt, usedAt);
    expect(used.content, 'Use focused changes.');

    final learnedFile = File(
      p.join(root.path, '.circuit', 'memories', 'learned-note.md'),
    );
    await learnedFile.writeAsString('''
---
kind: circuit-memory
provenance: learned
created-at: 2026-07-03T10:00:00.000Z
last-used-at: 2026-07-04T11:00:00.000Z
---
Reviewed project convention.
''');
    final learned = (await MemoriesLoader.loadMemories(
      root.path,
    )).firstWhere((memory) => memory.name == 'learned-note');
    expect(learned.provenance, MemoryProvenance.learned);
    expect(learned.createdAt, DateTime.utc(2026, 7, 3, 10));
    expect(learned.lastUsedAt, DateTime.utc(2026, 7, 4, 11));
  });

  test(
    'automatic learning rejects secret-bearing content before suggestion',
    () {
      expect(
        containsSensitiveAutomaticLearningContent(
          'Use API_KEY=super-secret-value for local development.',
        ),
        isTrue,
      );
      expect(
        containsSensitiveAutomaticLearningContent(
          '-----BEGIN PRIVATE KEY-----',
        ),
        isTrue,
      );
      expect(
        containsSensitiveAutomaticLearningContent(
          'Prefer small reviewable patches and Riverpod state.',
        ),
        isFalse,
      );
    },
  );

  test(
    'approved memory suggestions persist as reviewed learned notes',
    () async {
      final root = await Directory.systemTemp.createTemp('learned_memory_');
      addTearDown(() => root.delete(recursive: true));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(fileTreeProvider.notifier).openDirectory(root.path);

      final suggestion = container
          .read(suggestedLearningProvider.notifier)
          .suggestMemory(
            name: 'review-first',
            content: 'Keep proposed changes small and reviewable.',
          );
      await container
          .read(suggestedLearningProvider.notifier)
          .approve(suggestion.id);
      await container.read(memoriesProvider.notifier).loadMemories();

      final learned = container
          .read(memoriesProvider)
          .projectMemories
          .singleWhere((memory) => memory.name == 'review-first');
      expect(learned.provenance, MemoryProvenance.learned);
      expect(learned.lastUsedAt, isNull);
    },
  );

  testWidgets('memory item exposes provenance, scope, and last use', (
    tester,
  ) async {
    final memory = Memory(
      name: 'review-first',
      content: 'Keep proposed changes small and reviewable.',
      filePath: '/tmp/review-first.md',
      isGlobal: false,
      modified: DateTime.utc(2026, 7, 4),
      provenance: MemoryProvenance.learned,
      createdAt: DateTime.utc(2026, 7, 3),
      lastUsedAt: DateTime(2026, 7, 4),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MemoryItem(memory: memory, onEdit: () {}, onDelete: () {}),
          ),
        ),
      ),
    );

    expect(find.text('review-first'), findsOneWidget);
    expect(
      find.text('Project · reviewed learned · Last used 2026-07-04'),
      findsOneWidget,
    );
  });
}
