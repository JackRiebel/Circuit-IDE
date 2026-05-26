import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command_descriptor.dart';

typedef Command = CommandDescriptor;

class CommandPaletteState {
  final bool isOpen;
  final String query;
  final List<Command> allCommands;
  final List<Command> filteredCommands;
  final List<String> recentCommandIds;
  final String? categoryFilter;

  const CommandPaletteState({
    this.isOpen = false,
    this.query = '',
    this.allCommands = const [],
    this.filteredCommands = const [],
    this.recentCommandIds = const [],
    this.categoryFilter,
  });

  List<String> get categories {
    final values =
        allCommands.map((command) => command.category).toSet().toList()..sort();
    return values;
  }

  List<Command> get recentCommands {
    return recentCommandIds
        .map(
          (id) => allCommands.where((command) => command.id == id).firstOrNull,
        )
        .nonNulls
        .toList();
  }

  CommandPaletteState copyWith({
    bool? isOpen,
    String? query,
    List<Command>? allCommands,
    List<Command>? filteredCommands,
    List<String>? recentCommandIds,
    Object? categoryFilter = _sentinel,
  }) {
    return CommandPaletteState(
      isOpen: isOpen ?? this.isOpen,
      query: query ?? this.query,
      allCommands: allCommands ?? this.allCommands,
      filteredCommands: filteredCommands ?? this.filteredCommands,
      recentCommandIds: recentCommandIds ?? this.recentCommandIds,
      categoryFilter: identical(categoryFilter, _sentinel)
          ? this.categoryFilter
          : categoryFilter as String?,
    );
  }
}

class CommandPaletteNotifier extends Notifier<CommandPaletteState> {
  @override
  CommandPaletteState build() => const CommandPaletteState();

  void registerCommands(List<Command> commands) {
    state = state.copyWith(allCommands: commands, filteredCommands: commands);
  }

  void toggle() {
    state = state.copyWith(
      isOpen: !state.isOpen,
      query: '',
      filteredCommands: state.allCommands,
      categoryFilter: null,
    );
  }

  void open() {
    state = state.copyWith(
      isOpen: true,
      query: '',
      filteredCommands: state.allCommands,
      categoryFilter: null,
    );
  }

  void close() {
    state = state.copyWith(isOpen: false, query: '');
  }

  void filter(String query) {
    final lower = _normalize(query);
    final filtered =
        state.allCommands.where((cmd) {
          final categoryMatches =
              state.categoryFilter == null ||
              cmd.category == state.categoryFilter;
          if (!categoryMatches) return false;
          if (query.isEmpty) return true;
          return _normalize(cmd.title).contains(lower) ||
              _normalize(cmd.category).contains(lower) ||
              (cmd.description == null
                  ? false
                  : _normalize(cmd.description!).contains(lower));
        }).toList()..sort((a, b) {
          final aTitle = _normalize(a.title).startsWith(lower) ? 0 : 1;
          final bTitle = _normalize(b.title).startsWith(lower) ? 0 : 1;
          if (aTitle != bTitle) return aTitle.compareTo(bTitle);
          return a.title.compareTo(b.title);
        });

    state = state.copyWith(query: query, filteredCommands: filtered);
  }

  void setCategory(String? category) {
    state = state.copyWith(categoryFilter: category);
    filter(state.query);
  }

  void execute(Command command) {
    if (!command.enabled) return;
    final recent = [
      command.id,
      ...state.recentCommandIds.where((id) => id != command.id),
    ].take(6).toList();
    state = state.copyWith(recentCommandIds: recent);
    close();
    command.run();
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}

const _sentinel = Object();

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final commandPaletteProvider =
    NotifierProvider<CommandPaletteNotifier, CommandPaletteState>(
      CommandPaletteNotifier.new,
    );
