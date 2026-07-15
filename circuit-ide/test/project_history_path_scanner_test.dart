import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/project_history_path_scanner.dart';
import 'package:circuit_ide/services/worker_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'worker recovers only existing project roots from history entries',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-project-history-scan-',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = await Directory(
        '${root.path}${Platform.pathSeparator}project',
      ).create();
      final taskStore = await Directory(
        '${root.path}${Platform.pathSeparator}tasks',
      ).create();
      final threadStore = await Directory(
        '${root.path}${Platform.pathSeparator}threads',
      ).create();
      final validKey = base64Url.encode(utf8.encode(project.path));
      final missingKey = base64Url.encode(
        utf8.encode('${root.path}${Platform.pathSeparator}missing'),
      );
      await File(
        '${taskStore.path}${Platform.pathSeparator}$validKey.json',
      ).writeAsString('{}');
      await File(
        '${taskStore.path}${Platform.pathSeparator}$validKey.summary.json',
      ).writeAsString('{}');
      await File(
        '${threadStore.path}${Platform.pathSeparator}$missingKey.json',
      ).writeAsString('{}');
      await File(
        '${threadStore.path}${Platform.pathSeparator}scratch.json',
      ).writeAsString('{}');
      await File(
        '${threadStore.path}${Platform.pathSeparator}not-base64.json',
      ).writeAsString('{}');

      final recovered = await const ProjectHistoryPathScanner().recover(
        storageDirectories: [taskStore.path, threadStore.path],
      );

      expect(recovered, [project.path]);
    },
  );

  test('pre-cancelled history discovery does not start a worker', () async {
    final cancellation = WorkerCancellationToken()
      ..cancel('History view closed.');

    await expectLater(
      const ProjectHistoryPathScanner().recover(
        storageDirectories: const ['/does-not-matter'],
        cancellationToken: cancellation,
      ),
      throwsA(isA<WorkerCancelledException>()),
    );
  });
}
