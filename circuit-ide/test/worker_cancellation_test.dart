import 'dart:io';
import 'dart:isolate';

import 'package:circuit_ide/services/worker_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancelling a running worker terminates it without waiting for completion',
    () async {
      final cancellation = WorkerCancellationToken();
      final stopwatch = Stopwatch()..start();
      final work = CancellableWorker.run<String>(
        entryPoint: _blockingWorker,
        arguments: const {},
        cancellationToken: cancellation,
        decodeResult: (result) => result! as String,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancellation.cancel('Test cancellation.');

      await expectLater(work, throwsA(isA<WorkerCancelledException>()));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );
}

void _blockingWorker(Map<String, Object?> arguments) {
  final replyPort = arguments['replyPort'];
  if (replyPort is! SendPort) return;
  sleep(const Duration(seconds: 3));
  replyPort.send({'result': 'unexpected completion'});
}
