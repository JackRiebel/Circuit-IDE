import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/crash_reporting_boundary.dart';
import 'package:circuit_ide/services/privacy_crash_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'writes only opt-in, redacted local crash reports and exports them',
    () async {
      final root = await Directory.systemTemp.createTemp('crash_reporter_');
      addTearDown(() => root.delete(recursive: true));
      var enabled = false;
      final reporter = PrivacyCrashReporter(
        isEnabled: () => enabled,
        directoryPath: root.path,
      );
      reporter.addBreadcrumb(
        CrashBreadcrumbEvent.turnFailed,
        metadata: {
          'prompt': 'Keep this customer request private.',
          'path': '/Users/example/private/project.dart',
          'token': 'super-secret-token',
          'phase': 'requesting',
        },
      );
      await reporter.record(
        error: StateError(
          'prompt=Customer source and token=super-secret-token',
        ),
        stackTrace: StackTrace.fromString(
          '#0   crash (/Users/example/private/project.dart:14:2)\n'
          'prompt=Customer source and token=super-secret-token',
        ),
        source: 'flutter',
      );

      expect(await File(reporter.filePath).exists(), isFalse);

      enabled = true;
      await reporter.record(
        error: StateError(
          'prompt=Customer source and token=super-secret-token',
        ),
        stackTrace: StackTrace.fromString(
          '#0   crash (/Users/example/private/project.dart:14:2)\n'
          'prompt=Customer source and token=super-secret-token',
        ),
        source: 'flutter',
      );

      final persisted = await File(reporter.filePath).readAsString();
      expect(persisted, contains('StateError: [REDACTED DIAGNOSTIC BODY]'));
      expect(persisted, contains('[PATH]'));
      expect(persisted, contains('[REDACTED CONTENT'));
      expect(persisted, contains('turn.failed'));
      expect(persisted, isNot(contains('Customer source')));
      expect(persisted, isNot(contains('super-secret-token')));

      final events = await reporter.load();
      expect(events, hasLength(1));
      expect(events.single.source, 'flutter');
      expect(events.single.breadcrumbs.single.metadata['phase'], 'requesting');

      final destination = File('${root.path}/export.json');
      await reporter.export(destination);
      final exported = await destination.readAsString();
      final envelope = jsonDecode(exported) as Map<String, dynamic>;
      expect(envelope['kind'], 'circuit.redacted-crash-report-export');
      expect(exported, isNot(contains('Customer source')));
      expect(exported, isNot(contains('super-secret-token')));
    },
  );

  test('tolerates incomplete crash ledger records', () async {
    final root = await Directory.systemTemp.createTemp('crash_reporter_');
    addTearDown(() => root.delete(recursive: true));
    final reporter = PrivacyCrashReporter(
      isEnabled: () => true,
      directoryPath: root.path,
    );
    final ledger = File(reporter.filePath);
    await ledger.parent.create(recursive: true);
    await ledger.writeAsString('{not valid json}\n');

    expect(await reporter.load(), isEmpty);
  });

  test('refuses a symlinked ledger and bounds retained diagnostics', () async {
    final root = await Directory.systemTemp.createTemp('crash_reporter_');
    addTearDown(() => root.delete(recursive: true));
    final reporter = PrivacyCrashReporter(
      isEnabled: () => true,
      directoryPath: root.path,
      ledgerByteLimit: 1200,
    );
    final external = File('${root.path}/external-sentinel.txt');
    await external.writeAsString('must not be touched');
    final ledger = File(reporter.filePath);
    await ledger.parent.create(recursive: true);
    await Link(ledger.path).create(external.path);

    expect(await reporter.load(), isEmpty);
    await reporter.record(
      error: StateError('linked ledger'),
      stackTrace: StackTrace.fromString('#0 linked ledger'),
      source: 'runtime',
    );
    expect(await external.readAsString(), 'must not be touched');
    expect(
      await FileSystemEntity.type(ledger.path, followLinks: false),
      FileSystemEntityType.link,
    );

    await ledger.delete();
    for (var index = 0; index < 24; index++) {
      await reporter.record(
        error: StateError('bounded crash $index'),
        stackTrace: StackTrace.fromString('#0 bounded crash $index'),
        source: 'runtime',
      );
    }

    expect(await ledger.length(), lessThanOrEqualTo(1200));
    final events = await reporter.load();
    expect(events, isNotEmpty);
    expect(events.length, lessThan(24));
    expect(events.first.source, 'runtime');
  });

  test(
    'Flutter and platform boundaries synchronously persist redacted events',
    () async {
      final root = await Directory.systemTemp.createTemp('crash_boundary_');
      addTearDown(() => root.delete(recursive: true));
      final reporter = PrivacyCrashReporter(
        isEnabled: () => true,
        directoryPath: root.path,
      );
      reporter.addBreadcrumb(
        CrashBreadcrumbEvent.turnFailed,
        metadata: {
          'prompt': 'Do not retain this customer prompt.',
          'authorization': 'Bearer boundary-secret',
        },
      );
      final presented = <FlutterErrorDetails>[];
      final boundary = CrashReportingBoundary(
        reporter: reporter,
        presentFlutterError: presented.add,
      );
      final stack = StackTrace.fromString(
        '#0   crash (/Users/example/customer/private.dart:18:3) '
        'token=boundary-secret prompt=private customer content',
      );

      boundary.handleFlutterError(
        FlutterErrorDetails(
          exception: StateError('prompt=private customer content'),
          stack: stack,
        ),
      );
      expect(presented, hasLength(1));
      expect(
        boundary.handlePlatformError(
          StateError('authorization=Bearer boundary-secret'),
          stack,
        ),
        isFalse,
      );

      final persisted = await File(reporter.filePath).readAsString();
      expect(persisted, contains('"source":"flutter"'));
      expect(persisted, contains('"source":"platform"'));
      expect(persisted, contains('[PATH]'));
      expect(persisted, isNot(contains('private customer content')));
      expect(persisted, isNot(contains('boundary-secret')));
      expect(await reporter.load(), hasLength(2));
    },
  );
}
