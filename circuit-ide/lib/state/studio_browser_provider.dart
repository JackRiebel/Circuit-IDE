import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/studio_browser.dart';
import '../models/studio_source_artifact.dart';
import 'studio_source_artifact_provider.dart';
import 'studio_thread_provider.dart';

const _uuid = Uuid();

class StudioBrowserController extends Notifier<StudioBrowserSession> {
  @override
  StudioBrowserSession build() => const StudioBrowserSession();

  void setAddressDraft(String value) {
    state = state.copyWith(addressDraft: value);
  }

  bool open(String input) {
    final url = normalizeBrowserUrl(input);
    if (url == null) {
      state = state.copyWith(error: 'Enter a valid http or https URL.');
      return false;
    }
    final nextHistory = [...state.history.take(state.historyIndex + 1), url];
    state = state.copyWith(
      currentUrl: url,
      addressDraft: url,
      history: nextHistory,
      historyIndex: nextHistory.length - 1,
      loadingProgress: 0,
      error: null,
      permission: BrowserSitePermission.unknown,
    );
    return true;
  }

  void goBack() {
    if (!state.canGoBack) return;
    final index = state.historyIndex - 1;
    final url = state.history[index];
    state = state.copyWith(
      currentUrl: url,
      addressDraft: url,
      historyIndex: index,
      loadingProgress: 0,
      error: null,
    );
  }

  void goForward() {
    if (!state.canGoForward) return;
    final index = state.historyIndex + 1;
    final url = state.history[index];
    state = state.copyWith(
      currentUrl: url,
      addressDraft: url,
      historyIndex: index,
      loadingProgress: 0,
      error: null,
    );
  }

  void reload() {
    state = state.copyWith(reloadNonce: state.reloadNonce + 1, error: null);
  }

  void setProgress(int progress) {
    state = state.copyWith(loadingProgress: progress.clamp(0, 100));
  }

  void setError(String? error) {
    state = state.copyWith(error: error);
  }

  void allowSite() {
    state = state.copyWith(permission: BrowserSitePermission.allowed);
  }

  void blockSite() {
    state = state.copyWith(permission: BrowserSitePermission.blocked);
  }

  void addAnnotation(String note) {
    final url = state.currentUrl;
    final trimmed = note.trim();
    if (url == null || trimmed.isEmpty) return;
    final annotation = BrowserAnnotation(
      id: _uuid.v4().substring(0, 8),
      url: url,
      note: trimmed,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(annotations: [annotation, ...state.annotations]);
    final thread = ref.read(studioThreadProvider).selectedThread;
    if (thread == null) return;
    ref
        .read(studioSourceArtifactProvider.notifier)
        .add(
          StudioSourceArtifact(
            id: 'browser-comment-${thread.id}-${annotation.id}',
            kind: StudioSourceArtifactKind.browserComment,
            title: 'Browser comment',
            subtitle: url,
            value: trimmed,
            threadId: thread.id,
            requestId: thread.requestId,
            localUrl: url,
            createdAt: annotation.createdAt,
          ),
        );
  }
}

final studioBrowserProvider =
    NotifierProvider<StudioBrowserController, StudioBrowserSession>(
      StudioBrowserController.new,
    );
