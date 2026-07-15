import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:circuit_ide/models/studio_browser.dart';
import 'package:circuit_ide/models/studio_source_artifact.dart';
import 'package:circuit_ide/services/browser_visual_snapshot_archive.dart';
import 'package:circuit_ide/state/studio_browser_provider.dart';
import 'package:circuit_ide/state/studio_source_artifact_provider.dart';
import 'package:circuit_ide/state/studio_thread_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'browser permissions are scoped to exact origins and block navigation',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final browser = container.read(studioBrowserProvider.notifier);

      expect(browser.open('http://localhost:3000/dashboard'), isTrue);
      browser.blockCurrentSite();

      final blocked = container.read(studioBrowserProvider);
      expect(
        blocked.permissionFor('http://localhost:3000/other'),
        BrowserSitePermission.blocked,
      );
      expect(
        blocked.permissionFor('http://localhost:3001/dashboard'),
        BrowserSitePermission.unknown,
      );
      expect(browser.open('http://localhost:3000/other'), isFalse);
      expect(browser.open('http://localhost:3001/dashboard'), isTrue);
    },
  );

  test('browser refuses credential URLs and redacts durable URL provenance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final thread = container
        .read(studioThreadProvider.notifier)
        .ensureThread(title: 'Browser privacy review');
    final browser = container.read(studioBrowserProvider.notifier);

    expect(
      browser.open('https://user:private-password@docs.example.test/guide'),
      isFalse,
    );
    expect(
      browser.open(
        'https://docs.example.test/guide?session_token=private-token#fragment',
      ),
      isTrue,
    );
    browser.recordSnapshot(
      BrowserPageSnapshot(
        url:
            'https://docs.example.test/guide?session_token=private-token#fragment',
        title: 'Guide',
        selectedText: 'The user selected this fact.',
        selectedDomPath: 'main > p',
        textPreview: 'Private browser preview.',
        capturedAt: DateTime.utc(2026, 7, 14),
      ),
    );

    expect(browser.shareSelectedObservationWithCurrentTask(), isTrue);
    final artifact = container
        .read(studioSourceArtifactProvider)
        .forThread(thread.id)
        .single;
    expect(artifact.localUrl, 'https://docs.example.test/guide');
    expect(artifact.value, isNot(contains('session_token')));
    expect(artifact.value, isNot(contains('private-token')));
    expect(artifact.value, isNot(contains('fragment')));
  });

  test('browser snapshots are bounded and reset on navigation', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final browser = container.read(studioBrowserProvider.notifier);
    browser.open('https://example.test/report');

    browser.recordSnapshot(
      BrowserPageSnapshot(
        url: 'https://example.test/report',
        title: 'Report',
        selectedText: 'A user-highlighted finding',
        selectedDomPath: 'article:nth-of-type(1) > p:nth-of-type(2)',
        textPreview: 'A browser-only page snapshot',
        visualPngBytes: _validPngBytes,
        capturedAt: DateTime.utc(2026, 7, 12),
      ),
    );

    expect(container.read(studioBrowserProvider).snapshot?.title, 'Report');
    expect(
      container.read(studioBrowserProvider).snapshot?.hasSelection,
      isTrue,
    );
    expect(
      container.read(studioBrowserProvider).snapshot?.hasVisualSnapshot,
      isTrue,
    );

    browser.recordNavigationFromWebView('https://example.test/next');
    expect(container.read(studioBrowserProvider).snapshot, isNull);
  });

  test('browser visual snapshots reject unbounded session memory', () {
    final tooLarge = Uint8List(BrowserPageSnapshot.maxVisualSnapshotBytes + 1);
    final snapshot = BrowserPageSnapshot(
      url: 'https://example.test/report',
      title: 'Report',
      selectedText: '',
      selectedDomPath: '',
      textPreview: 'Private page state.',
      visualPngBytes: tooLarge,
      capturedAt: DateTime.utc(2026, 7, 13),
    );

    expect(snapshot.visualPngBytes, isNull);
    expect(snapshot.hasVisualSnapshot, isFalse);

    final headerOnly = BrowserPageSnapshot(
      url: 'https://example.test/report',
      title: 'Report',
      selectedText: '',
      selectedDomPath: '',
      textPreview: 'Invalid image fixture.',
      visualPngBytes: Uint8List.fromList(const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]),
      capturedAt: DateTime.utc(2026, 7, 13),
    );
    expect(headerOnly.visualPngBytes, isNull);
  });

  test('browser tabs retain separate histories and local snapshots', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final browser = container.read(studioBrowserProvider.notifier);

    expect(browser.open('https://first.example.test/brief'), isTrue);
    final firstTabId = container.read(studioBrowserProvider).activeTab.id;
    browser.recordSnapshot(
      BrowserPageSnapshot(
        url: 'https://first.example.test/brief',
        title: 'First brief',
        selectedText: '',
        selectedDomPath: '',
        textPreview: 'First tab stays private.',
        capturedAt: DateTime.utc(2026, 7, 13),
      ),
    );

    expect(browser.openInNewTab('https://second.example.test/start'), isTrue);
    final secondTabId = container.read(studioBrowserProvider).activeTab.id;
    expect(secondTabId, isNot(firstTabId));
    browser.recordNavigationFromWebView('https://second.example.test/next');
    browser.recordSnapshot(
      BrowserPageSnapshot(
        url: 'https://second.example.test/next',
        title: 'Second brief',
        selectedText: '',
        selectedDomPath: '',
        textPreview: 'Second tab stays private.',
        capturedAt: DateTime.utc(2026, 7, 13),
      ),
    );

    expect(browser.selectTab(firstTabId), isTrue);
    var session = container.read(studioBrowserProvider);
    expect(session.tabs, hasLength(2));
    expect(session.currentUrl, 'https://first.example.test/brief');
    expect(session.history, ['https://first.example.test/brief']);
    expect(session.snapshot?.title, 'First brief');

    expect(browser.selectTab(secondTabId), isTrue);
    session = container.read(studioBrowserProvider);
    expect(session.currentUrl, 'https://second.example.test/next');
    expect(session.history, [
      'https://second.example.test/start',
      'https://second.example.test/next',
    ]);
    expect(session.snapshot?.title, 'Second brief');

    expect(browser.closeTab(secondTabId), isTrue);
    session = container.read(studioBrowserProvider);
    expect(session.tabs, hasLength(1));
    expect(session.activeTab.id, firstTabId);
    expect(session.snapshot?.title, 'First brief');
  });

  test(
    'blocking an origin clears snapshots from every open page at that origin',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final browser = container.read(studioBrowserProvider.notifier);
      const url = 'https://docs.example.test/guide';

      expect(browser.open(url), isTrue);
      final firstTabId = container.read(studioBrowserProvider).activeTab.id;
      browser.recordSnapshot(
        BrowserPageSnapshot(
          url: url,
          title: 'First guide',
          selectedText: '',
          selectedDomPath: '',
          textPreview: 'Private first snapshot.',
          capturedAt: DateTime.utc(2026, 7, 13),
        ),
      );
      expect(browser.openInNewTab('$url?tab=two'), isTrue);
      browser.recordSnapshot(
        BrowserPageSnapshot(
          url: '$url?tab=two',
          title: 'Second guide',
          selectedText: '',
          selectedDomPath: '',
          textPreview: 'Private second snapshot.',
          capturedAt: DateTime.utc(2026, 7, 13),
        ),
      );

      browser.blockCurrentSite();
      final session = container.read(studioBrowserProvider);
      expect(session.tabs.map((tab) => tab.snapshot), everyElement(isNull));
      expect(browser.selectTab(firstTabId), isFalse);
      expect(container.read(studioBrowserProvider).currentUrl, url);
    },
  );

  test('browser tab creation is bounded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final browser = container.read(studioBrowserProvider.notifier);

    for (var index = 1; index < StudioBrowserSession.maxTabCount; index++) {
      expect(browser.createTab(), isTrue);
    }
    expect(browser.createTab(), isFalse);
    expect(
      container.read(studioBrowserProvider).tabs,
      hasLength(StudioBrowserSession.maxTabCount),
    );
  });

  test('browser history, drafts, annotations, and URLs stay bounded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final browser = container.read(studioBrowserProvider.notifier);
    expect(browser.open('https://example.test/initial'), isTrue);

    for (var index = 0; index <= StudioBrowserTab.maxHistoryEntries; index++) {
      browser.recordNavigationFromWebView('https://example.test/page-$index');
    }
    expect(
      container.read(studioBrowserProvider).history,
      hasLength(StudioBrowserTab.maxHistoryEntries),
    );
    expect(
      container.read(studioBrowserProvider).history.last,
      'https://example.test/page-${StudioBrowserTab.maxHistoryEntries}',
    );

    final oversized = List<String>.filled(
      StudioBrowserTab.maxAddressDraftLength + 1,
      'x',
    ).join();
    browser.setAddressDraft(oversized);
    expect(
      container.read(studioBrowserProvider).addressDraft.length,
      StudioBrowserTab.maxAddressDraftLength,
    );
    expect(browser.open('https://example.test/$oversized'), isFalse);

    for (
      var index = 0;
      index <= StudioBrowserSession.maxAnnotationCount;
      index++
    ) {
      browser.addAnnotation('Private annotation $index');
    }
    browser.addAnnotation(oversized);
    final annotations = container.read(studioBrowserProvider).annotations;
    expect(annotations, hasLength(StudioBrowserSession.maxAnnotationCount));
    expect(
      annotations.first.note.length,
      lessThanOrEqualTo(BrowserAnnotation.maxNoteLength),
    );
    expect(annotations.first.note, contains('[Browser annotation truncated]'));
  });

  test(
    'only an explicit selected-text action shares browser context with a task',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Research task');
      final browser = container.read(studioBrowserProvider.notifier);
      browser.open('https://docs.example.test/guide');
      browser.recordSnapshot(
        BrowserPageSnapshot(
          url: 'https://docs.example.test/guide',
          title: 'Guide',
          selectedText: 'This is the only text the user chose to share.',
          selectedDomPath: 'main:nth-of-type(1) > p:nth-of-type(1)',
          textPreview:
              'This broader page snapshot is never automatically shared.',
          visualPngBytes: _validPngBytes,
          capturedAt: DateTime.utc(2026, 7, 12),
        ),
      );

      browser.addAnnotation('Keep this private preview note.');
      expect(
        container.read(studioSourceArtifactProvider).forThread(thread.id),
        isEmpty,
      );
      expect(browser.shareSelectedObservationWithCurrentTask(), isTrue);

      final artifacts = container
          .read(studioSourceArtifactProvider)
          .forThread(thread.id);
      expect(artifacts, hasLength(1));
      expect(artifacts.single.kind, StudioSourceArtifactKind.browserSelection);
      expect(artifacts.single.value, contains('Untrusted browser observation'));
      expect(
        artifacts.single.value,
        contains('only text the user chose to share'),
      );
      expect(artifacts.single.value, isNot(contains('broader page snapshot')));
    },
  );

  test(
    'an explicit local visual save stores provenance but never browser context',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'circuit-browser-provider-',
      );
      final container = ProviderContainer(
        overrides: [
          browserVisualSnapshotArchiveProvider.overrideWithValue(
            BrowserVisualSnapshotArchive(rootResolver: () async => root),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final thread = container
          .read(studioThreadProvider.notifier)
          .ensureThread(title: 'Private website review');
      final browser = container.read(studioBrowserProvider.notifier);
      browser.open('https://portal.example.test/review');
      browser.recordSnapshot(
        BrowserPageSnapshot(
          url: 'https://portal.example.test/review',
          title: 'Private review',
          selectedText: 'This remains separate from the saved image.',
          selectedDomPath: 'main > section',
          textPreview: 'Never persist this page preview beside pixel metadata.',
          visualPngBytes: _validPngBytes,
          capturedAt: DateTime.utc(2026, 7, 13),
        ),
      );

      expect(
        await browser.saveVisualSnapshotToCurrentTask(),
        BrowserVisualSnapshotSaveResult.saved,
      );

      final artifacts = container
          .read(studioSourceArtifactProvider)
          .forThread(thread.id);
      expect(artifacts, hasLength(1));
      final artifact = artifacts.single;
      expect(artifact.kind, StudioSourceArtifactKind.browserVisualSnapshot);
      expect(await File(artifact.filePath!).exists(), isTrue);
      expect(
        artifact.value,
        contains('never automatically added to model context'),
      );
      expect(artifact.value, isNot(contains('This remains separate')));
      expect(
        artifact.value,
        isNot(contains('Never persist this page preview')),
      );
      expect(
        await browser.deleteVisualSnapshot(artifact.id),
        BrowserVisualSnapshotDeleteResult.deleted,
      );
      expect(await File(artifact.filePath!).exists(), isFalse);
      expect(
        container
            .read(studioSourceArtifactProvider)
            .forThread(thread.id)
            .where((candidate) => candidate.id == artifact.id),
        isEmpty,
      );
      expect(
        container
            .read(studioThreadProvider)
            .threads
            .singleWhere((candidate) => candidate.id == thread.id)
            .sourceArtifacts
            .where((candidate) => candidate.id == artifact.id),
        isEmpty,
      );
    },
  );
}

final _validPngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9J5l8AAAAASUVORK5CYII=',
  ),
);
