import 'dart:io';

import 'package:circuit_ide/services/summary_index_page_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker pages large summary indexes without losing later valid rows',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-summary-index-',
      );
      addTearDown(() => root.delete(recursive: true));
      final index = File('${root.path}${Platform.pathSeparator}index.jsonl');
      await index.writeAsString('''
{"kind":"circuit.studio-thread-summary-index","version":1,"totalCount":4}
{"id":"first","title":"First"}
not-json
{"id":"second","title":"Second"}
{"id":"third","title":"Third"}
{"id":"fourth","title":"Fourth"}
''');

      final page = await const SummaryIndexPageReader().read(
        path: index.path,
        headerKind: 'circuit.studio-thread-summary-index',
        offset: 1,
        limit: 2,
      );

      expect(page.declaredTotalCount, 4);
      expect(page.readableRecordCount, 4);
      expect(page.totalCount, 4);
      expect(page.records.map((record) => record['id']), ['second', 'third']);
    },
  );

  test(
    'worker reports readable records when a stale header undercounts them',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-summary-index-',
      );
      addTearDown(() => root.delete(recursive: true));
      final index = File('${root.path}${Platform.pathSeparator}index.jsonl');
      await index.writeAsString('''
{"kind":"circuit.agent-task-summary-index","version":1,"totalCount":1}
{"id":"first"}
{"id":"second"}
''');

      final page = await const SummaryIndexPageReader().read(
        path: index.path,
        headerKind: 'circuit.agent-task-summary-index',
        offset: 0,
        limit: 12,
      );

      expect(page.totalCount, 2);
      expect(page.records.map((record) => record['id']), ['first', 'second']);
    },
  );
}
