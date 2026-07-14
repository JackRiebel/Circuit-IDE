import 'dart:io';

import 'package:circuit_ide/services/file_indexer.dart';
import 'package:circuit_ide/services/semantic_index.dart';
import 'package:circuit_ide/services/worker_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'FileIndexer indexes large projects without unbounded content reads',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'file_indexer_budget_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final lib = Directory(p.join(root.path, 'lib'))..createSync();
      final repeatedPayload = '${List.filled(8192, 'x').join()}\n';
      for (var index = 0; index < 1200; index++) {
        File(p.join(lib.path, 'feature_$index.dart')).writeAsStringSync('''
class Feature$index {
  String get marker => "datacenterSizing";
  String get payload => "$repeatedPayload";
}
''');
      }

      final indexer = FileIndexer(workingDir: root.path);
      await indexer.index();

      final indexedSourceFiles = indexer.files.where(
        (file) => !file.isDirectory && file.extension == '.dart',
      );
      expect(indexedSourceFiles, hasLength(1200));
      expect(indexer.contentIndexedFileCount, lessThan(1200));
      expect(
        indexer.contentIndexedByteCount,
        lessThanOrEqualTo(6 * 1024 * 1024),
      );
      expect(
        indexedSourceFiles.any(
          (file) => file.contentTerms.contains('datacentersizing'),
        ),
        isTrue,
      );
    },
  );

  test('FileIndexer extracts symbols and searches declaration files', () async {
    final root = await Directory.systemTemp.createTemp('file_indexer_symbol_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final lib = Directory(p.join(root.path, 'lib'))..createSync();
    File(p.join(lib.path, 'sizing_engine.dart')).writeAsStringSync('''
class DatacenterSizingEngine {
  int scoreWanThroughput(int mbps) => mbps;
}
''');
    File(p.join(lib.path, 'notes.dart')).writeAsStringSync('''
const note = 'DatacenterSizingEngine appears in docs but is not declared here';
''');

    final indexer = FileIndexer(workingDir: root.path);
    await indexer.index();

    final engine = indexer.files.singleWhere(
      (file) => file.relativePath == 'lib/sizing_engine.dart',
    );
    expect(engine.symbols, contains('datacentersizingengine'));
    expect(engine.symbols, contains('datacenter'));
    expect(engine.symbols, contains('sizing'));
    expect(engine.symbols, contains('engine'));

    final results = indexer.search('DatacenterSizingEngine');
    expect(results.first.relativePath, 'lib/sizing_engine.dart');
  });

  test('SemanticIndex builds a queryable worker snapshot', () async {
    final root = await Directory.systemTemp.createTemp('semantic_worker_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final source = File(p.join(root.path, 'lib', 'policy_engine.dart'));
    await source.parent.create(recursive: true);
    await source.writeAsString('''
class PolicyEngine {
  bool requiresMfa(String role) => role == 'admin';
}
''');

    final index = SemanticIndex();
    await index.buildIndex(root.path);

    expect(index.chunkCount, greaterThan(0));
    expect(
      index.getCandidates('requires MFA').map((chunk) => chunk.filePath),
      contains(source.path),
    );
  });

  test(
    'SemanticIndex keeps its last complete snapshot when rebuild is cancelled',
    () async {
      final root = await Directory.systemTemp.createTemp('semantic_cancel_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final source = File(p.join(root.path, 'lib', 'policy_engine.dart'));
      await source.parent.create(recursive: true);
      await source.writeAsString('class PolicyEngine {}');

      final index = SemanticIndex();
      await index.buildIndex(root.path);
      final initialChunkCount = index.chunkCount;
      final cancellation = WorkerCancellationToken()
        ..cancel('Superseded semantic index build.');

      await expectLater(
        index.buildIndex(root.path, cancellationToken: cancellation),
        throwsA(isA<WorkerCancelledException>()),
      );
      expect(index.chunkCount, initialChunkCount);
    },
  );
}
