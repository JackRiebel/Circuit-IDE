import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/platform_utils.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../models/chat_message.dart';
import '../../enums/message_role.dart';

class SessionData {
  final String name;
  final DateTime createdAt;
  final String model;
  final String workingDir;
  final bool autoApprove;
  final List<ChatMessage> history;
  final Map<String, dynamic> metadata;

  const SessionData({
    required this.name,
    required this.createdAt,
    required this.model,
    required this.workingDir,
    this.autoApprove = false,
    this.history = const [],
    this.metadata = const {},
  });
}

class SessionManager {
  static String get sessionsDir =>
      p.join(PlatformUtils.configDir, AppConstants.sessionsDirName);

  Future<void> save({
    required String name,
    required List<ChatMessage> history,
    required String model,
    required String workingDir,
    bool autoApprove = false,
    Map<String, dynamic> metadata = const {},
  }) async {
    final dir = Directory(sessionsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(sessionsDir, '$name.json'));
    final data = {
      'version': '3.0',
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
      'model': model,
      'working_dir': workingDir,
      'auto_approve': autoApprove,
      'metadata': metadata,
      'history': history
          .map((m) => {
                'id': m.id,
                'role': m.role.value,
                'content': m.content,
                'timestamp': m.timestamp.toIso8601String(),
                if (m.toolCallId != null) 'tool_call_id': m.toolCallId,
              })
          .toList(),
    };

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    Logger.info('Session saved: $name', 'SessionManager');
  }

  Future<SessionData?> load(String name) async {
    final file = File(p.join(sessionsDir, '$name.json'));
    if (!await file.exists()) return null;

    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      final historyJson = json['history'] as List<dynamic>;
      final history = historyJson.map((h) {
        final map = h as Map<String, dynamic>;
        return ChatMessage(
          id: map['id'] as String,
          role: MessageRole.values.firstWhere(
            (r) => r.value == map['role'],
            orElse: () => MessageRole.user,
          ),
          content: map['content'] as String,
          timestamp: DateTime.parse(map['timestamp'] as String),
          toolCallId: map['tool_call_id'] as String?,
        );
      }).toList();

      return SessionData(
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        model: json['model'] as String,
        workingDir: json['working_dir'] as String,
        autoApprove: json['auto_approve'] as bool? ?? false,
        history: history,
        metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      );
    } catch (e) {
      Logger.error('Failed to load session: $name', e);
      return null;
    }
  }

  Future<List<String>> listSessions() async {
    final dir = Directory(sessionsDir);
    if (!await dir.exists()) return [];

    final sessions = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        sessions.add(p.basenameWithoutExtension(entity.path));
      }
    }
    sessions.sort();
    return sessions.reversed.toList();
  }

  Future<bool> delete(String name) async {
    final file = File(p.join(sessionsDir, '$name.json'));
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  Future<String> autoSave({
    required List<ChatMessage> history,
    required String model,
    required String workingDir,
    bool autoApprove = false,
  }) async {
    final dirName = p.basename(workingDir);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final name = '$dirName-$timestamp';

    await save(
      name: name,
      history: history,
      model: model,
      workingDir: workingDir,
      autoApprove: autoApprove,
    );

    return name;
  }
}
