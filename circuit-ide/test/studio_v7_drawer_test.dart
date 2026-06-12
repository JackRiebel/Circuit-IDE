import 'package:circuit_ide/models/studio_right_drawer.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/state/studio_right_drawer_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detectLocalUrls finds local preview URLs and strips punctuation', () {
    final urls = detectLocalUrls(
      'Preview at http://127.0.0.1:4173. Also open http://localhost:3000/app), '
      'but ignore https://example.com.',
    );

    expect(urls, contains('http://127.0.0.1:4173'));
    expect(urls, contains('http://localhost:3000/app'));
    expect(urls, isNot(contains('https://example.com')));
  });

  test('StudioRightDrawerController opens artifact-specific surfaces', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(studioRightDrawerProvider.notifier);

    controller.openArtifact(
      StudioSourceArtifact(
        id: 'preview',
        kind: StudioSourceArtifactKind.localUrl,
        title: 'localhost',
        subtitle: 'http://localhost:3000',
        value: 'http://localhost:3000',
        localUrl: 'http://localhost:3000',
        createdAt: DateTime(2026),
      ),
    );

    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.browser,
    );
    expect(
      container.read(studioRightDrawerProvider).localUrl,
      'http://localhost:3000',
    );

    controller.openArtifact(
      StudioSourceArtifact(
        id: 'command',
        kind: StudioSourceArtifactKind.command,
        title: 'npm run dev',
        subtitle: 'running',
        value: 'ready',
        commandRunId: 'run-1',
        createdAt: DateTime(2026),
      ),
    );

    expect(
      container.read(studioRightDrawerProvider).mode,
      StudioDrawerMode.terminal,
    );
    expect(container.read(studioRightDrawerProvider).commandRunId, 'run-1');
  });
}
