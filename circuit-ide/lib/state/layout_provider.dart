import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/constants/design_tokens.dart';
import '../core/utils/platform_utils.dart';

class IdeLayoutSizes {
  final double sidePanelWidth;
  final double chatPanelWidth;

  const IdeLayoutSizes({
    this.sidePanelWidth = LayoutDimensions.sidePanelDefaultWidth,
    this.chatPanelWidth = LayoutDimensions.chatPanelDefaultWidth,
  });

  IdeLayoutSizes copyWith({double? sidePanelWidth, double? chatPanelWidth}) {
    return IdeLayoutSizes(
      sidePanelWidth: sidePanelWidth ?? this.sidePanelWidth,
      chatPanelWidth: chatPanelWidth ?? this.chatPanelWidth,
    );
  }
}

class _LayoutStorage {
  static String get _filePath =>
      p.join(PlatformUtils.configDir, 'ide_layout.json');

  static Future<Map<String, dynamic>> read() async {
    try {
      final file = File(_filePath);
      if (!await file.exists()) return {};
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> write(Map<String, dynamic> patch) async {
    try {
      final dir = Directory(PlatformUtils.configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final existing = await read();
      existing.addAll(patch);
      await File(
        _filePath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(existing));
    } catch (_) {}
  }
}

class SidePanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    final data = await _LayoutStorage.read();
    final value = data['side_panel_visible'];
    if (value is bool) state = value;
  }

  void toggle() => set(!state);

  void set(bool value) {
    state = value;
    unawaited(_LayoutStorage.write({'side_panel_visible': value}));
  }
}

final sidePanelVisibleProvider =
    NotifierProvider<SidePanelVisibleNotifier, bool>(
      SidePanelVisibleNotifier.new,
    );

class ChatPanelVisibleNotifier extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    final data = await _LayoutStorage.read();
    final value = data['chat_panel_visible'];
    if (value is bool) state = value;
  }

  void toggle() => set(!state);

  void set(bool value) {
    state = value;
    unawaited(_LayoutStorage.write({'chat_panel_visible': value}));
  }
}

final chatPanelVisibleProvider =
    NotifierProvider<ChatPanelVisibleNotifier, bool>(
      ChatPanelVisibleNotifier.new,
    );

class IdeLayoutSizesNotifier extends Notifier<IdeLayoutSizes> {
  @override
  IdeLayoutSizes build() {
    unawaited(_load());
    return const IdeLayoutSizes();
  }

  Future<void> _load() async {
    final data = await _LayoutStorage.read();
    final sideWidth = (data['side_panel_width'] as num?)?.toDouble();
    final chatWidth = (data['chat_panel_width'] as num?)?.toDouble();
    state = state.copyWith(
      sidePanelWidth: sideWidth?.clamp(
        LayoutDimensions.sidePanelMinWidth,
        LayoutDimensions.sidePanelMaxWidth,
      ),
      chatPanelWidth: chatWidth?.clamp(
        LayoutDimensions.chatPanelMinWidth,
        LayoutDimensions.chatPanelMaxWidth,
      ),
    );
  }

  void setSidePanelWidth(double width) {
    final clamped = width.clamp(
      LayoutDimensions.sidePanelMinWidth,
      LayoutDimensions.sidePanelMaxWidth,
    );
    state = state.copyWith(sidePanelWidth: clamped);
    unawaited(_LayoutStorage.write({'side_panel_width': clamped}));
  }

  void setChatPanelWidth(double width) {
    final clamped = width.clamp(
      LayoutDimensions.chatPanelMinWidth,
      LayoutDimensions.chatPanelMaxWidth,
    );
    state = state.copyWith(chatPanelWidth: clamped);
    unawaited(_LayoutStorage.write({'chat_panel_width': clamped}));
  }
}

final ideLayoutSizesProvider =
    NotifierProvider<IdeLayoutSizesNotifier, IdeLayoutSizes>(
      IdeLayoutSizesNotifier.new,
    );
