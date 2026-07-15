import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/studio_browser.dart';
import '../../models/studio_right_drawer.dart';
import '../../models/studio_source_artifact.dart';
import '../../services/browser_visual_snapshot_service.dart';
import '../../state/studio_browser_provider.dart';
import '../../state/studio_right_drawer_provider.dart';
import '../../state/studio_source_artifact_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_browser_controls.dart';
import 'studio_drawer_empty_state.dart';

/// User-controlled browser preview, navigation, and page-observation capture.
class StudioBrowserDrawer extends ConsumerStatefulWidget {
  const StudioBrowserDrawer({super.key});

  @override
  ConsumerState<StudioBrowserDrawer> createState() =>
      _StudioBrowserDrawerState();
}

class _StudioBrowserDrawerState extends ConsumerState<StudioBrowserDrawer> {
  final BrowserVisualSnapshotService _visualSnapshotService =
      BrowserVisualSnapshotService.platform();
  WebViewController? _controller;
  String? _loadedUrl;
  String? _scheduledLoadKey;
  String? _handledArtifactUrl;
  int _loadedReloadNonce = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = ref.watch(themeProvider);
    final drawer = ref.watch(studioRightDrawerProvider);
    final session = ref.watch(studioBrowserProvider);
    final selected = _selectedArtifact(ref);
    final artifactUrl = drawer.localUrl ?? selected?.localUrl;
    // A local preview/source URL is a one-time browser seed, not a permanent
    // navigation instruction. Otherwise selecting another tab would reset it
    // back to the artifact URL on every build.
    if (artifactUrl != null && artifactUrl != _handledArtifactUrl) {
      _handledArtifactUrl = artifactUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(studioBrowserProvider).currentUrl == artifactUrl) return;
        ref.read(studioBrowserProvider.notifier).open(artifactUrl);
      });
    }
    final activeUrl = session.currentUrl ?? artifactUrl;
    final sitePermission = session.permissionFor(activeUrl);
    // A blocked origin must never be scheduled for a WebView load, including
    // when restored browser session state is mounted before the blocked UI.
    if (activeUrl != null &&
        sitePermission != BrowserSitePermission.blocked &&
        (activeUrl != _loadedUrl ||
            session.reloadNonce != _loadedReloadNonce)) {
      final loadKey = '$activeUrl#${session.reloadNonce}';
      if (_scheduledLoadKey != loadKey) {
        _scheduledLoadKey = loadKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_loadedUrl == activeUrl &&
              _loadedReloadNonce == session.reloadNonce) {
            return;
          }
          _load(activeUrl, session.reloadNonce);
        });
      }
    }

    return Column(
      children: [
        StudioBrowserTabStrip(
          session: session,
          onSelect: (tabId) =>
              ref.read(studioBrowserProvider.notifier).selectTab(tabId),
          onClose: (tabId) =>
              ref.read(studioBrowserProvider.notifier).closeTab(tabId),
          onCreate: () => ref.read(studioBrowserProvider.notifier).createTab(),
        ),
        StudioBrowserToolbar(
          session: session,
          onBack: () {
            ref.read(studioBrowserProvider.notifier).goBack();
          },
          onForward: () {
            ref.read(studioBrowserProvider.notifier).goForward();
          },
          onNavigate: (value) {
            ref.read(studioBrowserProvider.notifier).open(value);
          },
          onReload: () {
            ref.read(studioBrowserProvider.notifier).reload();
          },
          onCopy: activeUrl == null
              ? null
              : () => Clipboard.setData(ClipboardData(text: activeUrl)),
          onOpenExternal: activeUrl == null
              ? null
              : () => launchUrl(Uri.parse(activeUrl)),
          onAllow: () {
            ref.read(studioBrowserProvider.notifier).allowCurrentSite();
            ref.read(studioBrowserProvider.notifier).reload();
          },
          onBlock: () =>
              ref.read(studioBrowserProvider.notifier).blockCurrentSite(),
          onComment: () => _showCommentDialog(activeUrl),
          onCaptureObservation: _captureCurrentObservation,
          onSaveVisualSnapshot: _saveVisualSnapshot,
          onShareSelection: _shareSelectedObservation,
        ),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              session.error!,
              style: TextStyle(color: tokens.error, fontSize: FontSizes.sm),
            ),
          ),
        if (activeUrl == null)
          Expanded(
            child: StudioDrawerEmptyState(
              icon: StudioIcons.language,
              title: 'Open a browser preview',
              detail:
                  'Enter an http or https URL. This user-controlled preview never gives the assistant browser control.',
              actionLabel: 'Open sources',
              onAction: () => ref
                  .read(studioRightDrawerProvider.notifier)
                  .openMode(StudioDrawerMode.sources),
            ),
          )
        else if (sitePermission == BrowserSitePermission.blocked)
          const Expanded(
            child: StudioDrawerEmptyState(
              icon: StudioIcons.block,
              title: 'Site blocked',
              detail: 'Allow this site from the browser toolbar to load it.',
            ),
          )
        else
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
      ],
    );
  }

  StudioSourceArtifact? _selectedArtifact(WidgetRef ref) {
    final drawer = ref.watch(studioRightDrawerProvider);
    return ref.watch(
      studioSourceArtifactByIdProvider(drawer.selectedArtifactId),
    );
  }

  void _load(String url, int reloadNonce) {
    _loadedUrl = url;
    _loadedReloadNonce = reloadNonce;
    ref.read(studioBrowserProvider.notifier).setError(null);
    ref.read(studioBrowserProvider.notifier).setProgress(0);
    _controller = WebViewController()
      // JavaScript is enabled for the page's own rendering only. Circuit adds
      // no JavaScript channels and captures a bounded, user-visible snapshot;
      // an agent cannot issue browser commands through this controller.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = normalizeBrowserUrl(request.url);
            if (target == null) {
              ref
                  .read(studioBrowserProvider.notifier)
                  .setError('Blocked non-web navigation from browser preview.');
              return NavigationDecision.prevent;
            }
            if (ref.read(studioBrowserProvider).isBlocked(target)) {
              ref
                  .read(studioBrowserProvider.notifier)
                  .setError('This site is blocked for this browser session.');
              return NavigationDecision.prevent;
            }
            if (request.isMainFrame) {
              _loadedUrl = target;
              ref
                  .read(studioBrowserProvider.notifier)
                  .recordNavigationFromWebView(target);
            }
            return NavigationDecision.navigate;
          },
          onProgress: (progress) {
            ref.read(studioBrowserProvider.notifier).setProgress(progress);
          },
          onWebResourceError: (error) {
            ref
                .read(studioBrowserProvider.notifier)
                .setError(error.description);
          },
          onPageFinished: (pageUrl) {
            final target = normalizeBrowserUrl(pageUrl);
            if (target == null) return;
            _loadedUrl = target;
            ref
                .read(studioBrowserProvider.notifier)
                .recordNavigationFromWebView(target);
            _capturePageObservation(target);
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    setState(() {});
  }

  Future<void> _captureCurrentObservation() async {
    final url = ref.read(studioBrowserProvider).currentUrl;
    if (url == null) return;
    await _capturePageObservation(url);
  }

  Future<void> _capturePageObservation(String pageUrl) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await controller.runJavaScriptReturningResult(
        _browserObservationScript,
      );
      final observation = _decodeBrowserObservation(result);
      if (observation == null) {
        ref
            .read(studioBrowserProvider.notifier)
            .setError('Could not capture a page observation.');
        return;
      }
      final visualPngBytes = await _visualSnapshotService.capture(pageUrl);
      ref
          .read(studioBrowserProvider.notifier)
          .recordSnapshot(
            BrowserPageSnapshot(
              url: pageUrl,
              title: observation['title'] ?? '',
              selectedText: observation['selectedText'] ?? '',
              selectedDomPath: observation['selectedDomPath'] ?? '',
              textPreview: observation['textPreview'] ?? '',
              visualPngBytes: visualPngBytes,
              capturedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      ref
          .read(studioBrowserProvider.notifier)
          .setError('Could not capture a page observation.');
    }
  }

  Map<String, String>? _decodeBrowserObservation(Object result) {
    try {
      dynamic decoded = result;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map) return null;
      return {
        for (final key in const [
          'title',
          'selectedText',
          'selectedDomPath',
          'textPreview',
        ])
          key: decoded[key]?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  void _shareSelectedObservation() {
    final shared = ref
        .read(studioBrowserProvider.notifier)
        .shareSelectedObservationWithCurrentTask();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? 'Selected browser text shared with the current task.'
              : 'Capture text, select a task, then choose Share selected text.',
        ),
      ),
    );
  }

  Future<void> _saveVisualSnapshot() async {
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        final tokens = ref.read(themeProvider);
        return AlertDialog(
          backgroundColor: tokens.studioPanel,
          title: const Text('Save local visual snapshot?'),
          content: const Text(
            'This writes the currently visible page pixels to CircuitCode local app data for the current task. It is not added to model context or sent anywhere, but it may contain sensitive information.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save local copy'),
            ),
          ],
        );
      },
    );
    if (shouldSave != true || !mounted) return;
    final result = await ref
        .read(studioBrowserProvider.notifier)
        .saveVisualSnapshotToCurrentTask();
    if (!mounted) return;
    final message = switch (result) {
      BrowserVisualSnapshotSaveResult.saved =>
        'Saved a local visual snapshot with the current task.',
      BrowserVisualSnapshotSaveResult.noTask =>
        'Select a task before saving a visual snapshot.',
      BrowserVisualSnapshotSaveResult.noVisualSnapshot =>
        'Capture the visible page before saving a visual snapshot.',
      BrowserVisualSnapshotSaveResult.failed =>
        'Could not save the local visual snapshot.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showCommentDialog(String? url) async {
    if (url == null) return;
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) {
        final tokens = ref.read(themeProvider);
        return AlertDialog(
          backgroundColor: tokens.studioPanel,
          title: const Text('Comment on preview'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Describe what Circuit should notice or change...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add comment'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (note == null || note.trim().isEmpty) return;
    ref.read(studioBrowserProvider.notifier).addAnnotation(note);
  }
}

const _browserObservationScript = r'''
(() => {
  const limit = (value, maximum) => String(value || '').slice(0, maximum);
  const selection = window.getSelection();
  const selectedText = limit(selection ? selection.toString() : '', 12000);
  const locator = (node) => {
    let element = node && (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement);
    const parts = [];
    while (element && element.nodeType === Node.ELEMENT_NODE && parts.length < 8) {
      const tag = element.tagName.toLowerCase();
      const siblings = Array.from(element.parentElement?.children || []).filter((item) => item.tagName === element.tagName);
      const index = siblings.indexOf(element) + 1;
      parts.unshift(`${tag}:nth-of-type(${Math.max(index, 1)})`);
      element = element.parentElement;
    }
    return parts.join(' > ');
  };
  return JSON.stringify({
    title: limit(document.title, 300),
    selectedText,
    selectedDomPath: limit(selection && selection.rangeCount ? locator(selection.anchorNode) : '', 1000),
    textPreview: limit(document.body?.innerText, 12000),
  });
})()
''';
