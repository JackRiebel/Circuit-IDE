import 'package:circuit_ide/services/macos_workspace_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/workspace_access');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('persists and resumes only a native security-scoped bookmark', () async {
    final store = _MemoryBookmarkStore();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'createAndStartWorkspaceAccess') {
            return {
              'sandboxed': true,
              'path': '/tmp/circuit-workspace',
              'bookmark': 'AQID',
            };
          }
          expect(call.method, 'resumeWorkspaceAccess');
          expect(call.arguments, {
            'path': '/tmp/circuit-workspace',
            'bookmark': 'AQID',
          });
          return {
            'sandboxed': true,
            'path': '/tmp/circuit-workspace',
            'bookmark': 'AQID',
          };
        });
    final access = NativeMacosWorkspaceAccess(
      channel: channel,
      store: store,
      isSupported: () => true,
      allowUnhostedDebugAccess: false,
    );

    final granted = await access.grantUserSelectedWorkspace(
      '/tmp/circuit-workspace',
    );
    final resumed = await access.resumeWorkspace('/tmp/circuit-workspace');

    expect(granted.granted, isTrue);
    expect(resumed.granted, isTrue);
    expect(calls.map((call) => call.method), [
      'createAndStartWorkspaceAccess',
      'resumeWorkspaceAccess',
    ]);
    expect(store.values, isNotEmpty);
  });

  test('missing stored grant fails closed before native access', () async {
    final store = _MemoryBookmarkStore();
    var nativeCall = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCall = true;
          return null;
        });
    final access = NativeMacosWorkspaceAccess(
      channel: channel,
      store: store,
      isSupported: () => true,
      allowUnhostedDebugAccess: false,
    );

    final result = await access.resumeWorkspace('/tmp/missing-grant');

    expect(result.granted, isFalse);
    expect(result.message, contains('Reopen the project folder'));
    expect(nativeCall, isFalse);
  });

  test('malformed native bookmark is rejected without persistence', () async {
    final store = _MemoryBookmarkStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {
            'sandboxed': true,
            'path': '/tmp/circuit-workspace',
            'bookmark': 'not a bookmark',
          },
        );
    final access = NativeMacosWorkspaceAccess(
      channel: channel,
      store: store,
      isSupported: () => true,
      allowUnhostedDebugAccess: false,
    );

    final result = await access.grantUserSelectedWorkspace(
      '/tmp/circuit-workspace',
    );

    expect(result.granted, isFalse);
    expect(store.values, isEmpty);
  });

  test(
    'an unsandboxed host never persists a bookmark-shaped response',
    () async {
      final store = _MemoryBookmarkStore();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {
              'sandboxed': false,
              'path': '/tmp/circuit-workspace',
              'bookmark': 'AQID',
            },
          );
      final access = NativeMacosWorkspaceAccess(
        channel: channel,
        store: store,
        isSupported: () => true,
        allowUnhostedDebugAccess: false,
      );

      final result = await access.grantUserSelectedWorkspace(
        '/tmp/circuit-workspace',
      );

      expect(result.granted, isTrue);
      expect(store.values, isEmpty);
    },
  );
}

class _MemoryBookmarkStore implements MacosWorkspaceBookmarkStore {
  final values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
