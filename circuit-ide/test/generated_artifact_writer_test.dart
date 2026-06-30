import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Excel prompt creates a real xlsx artifact from markdown table',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create an Excel file from this',
            content: '''
Here is the data.

| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
            turnId: 'turn-1',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.excel);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.xlsx'));
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      expect(String.fromCharCodes(bytes), contains('xl/workbook.xml'));
      expect(artifact.previewRows.first, ['Product', 'Count']);
      expect(artifact.sheetCount, 1);
    },
  );

  test('CSV prompt creates a CSV artifact from markdown table', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a CSV file from this',
          content: '''
| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
          turnId: 'turn-csv',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.csv);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.csv'));
    expect(File(artifact.filePath).readAsStringSync(), contains('C9300,6'));
  });

  test(
    'JSON prompt creates formatted JSON artifact when valid JSON is fenced',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'generate a JSON file',
            content: '''
```json
{"name":"Circuit","count":2}
```
''',
            turnId: 'turn-json',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.json);
      expect(
        File(artifact.filePath).readAsStringSync(),
        contains('"name": "Circuit"'),
      );
    },
  );
}
