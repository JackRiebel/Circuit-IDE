import 'dart:io';

import 'package:flutter/services.dart';

enum CircuitUpdateChannel { stable, beta }

/// The small, user-visible state surface of Sparkle. Package verification,
/// download, install, and rollback remain in Sparkle's signed native path.
class CircuitUpdateStatus {
  final bool configured;
  final CircuitUpdateChannel channel;
  final bool automaticChecks;
  final bool automaticDownloads;
  final bool allowsAutomaticDownloads;
  final bool canCheck;
  final bool checkInProgress;
  final DateTime? lastCheckedAt;
  final bool mutationActive;
  final bool installDeferred;
  final String? message;

  const CircuitUpdateStatus({
    required this.configured,
    this.channel = CircuitUpdateChannel.stable,
    this.automaticChecks = false,
    this.automaticDownloads = false,
    this.allowsAutomaticDownloads = false,
    this.canCheck = false,
    this.checkInProgress = false,
    this.lastCheckedAt,
    this.mutationActive = false,
    this.installDeferred = false,
    this.message,
  });

  CircuitUpdateStatus copyWith({String? message}) => CircuitUpdateStatus(
    configured: configured,
    channel: channel,
    automaticChecks: automaticChecks,
    automaticDownloads: automaticDownloads,
    allowsAutomaticDownloads: allowsAutomaticDownloads,
    canCheck: canCheck,
    checkInProgress: checkInProgress,
    lastCheckedAt: lastCheckedAt,
    mutationActive: mutationActive,
    installDeferred: installDeferred,
    message: message ?? this.message,
  );

  factory CircuitUpdateStatus.fromPlatform(Object? raw) {
    if (raw is! Map) {
      return const CircuitUpdateStatus(
        configured: false,
        message: 'Update status is unavailable for this build.',
      );
    }
    final epoch = raw['lastCheckEpochMillis'];
    return CircuitUpdateStatus(
      configured: raw['configured'] == true,
      channel: CircuitUpdateChannel.values.firstWhere(
        (channel) => channel.name == raw['channel'],
        orElse: () => CircuitUpdateChannel.stable,
      ),
      automaticChecks: raw['automaticChecks'] == true,
      automaticDownloads: raw['automaticDownloads'] == true,
      allowsAutomaticDownloads: raw['allowsAutomaticDownloads'] == true,
      canCheck: raw['canCheck'] == true,
      checkInProgress: raw['checkInProgress'] == true,
      lastCheckedAt: epoch is num
          ? DateTime.fromMillisecondsSinceEpoch(epoch.toInt(), isUtc: true)
          : null,
      mutationActive: raw['mutationActive'] == true,
      installDeferred: raw['installDeferred'] == true,
      message: raw['message']?.toString(),
    );
  }
}

/// Narrow Dart bridge for the user-owned Sparkle updater. It accepts no feed
/// URLs, package paths, or executable commands from Studio, agents, or MCP.
class MacosUpdateService {
  final MethodChannel _channel;
  final bool Function() _isSupported;

  const MacosUpdateService({
    MethodChannel channel = const MethodChannel('circuitcode/updates'),
    bool Function()? isSupported,
  }) : _channel = channel,
       _isSupported = isSupported ?? _supportsMacos;

  static const platform = MacosUpdateService();

  Future<CircuitUpdateStatus> status() => _invokeStatus('status');

  Future<CircuitUpdateStatus> setChannel(CircuitUpdateChannel channel) =>
      _invokeStatus('setChannel', {'channel': channel.name});

  Future<CircuitUpdateStatus> setAutomaticChecks(bool enabled) =>
      _invokeStatus('setAutomaticChecks', {'enabled': enabled});

  Future<CircuitUpdateStatus> setAutomaticDownloads(bool enabled) =>
      _invokeStatus('setAutomaticDownloads', {'enabled': enabled});

  Future<CircuitUpdateStatus> setMutationActive(bool active) =>
      _invokeStatus('setMutationActive', {'active': active});

  Future<CircuitUpdateStatus> checkForUpdates() =>
      _invokeStatus('checkForUpdates');

  Future<CircuitUpdateStatus> _invokeStatus(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    if (!_isSupported()) {
      return const CircuitUpdateStatus(
        configured: false,
        message: 'Automatic updates are available only in the macOS app.',
      );
    }
    try {
      return CircuitUpdateStatus.fromPlatform(
        await _channel.invokeMethod<Object?>(method, arguments),
      );
    } on PlatformException catch (error) {
      return CircuitUpdateStatus.fromPlatform(error.details).copyWith(
        message: error.message ?? 'The signed update service is unavailable.',
      );
    } on MissingPluginException {
      return const CircuitUpdateStatus(
        configured: false,
        message: 'The signed update service is unavailable for this build.',
      );
    }
  }

  static bool _supportsMacos() => Platform.isMacOS;
}
