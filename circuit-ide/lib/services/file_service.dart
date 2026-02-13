import 'dart:async';

import 'package:watcher/watcher.dart';

import '../core/utils/debouncer.dart';
import '../core/utils/logger.dart';

class FileService {
  DirectoryWatcher? _watcher;
  StreamSubscription? _subscription;
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 500));
  void Function(String path, WatchEventType type)? onFileChanged;

  Future<void> watchDirectory(String path) async {
    await stopWatching();

    try {
      _watcher = DirectoryWatcher(path);
      _subscription = _watcher!.events.listen((event) {
        _debouncer.call(() {
          final type = switch (event.type) {
            ChangeType.ADD => WatchEventType.added,
            ChangeType.MODIFY => WatchEventType.modified,
            ChangeType.REMOVE => WatchEventType.removed,
            _ => WatchEventType.modified, // fallback
          };
          onFileChanged?.call(event.path, type);
        });
      });
      Logger.info('Watching directory: $path', 'FileService');
    } catch (e) {
      Logger.error('Failed to watch directory', e);
    }
  }

  Future<void> stopWatching() async {
    await _subscription?.cancel();
    _subscription = null;
    _watcher = null;
  }

  void dispose() {
    stopWatching();
    _debouncer.dispose();
  }
}

enum WatchEventType { added, modified, removed }
