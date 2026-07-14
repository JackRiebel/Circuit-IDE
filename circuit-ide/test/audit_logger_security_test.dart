import 'dart:io';

import 'package:circuit_ide/agent/security/audit_logger.dart';
import 'package:circuit_ide/models/provider_lifecycle_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'audit records redact seeded prompts, tool data, paths, and secrets',
    () async {
      final directory = await Directory.systemTemp.createTemp('circuit-audit-');
      addTearDown(() => directory.delete(recursive: true));
      final logger = AuditLogger(directoryPath: directory.path);
      const promptSecret = 'sk-this-is-a-seeded-secret-value';
      const headerSecret = 'Bearer private-header-secret';
      const fileContents = 'customer spreadsheet row 31';
      const localPath = '/Users/tester/Customer/secret.txt';

      await logger.init();
      await logger.logUserInput(
        'Please use $promptSecret to review $fileContents',
      );
      await logger.logToolCall(
        'web_fetch',
        {
          'url': 'https://api.example.test/export?token=private-query-token',
          'path': localPath,
          'Authorization': headerSecret,
          'content': fileContents,
        },
        'Result contained $headerSecret and $fileContents at $localPath',
        true,
      );
      await logger.logError(
        'provider_error',
        'Request to https://api.example.test?api_key=private-query-token failed',
        {
          'prompt': 'full $fileContents',
          'HOME': '/Users/tester',
          'api_key': 'private-query-token',
        },
      );

      final sessions = await logger.listSessions();
      expect(sessions, hasLength(1));
      final stored = await logger.inspectSession(sessions.single.id);

      expect(stored, isNotNull);
      for (final secret in [
        promptSecret,
        headerSecret,
        fileContents,
        localPath,
        'private-query-token',
      ]) {
        expect(stored, isNot(contains(secret)), reason: secret);
      }
      expect(stored, contains('[REDACTED PROMPT'));
      expect(stored, contains('[REDACTED TOOL RESULT'));
      expect(stored, contains('https://api.example.test/[REDACTED]'));
      expect(await logger.deleteSession(sessions.single.id), isTrue);
      expect(await logger.listSessions(), isEmpty);
    },
  );

  test('audit retention purges only expired session files', () async {
    final directory = await Directory.systemTemp.createTemp('circuit-audit-');
    addTearDown(() => directory.delete(recursive: true));
    final old = File('${directory.path}/session-old.jsonl')
      ..writeAsStringSync('{"old":true}\n');
    await old.setLastModified(DateTime.now().subtract(const Duration(days: 8)));
    final recent = File('${directory.path}/session-recent.jsonl')
      ..writeAsStringSync('{"recent":true}\n');
    final logger = AuditLogger(
      directoryPath: directory.path,
      retention: const Duration(days: 7),
    );

    expect(await logger.purgeExpired(), 1);
    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isTrue);
  });

  test(
    'support bundles re-redact retained records and export no seeded data',
    () async {
      final directory = await Directory.systemTemp.createTemp('circuit-audit-');
      addTearDown(() => directory.delete(recursive: true));
      const promptSecret = 'private customer prompt';
      const tokenSecret = 'sk-exported-secret-value';
      const localPath = '/Users/tester/Customer/financials.xlsx';
      const sourceUrl = 'https://api.example.test/export?token=private-token';
      final legacySession = File('${directory.path}/session-legacy.jsonl');
      await legacySession.writeAsString(
        '{"prompt":"$promptSecret","token":"$tokenSecret",'
        '"path":"$localPath","url":"$sourceUrl"}\n',
      );
      final logger = AuditLogger(directoryPath: directory.path);

      final bundle = await logger.buildSupportBundle(
        metadata: {
          'prompt': promptSecret,
          'authorization': 'Bearer $tokenSecret',
          'endpoint': sourceUrl,
        },
      );
      final exported = await logger.exportSupportBundle(
        '${directory.path}/support-bundle.json',
        metadata: {'prompt': promptSecret},
      );
      final exportedBundle = await exported.readAsString();

      for (final secret in [
        promptSecret,
        tokenSecret,
        localPath,
        'private-token',
      ]) {
        expect(bundle, isNot(contains(secret)), reason: secret);
        expect(exportedBundle, isNot(contains(secret)), reason: secret);
      }
      expect(bundle, contains('circuit.support-bundle'));
      expect(bundle, contains('https://api.example.test/[REDACTED]'));
      expect(exported.path, '${directory.path}/support-bundle.json');
    },
  );

  test('persisted provider diagnostics redact raw transport bodies', () {
    const promptSecret = 'customer prompt should never be persisted as trace';
    const bearer = 'Bearer private-provider-token';
    const localPath = '/Users/tester/Customer/secret.txt';
    final event = ProviderLifecycleEvent(
      requestId: 'request-1',
      kind: ProviderLifecycleEventKind.failed,
      timestamp: DateTime(2026),
      model: 'test-model',
      detail: 'Request at https://provider.example.test/run failed: $bearer',
      rawDiagnostic: '$promptSecret at $localPath',
    );

    final persisted = event.toJson();
    expect(persisted['detail'], isNot(contains('private-provider-token')));
    expect(persisted['rawDiagnostic'], isNot(contains(promptSecret)));
    expect(persisted['rawDiagnostic'], isNot(contains(localPath)));
    expect(persisted['rawDiagnostic'], contains('[REDACTED DIAGNOSTIC BODY'));

    final reloaded = ProviderLifecycleEvent.fromJson(persisted)!;
    expect(reloaded.rawDiagnostic, isNot(contains(promptSecret)));
    expect(reloaded.detail, isNot(contains('private-provider-token')));
  });
}
