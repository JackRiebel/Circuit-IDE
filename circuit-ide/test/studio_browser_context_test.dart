import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/models/studio_thread.dart';
import 'package:circuit_ide/ui/studio/studio_context_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only explicit browser selections enter a thread context payload', () {
    final createdAt = DateTime.utc(2026, 7, 12);
    final thread = StudioThread(
      id: 'thread-1',
      title: 'Research',
      createdAt: createdAt,
      updatedAt: createdAt,
      sourceArtifacts: [
        StudioSourceArtifact(
          id: 'browser-selection-1',
          kind: StudioSourceArtifactKind.browserSelection,
          title: 'Official guide',
          subtitle: 'User-selected browser text',
          value:
              'URL: https://docs.example.test/guide?access_token=private-token#fragment\n\nQuoted fact',
          localUrl:
              'https://docs.example.test/guide?access_token=private-token#fragment',
          createdAt: createdAt,
        ),
        StudioSourceArtifact(
          id: 'browser-image-1',
          kind: StudioSourceArtifactKind.browserVisualSnapshot,
          title: 'Saved local pixels',
          subtitle: 'Never model context',
          value: 'Pixel image is local only.',
          filePath: '/private/local/browser.png',
          localUrl: 'https://docs.example.test/guide',
          createdAt: createdAt,
        ),
        StudioSourceArtifact(
          id: 'browser-comment-1',
          kind: StudioSourceArtifactKind.browserComment,
          title: 'Private note',
          subtitle: 'Browser annotation',
          value: 'Do not send this private note.',
          localUrl: 'https://docs.example.test/guide',
          createdAt: createdAt,
        ),
      ],
    );

    final attachments = browserSelectionContextAttachments(thread);

    expect(attachments, hasLength(1));
    expect(attachments.single.path, 'https://docs.example.test/guide');
    expect(attachments.single.content, contains('Quoted fact'));
    expect(attachments.single.content, isNot(contains('access_token')));
    expect(attachments.single.content, isNot(contains('private-token')));
    expect(attachments.single.content, isNot(contains('fragment')));
    expect(attachments.single.content, contains('untrusted data'));
    expect(attachments.single.content, isNot(contains('private note')));
    expect(attachments.single.content, isNot(contains('Pixel image')));
    expect(
      attachments.single.metadata['browserContext'],
      'explicit_user_selection',
    );
  });
}
