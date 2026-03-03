import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OrchestrationStatus { idle, running, completed, failed }

class OrchestrationTask {
  final String id;
  final String name;
  final String task;
  final OrchestrationStatus status;
  final String? result;
  final String? error;
  final String streamingContent;
  final DateTime startedAt;
  final DateTime? completedAt;

  const OrchestrationTask({
    required this.id,
    required this.name,
    required this.task,
    this.status = OrchestrationStatus.running,
    this.result,
    this.error,
    this.streamingContent = '',
    required this.startedAt,
    this.completedAt,
  });

  OrchestrationTask copyWith({
    OrchestrationStatus? status,
    String? result,
    String? error,
    String? streamingContent,
    DateTime? completedAt,
  }) {
    return OrchestrationTask(
      id: id,
      name: name,
      task: task,
      status: status ?? this.status,
      result: result ?? this.result,
      error: error,
      streamingContent: streamingContent ?? this.streamingContent,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class OrchestrationState {
  final List<OrchestrationTask> tasks;

  const OrchestrationState({this.tasks = const []});

  OrchestrationState copyWith({List<OrchestrationTask>? tasks}) {
    return OrchestrationState(tasks: tasks ?? this.tasks);
  }

  bool get hasActive =>
      tasks.any((t) => t.status == OrchestrationStatus.running);

  List<OrchestrationTask> get activeTasks =>
      tasks.where((t) => t.status == OrchestrationStatus.running).toList();
}

class OrchestrationNotifier extends Notifier<OrchestrationState> {
  @override
  OrchestrationState build() => const OrchestrationState();

  void addTask(OrchestrationTask task) {
    state = state.copyWith(tasks: [...state.tasks, task]);
  }

  void updateTask(String id, OrchestrationTask Function(OrchestrationTask) updater) {
    final tasks = state.tasks.map((t) {
      if (t.id == id) return updater(t);
      return t;
    }).toList();
    state = state.copyWith(tasks: tasks);
  }

  void completeTask(String id, String result) {
    updateTask(id, (t) => t.copyWith(
      status: OrchestrationStatus.completed,
      result: result,
      completedAt: DateTime.now(),
    ));
  }

  void failTask(String id, String error) {
    updateTask(id, (t) => t.copyWith(
      status: OrchestrationStatus.failed,
      error: error,
      completedAt: DateTime.now(),
    ));
  }

  void clear() {
    state = const OrchestrationState();
  }
}

final orchestrationProvider =
    NotifierProvider<OrchestrationNotifier, OrchestrationState>(
  OrchestrationNotifier.new,
);
